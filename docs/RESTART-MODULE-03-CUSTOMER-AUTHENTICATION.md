# RESTART MODULE 03 — CUSTOMER LOGIN, REGISTRATION, OTP & SESSION

Captured 2026-09-14. Customer Web build `index-ZKYO5Ulo.js`.

## What this module actually had to build

The backend authentication was already complete and is **not** taken on trust
here — it was re-run. 58 existing tests cover hashing, expiry, replay, attempt
limits, rate limiting, suspension, role isolation, token revocation, phone
normalisation and account-enumeration protection, and all pass.

The gap Restart Module 02 recorded as **MF-17** was the web UI: a customer could
not sign in through a browser at all. That is what this module built, plus
sign-out, the signed-in `/login` redirect, and central 401 handling.

## Architecture, as it actually is

| | |
| --- | --- |
| Phone normalisation | `PhoneNormalizer` → `PhoneNumber` (E.164). One shared `PhoneFormRequest` for request and verify, so the two cannot normalise differently |
| Identity column | `users.phone_e164`, **UNIQUE** |
| Challenge | `otp_challenges` — uuid, phone_e164, otp_hash, expires_at, attempts, max_attempts, consumed_at, invalidated_at, resend_count, request_ip |
| Code generation | `random_int()` per digit — a CSPRNG, not `mt_rand` |
| Code storage | `hash_hmac('sha256', $code, config('app.key'))` — **never plaintext**. Verified in the database: 64-character hex, no readable codes |
| Provider | `OtpDeliveryProvider` interface. `log` in development; `TwilioOtpProvider` built and tested, awaiting credentials |
| Session | Laravel Sanctum personal access tokens, ability-scoped `customer` |
| Web storage | `sessionStorage`, cleared when the tab closes |
| Mobile storage | `flutter_secure_storage` — Keychain on iOS, Keystore-backed on Android |

## Configured values — actual, not recommended

| Setting | Value | Env key |
| --- | --: | --- |
| Code length | 6 | `OTP_LENGTH` |
| Time to live | 300 s | `OTP_TTL_SECONDS` |
| Max wrong attempts | 5 | `OTP_MAX_ATTEMPTS` |
| Resend cooldown | 30 s | `OTP_RESEND_COOLDOWN_SECONDS` |
| Requests per number | 5 / hour | `OTP_MAX_REQUESTS_PER_PHONE` |
| Requests per IP | 20 / hour | `OTP_MAX_REQUESTS_PER_IP` |
| Registration token TTL | 900 s | `OTP_REGISTRATION_TOKEN_TTL_SECONDS` |

## Production OTP bypass: **DISABLED — structurally impossible**

Three independent defences, each with a test that fails if it is removed:

1. `LogOtpProvider::__construct()` **throws** when the environment is
   `production`. The class cannot be instantiated there.
2. It reports `deliversToRealDevices() === false`, and `ProductionConfigGuard`
   refuses to boot a production deployment on a provider that says so.
3. The unconfigured default provider sends nothing rather than pretending.

There is no master code, no fixed test code, and no environment flag that turns
verification off. The development path is "the server writes the code to a
dedicated log channel", which is a different mechanism, not a weaker check — the
code is still generated, hashed, expired, attempt-limited and consumed exactly as
in production.

## Log hygiene, measured

- Plaintext codes in the application log: **0** across every log file.
- Plaintext codes in `otp-development.log`: 693 — that is the channel's entire
  purpose, it is separate from the structured application log by design, and the
  provider that writes it cannot exist in production.
- Phone numbers are logged masked (`+91 ••••••2736`); the full E.164 appears only
  in the same development-only channel.
- No token appears in any log.

## The web flow

One component, one state machine: `phone → otp → register`. The step is
deliberately **not** in the URL — `/verify-otp` reached from a bookmark or a back
button has no challenge behind it and could only fail — and neither is the phone
number, which would otherwise land in browser history, server access logs and the
`Referer` header.

Post-sign-in redirect uses only the path the guard stored, rejecting anything not
beginning with a single `/`. An open redirect needs an attacker-supplied target,
and there is no query parameter here that supplies one.

## Verified live, end to end

A **new** customer and an **existing** customer both signed in through a real
browser against the real API. Codes were read from the server's log, never from
the UI.

| Scenario | Result |
| --- | --- |
| New number → code → **wrong code rejected** → correct code → registration → Home | **PASS** — landed on "Good afternoon, Meera" |
| Masked number shown | **PASS** — `+91 ••••••1122`, from the server |
| Existing number → straight Home, no registration | **PASS** — "Good afternoon, Rahul" |
| Account isolation | **PASS** — no trace of the previous customer's name |
| Browser refresh | **PASS** — session restored |
| Signed-in customer opens `/login` | **PASS** — redirected to `/`, no form |
| Sign out | **PASS** — token cleared, back button does **not** reopen Home |
| Revoked/forged token | **PASS** — cleared and sent to sign-in, centrally |
| 360 → 1920 | **PASS** — no horizontal overflow at any width |

Database after the run: one row per number, no duplicates; new accounts carry
`role=customer`, `status=active` — both assigned by the server, neither accepted
from the request.

## Not claimed

- **Android and iOS were not inspected by a person.** No SDK, emulator or Apple
  hardware is reachable here. The Flutter auth flow is unchanged by this module
  and its 29 on-device integration tests run in CI on every pull request.
  **iOS RESTART MODULE 03 = PENDING — RUNTIME ENVIRONMENT UNAVAILABLE.**
- **No SMS has been sent.** `OTP_PROVIDER=log`. Real delivery needs Twilio
  credentials and, for India, DLT registration.
- **Suspended and disabled accounts** are covered by backend tests
  (`a suspended customer cannot sign in with a correct code`) but were not driven
  through the browser — no suspended fixture exists in the local database.
- **Duplicate-registration race** is covered by a backend test
  (`a retried registration returns the same account rather than a second one`),
  not by concurrent browser tabs.

## Review authentication

No credentials are provided, because there are none: authentication is phone plus
a one-time code. There is no password and **no fake credential is invented**.

To sign in to a review build: enter a number, then read the code from the server:

```
docker compose exec php tail -n 1 storage/logs/otp-development.log
```

**This mechanism does not exist in production**, for the three reasons above.
