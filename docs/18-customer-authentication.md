# 18 — Customer authentication

How a traveller proves who they are, and why each part is built the way it is.

Module 03. Read [05-api-standards.md](05-api-standards.md) for the envelope and error contract, and
[07-security.md](07-security.md) for the platform-wide rules this sits inside.

---

## The shape of it

A customer signs in with a **phone number and a one-time code**. There is no password anywhere in
the flow, and `users.password` is `NULL` for every customer account.

That trade is deliberate, and it cuts both ways:

- **What it removes.** No password to reuse from a breached site, no reset flow to phish, no hash to
  crack in a database dump, no "forgot password" support queue. For a product whose customers order
  once a month from a moving vehicle, a password is friction that buys nothing.
- **What it costs.** The OTP endpoints become the attack surface, and SMS delivery becomes a
  dependency with a per-message cost. Most of this module is about those two facts.

Three endpoints and two more behind a token:

| Method | Path | Auth | What it does |
| --- | --- | --- | --- |
| POST | `/api/v1/auth/customer/otp/request` | none | Sends a code |
| POST | `/api/v1/auth/customer/otp/verify` | none | Signs in, or starts registration |
| POST | `/api/v1/auth/customer/register` | registration token | Creates the account |
| GET | `/api/v1/customer/me` | Bearer | The signed-in customer |
| POST | `/api/v1/auth/logout` | Bearer | Revokes this token |

---

## Phone numbers

**E.164 is the identity.** `+919876543210`. Everything else is presentation.

`98765 43210`, `+91 98765-43210` and `09876543210` are one subscriber. If they became three
accounts, that customer would have three order histories and a support ticket nobody could resolve —
so normalization happens on the way in and a unique index on `users.phone_e164` is what actually
guarantees it. Not a `SELECT` then an `INSERT`, which races.

The client normalizes too (`lib/core/phone/`), for a numeric keyboard and instant feedback. It is
not validation: `App\Support\Phone\PhoneNormalizer` re-does the work and its answer is the one that
counts. A modified client cannot get a different number stored.

Supported markets live in one table on each side, mirrored deliberately rather than fetched — the
country picker has to render on a cold start with no network:

| Code | Country | National digits | Mobile prefixes |
| --- | --- | --- | --- |
| +91 | India | 10 | 6, 7, 8, 9 |
| +971 | United Arab Emirates | 9 | 5 |
| +44 | United Kingdom | 10 | 7 |
| +1 | United States | 10 | (any) |

Adding a market is a row in `PhoneNormalizer::COUNTRIES`, a row in `SupportedCountry.all`, and a
test. The mobile-prefix rule is not pedantry: an Indian landline number cannot receive an SMS, so
accepting one means charging ourselves for a message and leaving a customer waiting for a code that
will never arrive.

**Masking.** `PhoneNumber::masked()` and `maskE164()` in Dart produce the same string —
`+91 ••••••3210`. Both exist because both sides display numbers, and one number masked two ways
reads as two numbers. The calling code stays visible: it is not identifying on its own, and it tells
a customer with numbers in two countries which one this is. The full number never appears in a log
line, an error message, or a screen — not even on the account's own profile.

---

## The code itself

`App\Services\Otp\OtpChallengeService` owns every rule. The properties it guarantees, each with a
test in `tests/Unit/OtpChallengeServiceTest.php`:

**Generated with a CSPRNG.** `random_int`, never `rand` or `mt_rand` — those are seeded predictably
and an attacker who observes a few codes can predict the next.

**Stored as a peppered hash.** `hash_hmac('sha256', $code, config('app.key'))`. The pepper lives in
the environment, not the database, so a dumped `otp_challenges` table cannot be brute-forced offline
even though a six-digit space is tiny. bcrypt is deliberately *not* used: it would put a ~100 ms
cost on a request that happens on every single sign-in, and the pepper already defeats the offline
attack that bcrypt would be defending against.

**Compared in constant time.** `hash_equals`, so response timing does not leak a prefix.

**Counted before it is compared.** `attempts` is incremented *before* the comparison. Incrementing
afterwards would let a client that disconnects mid-request guess indefinitely for free.

**Dead once exhausted.** After `max_attempts` wrong guesses the challenge is invalidated, and the
*correct* code stops working too. Otherwise an attacker who burns the counter could simply wait for
the real customer to be locked out and keep trying elsewhere.

**One live code at a time.** Requesting a new code invalidates the previous one. Two valid codes at
once doubles an attacker's odds for no benefit to a customer who is looking at the newest SMS
anyway.

**Never anywhere else.** The code exists as a local variable inside `issue()`. It is not returned,
not stored in plaintext, not put in an exception message, and not logged. `AuthLoggingTest` runs a
complete sign-up and greps the log file on disk to prove it.

The attempt counter lives in **MySQL on the challenge row**, not in Redis. That is the one place
this module refuses the faster option: losing a rate-limit counter on a Redis flush is merely
generous, while losing an attempt counter would hand an attacker unlimited guesses.

Configuration is entirely in `config/foodonthego.php` under `otp`. Nothing in the codebase compares
against a literal `6` or `300`.

---

## Registration is bound to the verification

The attack: verify a number you control, then post a registration naming somebody else's number and
take their account.

The defence is structural rather than a check. `POST /auth/customer/register` takes a
**registration token** and **has no `phone` field at all** — `CustomerRegisterRequest` declares no
rule for one, `AuthRepository.register()` in Dart has no parameter for one, and the registration
screen has no field for one. There is nowhere in the client for a substituted number to travel.

The token is `Crypt::encryptString` (AES-256-GCM with a MAC) over the challenge UUID, the verified
E.164 number, and an issue time. On the way back in, `RegistrationTokenService::verifiedPhoneFor()`
requires all of:

1. it decrypts and parses — a forged or altered token fails the MAC;
2. it is inside its TTL (15 minutes);
3. the challenge it names still exists **and was actually consumed** by a successful verification;
4. the phone inside the token still matches that challenge's row.

Point 4 is what stops a caller who reaches the token-minting path from claiming a number they did
not verify.

---

## Rate limiting, in two layers

**Per phone and per IP** (`OtpRateLimiter`, Redis-backed). Both, because they stop different things:
the per-phone limit stops somebody burning our SMS budget harassing one person; the per-IP limit
stops one client walking a range of numbers, which the per-phone limit would happily allow since
each number is only asked for once. Keys are hashed, so a Redis dump does not enumerate customers.

**A resend cooldown** (30 s), enforced from the server clock and checked *before* the rate limiter
is charged — a customer who taps twice inside the cooldown should not also be counted as an abuser.
The client countdown is a courtesy; a device with a wrong clock just sees a countdown that does not
match.

**A coarse per-IP HTTP throttle** on the routes themselves, far below the general public allowance,
so a flood never reaches the database at all.

Rate-limit responses carry `retry_after_seconds` — a client needs it to show a sensible countdown —
and never the threshold. "5 per hour" hands an attacker the shape of the limit to work around.
`OTP_RESEND_TOO_SOON` and `OTP_RATE_LIMITED` both return 429 on purpose, so a caller cannot
distinguish "too soon" from "too many".

---

## Account enumeration

`POST /otp/request` returns a **byte-identical response shape** whether or not an account exists.
Returning "new user" there would make the endpoint a free directory of who has a FoodOnTheGo
account: walk a range of numbers, read off the customer list.

Whether registration is needed is answered by `/otp/verify` — *after* the caller has proved control
of the number, at which point telling them about their own account discloses nothing.

Account status is the same idea in reverse: a `deleted` account reports as `ACCOUNT_DISABLED`, not
as deleted. "Deleted" would confirm to whoever now holds that number that an account once existed.

---

## Sessions

Laravel Sanctum personal access tokens. A customer token is created with the single ability
`customer` and an explicit 30-day expiry — long enough that a traveller is not signed out mid-
journey, short enough that a lost handset stops working.

The database stores `hash('sha256', $plaintext)`. A dumped `personal_access_tokens` table is not a
set of working credentials.

`config/sanctum.php` sets `'guard' => []`, overriding Laravel's default of `['web']`. Every client
is a bearer-token client, so a session cookie must never authenticate an API request — leaving the
web guard in place would make every state-changing `/api` route reachable with an ambient cookie,
which is exactly the shape CSRF exploits.

**Two gates, always.** Authenticated routes carry `auth:sanctum` *and* `role:customer` *and*
`abilities:customer`. Authentication answers "who is this"; the role answers "does that kind of
account belong here at all"; the ability answers "was this particular token minted for this work".
A valid customer token is a perfectly good credential with no business reaching a restaurant's order
queue. `AuthorizationBoundaryTest` registers restaurant- and admin-shaped routes with exactly the
middleware those modules will use and proves a customer token gets 403 — the gate is tested before
there is anything behind it, so the first restaurant route inherits a guard that works rather than
one that was intended.

Logout revokes **only the current token**. Signing out on a phone must not sign a customer out of a
tablet they left at home.

---

## On the device

Tokens go to the **iOS Keychain** (`first_unlock_this_device` — not synced to iCloud, not restored
to a different handset from a backup) and to **Android's KeyStore-backed encrypted storage**. Never
to `SharedPreferences` in the clear, which is world-readable on a rooted device; never to a log
line; never to an analytics event. `AuthSession` overrides `toString()` so a stray `debugPrint`
cannot leak the bearer token.

**Restore on launch does both halves.** The stored session is shown immediately (so a returning
customer sees their name, not a spinner), and then confirmed with `/customer/me`. Trusting storage
alone would show a signed-in shell to somebody whose token was revoked while the app was closed, and
then 401 on the first real request. Requiring the network would lock a customer out in a tunnel — so
a request that fails to *reach* the server keeps the session, and only the server actually saying no
ends it. A stored token past its stated expiry is discarded without a request at all.

`SessionSplash` covers the restore, so no frame ever shows the welcome screen to a signed-in
customer or the home screen to a signed-out one.

**One 401 ends the session everywhere.** `ApiClient` reports a failed *authenticated* request to
`AuthController`, which clears storage and flips the router guard. A 401 from the OTP endpoints does
not: there, it means "wrong code", not "your session ended". `FORBIDDEN` does not either — being
refused one endpoint is not a dead credential, and signing somebody out over a permission check
would be both wrong and confusing.

**Sign-out clears locally first**, then revokes best-effort. If the server call fails the customer is
still signed out on this device: the moment somebody hands their phone over is the moment that
button must not depend on the network.

**The app branches on error codes, never on prose.** `ApiErrorCode` mirrors the backend enum and
`authErrorMessage()` is the single mapping to wording. The server's message is written for a person
and expected to be reworded or translated; a client that parses it breaks the first time somebody
improves it. A code this build has never seen degrades to a generic message rather than crashing, so
a newer server does not break an older app.

---

## What is deliberately not here

Belongs to later modules, and building any of it now would mean shipping a screen that silently
discards what somebody typed:

- avatars, social sign-in, email/password, biometric unlock
- changing the verified phone number — see below
- multi-device session management beyond one-token revocation
- account deletion and data export (Module 17)

One thing worth naming as a gap rather than a decision: **suspending an account does not revoke its
existing tokens.** Sanctum tokens are bearer credentials and this module does not re-check status on
every request. The admin tooling that suspends an account is responsible for deleting its tokens,
and that module does not exist yet — recorded as KI-006 and pinned by a test that documents the
current behaviour honestly rather than pretending otherwise.

---

## The verified number is identity, not profile

Module 04 added profile editing, and the verified number is deliberately not part of it. It is
displayed read-only, and **no route changes it** — not a `PATCH` with the field in the body, not an
admin-shaped path, nothing. A payload carrying `phone_e164` is not rejected; the field is simply
never read, so the request succeeds and the number is unchanged. This is asserted by a test and by an
assertion in the live integration run, and confirmed by reading the column back out of MySQL.

The number is the account. Everything Module 03 built — the challenge, the encrypted registration
token, the binding between the verified number and the session — exists to establish that this device
belongs to that number. A form field that overwrote it would discard all of it in one `PATCH`.

Changing a number is therefore a flow of its own: verify the new number with a fresh OTP challenge,
confirm the old one still has a live session, then move the account. It belongs with the module that
also handles account recovery, and until then a customer who has changed numbers is a support case
rather than a silent overwrite.

The email address is the opposite kind of field: optional, editable, and **never trusted**. Changing
it clears `email_verified_at`, and the app does not display "verified" beside an email until an actual
verification flow exists to earn the word.

---

## Retention

`php artisan otp:prune` runs daily and deletes challenges that can no longer be used, after a 48-hour
grace period. A dead challenge is a record that a particular number tried to sign in at a particular
time — personal data with no product use, and one more thing a database compromise would disclose.

A live challenge is never pruned however old the row is: deleting one mid-verification would show
"code expired" to somebody looking at the SMS on their screen. Pruning also never touches the
rate-limit counters, which would hand an attacker a fresh budget.

---

## The development sender

`LogOtpProvider` writes codes to a dedicated `otp-development` log channel so a developer can
complete the flow without an SMS gateway. It is the most dangerous class in the module, so it has
three independent protections:

1. its constructor **throws** if the environment is `production`;
2. `deliversToRealDevices()` returns `false`, and `ProductionConfigGuard` refuses to boot a
   production or staging deployment on any provider that reports `false`;
3. it writes to its own channel, so a code never lands in the structured log that ships to an
   aggregator.

The default when `OTP_PROVIDER` is unset is `UnconfiguredOtpProvider`, which always fails loudly.
The failure this prevents has happened to other people: a release goes out still wired to a
development sender, every sign-in "succeeds" at the API while no SMS is ever sent, and the codes sit
in a file on a production host where anyone with read access can sign in as any customer who has
ever requested one.

Test numbers use the Indian range reserved for documentation (`+919999900000`–`+919999999999`), so a
code can never reach a real person's handset even if a real provider were configured by mistake.
