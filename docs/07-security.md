# 07 — Security

## Secrets

No credential is ever committed. `backend/.env` and `web/apps/*/.env*` (except `.env.example`) are
gitignored. `.env.example` contains placeholders only.

If a secret is ever committed: rotate it first, then rewrite history. Removing it from `HEAD` does
nothing — it is in the clone every developer already has.

## Roles

Seven roles in `App\Enums\Role`, stored as strings so a database row is self-describing and
re-ordering the enum cannot silently promote anyone.

`customer`, `restaurant_owner`, `restaurant_manager`, `restaurant_staff`, `support_agent`, `admin`,
`super_admin`.

**Authorisation is enforced server-side.** Hiding a button is a courtesy to the user, never a
control: the endpoint is reachable with `curl` regardless. Every future module authorises in the
request path.

New accounts default to `customer` — the least privileged role — and role escalation is never
self-service.

## Transport and headers

Every API response carries:

| Header | Value |
| --- | --- |
| `X-Content-Type-Options` | `nosniff` |
| `X-Frame-Options` | `DENY` |
| `Referrer-Policy` | `no-referrer` |
| `Cross-Origin-Resource-Policy` | `same-site` |
| `Permissions-Policy` | `geolocation=(), camera=(), microphone=()` |
| `Content-Security-Policy` | `default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'` |
| `Cache-Control` | `no-store, private` |
| `Strict-Transport-Security` | only over TLS |

The API serves no HTML, so the restrictive CSP is correct: a response coaxed into rendering as a
document cannot execute anything. HSTS is withheld over plain HTTP so local development does not pin
a developer's browser to `https://localhost` for a year.

## CORS

An exact-match allow-list from `FRONTEND_URLS`, never a reflection of the inbound `Origin`.
`supports_credentials` is on, which is precisely why a wildcard origin is refused at boot: wildcard
plus credentials is the configuration that leaks them.

## Authentication and sessions

The customer flow, its threat model and every decision behind it are documented in
[18-customer-authentication.md](18-customer-authentication.md). The rules that matter platform-wide:

- One-time codes are generated with `random_int`, stored as a **peppered SHA-256 HMAC** (the pepper
  is `APP_KEY`, which is not in the database), and compared with `hash_equals`.
- A code is never returned, logged, or stored in plaintext. The attempt counter lives in **MySQL**,
  not Redis — losing a rate-limit counter is generous, losing an attempt counter is dangerous.
- Registration is bound to the completed challenge by an encrypted token. The registration endpoint
  accepts **no phone number at all**, so verifying one number and registering another is not a check
  that could be forgotten — it is structurally impossible.
- Access tokens are stored as `sha256` hashes, carry a single ability, and expire.
- The OTP request response is identical whether or not an account exists (no enumeration).
- A production or staging deployment **refuses to boot** on an OTP sender that reports it cannot
  reach a real handset, and the development sender refuses to be constructed in production at all.

## Owning your own data

Module 04 is the first module where one customer's request could, if written carelessly, reach
another customer's row. Four controls, each independent of the others:

- **No identifier to tamper with.** Self-service routes name the resource, never the owner:
  `PATCH /api/v1/customer/profile`, `DELETE /api/v1/customer/addresses/{uuid}`. The owner comes from
  the Sanctum token. There is no `customer_id` in any path, query or body that the server reads.
- **One door to an address.** Every handler reaches a row through
  `CustomerAddressService::ownedByOrFail()`, which scopes by the authenticated customer before it
  looks anything up. Not-found and not-yours return the identical 404 body, so the endpoint is not an
  oracle for which identifiers exist. A denied attempt logs `address.access_denied` with the actor id
  and the requested uuid, and no address content.
- **Allow-lists, three deep.** The form request declares the three fields a customer may send
  (`first_name`, `last_name`, `email`); the model's `$fillable` excludes `customer_id`, `uuid` and
  `is_default`; and the service reads keys by name rather than passing an array through. A payload
  carrying `phone_e164`, `phone_verified_at`, `role`, `status`, `created_at` or `customer_id`
  succeeds and changes none of them, because nothing ever reads them.
- **The verified phone is identity, not profile.** It is displayed read-only and there is no route
  that changes it. Changing a verified number will be a re-verification flow of its own, not a field
  in a form.

Changing the email address clears `email_verified_at`. The app never labels an email verified on the
strength of the customer having typed it.

### Addresses are sensitive

A saved address is where someone lives. It is treated as application-sensitive data, not as ordinary
content: it is returned only to its owner, never included in an analytics event, and never written to
a log. Operational logs for this module carry record ids and actor ids and nothing else — verified
against the real 1,634-line application log, which contains zero address lines, zero email addresses
and zero complete phone numbers.

**Coordinates are never invented.** If geocoding has not run, `latitude` and `longitude` are `NULL`.
A plausible-looking coordinate derived from a text address is worse than no coordinate, because the
routing module in Module 05 would trust it.

### Cache isolation between accounts

The Flutter addresses provider watches the auth session rather than listening for a logout event, so
the session ending disposes the state; there is no per-customer cache that can outlive the customer.
Verified end-to-end: signing out of one account and into another shows no trace of the first, not
even for a frame.

## Logging

Structured JSON, one object per line, carrying `request_id`, `actor_id` and `actor_role`.

**Redaction happens in the formatter, not at the call site.** A call site that forgets is the normal
case, and a password on disk cannot be un-written. Any key containing `password`, `secret`, `token`,
`authorization`, `auth`, `otp`, `pin`, `cvv`, `cvc`, `card`, `pan`, `api_key`, `private_key`,
`credential`, `session`, `cookie` or `signature` is replaced with `[REDACTED]`, case-insensitively,
at every depth. Recursion is bounded so a cyclic payload cannot turn a log write into a crash.

Request **bodies are never logged at all**. The formatter would redact known keys, but the safer
default for an API that will carry addresses, payment intents and OTPs is not to write them.

## Input validation

Every endpoint validates before acting. A validation failure returns `VALIDATION_FAILED` with the
offending fields — all of them, not the first.

## Rate limiting and idempotency

See [05-api-standards.md](05-api-standards.md). Both are security controls: the first limits
brute-force and scraping, the second prevents a retried payment being charged twice.

## Not yet built

Named rather than implied:

- **Authentication for the restaurant and admin surfaces** — those shells still render
  clearly-labelled test personas. The **customer** surface is built: phone + OTP, Sanctum sessions,
  role and ability gates. See [18-customer-authentication.md](18-customer-authentication.md).
- **Token revocation on account suspension** — a suspended account cannot obtain a new session, but
  an existing token keeps working until it expires. KI-008; the fix belongs with the admin module
  that does the suspending.
- **Per-resource authorisation policies** — with the modules that own the resources. Module 04's
  saved addresses are authorised in one service method rather than a policy class; a policy layer
  arrives with the first resource that more than one role can reach.
- **Email verification** — an email address on a profile is stored unverified and shown unverified.
- **Address geocoding** — no Places or Geocoding call is made yet, so coordinates stay `NULL`.
- **File upload scanning** — with the first module that accepts an upload.
- **Webhook signature verification** — with the payment module.
- **Audit log** — Module 18.

## Dependency security

`composer audit` and `npm audit` run in CI. The build fails on a high or critical advisory.

**Known gap:** PHPStan/Larastan could not be installed in the build environment used for Module 01 —
Composer's dist downloads resolve to GitHub zipball URLs, which that environment's egress policy
denies. Static analysis for PHP is therefore **not** in CI yet. Laravel Pint (code style) runs in its
place. This is a real gap, tracked in [13-known-issues.md](13-known-issues.md).
