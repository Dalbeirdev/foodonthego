# 19 — Customer profile and saved addresses

What a customer may change about themselves, where they save the places they
travel from, and why each boundary is where it is.

Module 04. Read [18-customer-authentication.md](18-customer-authentication.md)
first — the identity this builds on is established there.

---

## What a customer owns

Three fields: **first name, last name, email**. That is the whole editable
surface, and the list is short deliberately.

| Field | Editable | Required | Validated | Why |
| --- | --- | --- | --- | --- |
| `first_name` | ✅ | ✅ | 1–80 chars, must contain a letter | The name the kitchen reads out |
| `last_name` | ✅ | ➖ | ≤ 80 chars | Plenty of people have one name |
| `email` | ✅ | ➖ | RFC syntax, unique | Receipts, and nothing else |
| `phone_e164` | ❌ | — | — | **Identity.** See below |
| `phone_verified_at` | ❌ | — | — | Set by an OTP, never by a request |
| `role`, `status` | ❌ | — | — | Privilege, not self-service |

Nothing else is collected. No date of birth, no gender, no government id, no
workplace, no contacts, no location history. A field that is not collected
cannot be leaked, cannot be wrong, and cannot need a deletion process.

### The verified number is not a profile field

`PATCH /customer/profile` accepts a body containing `phone_e164` and changes
nothing. That is enforced in three independent places, and any one of them would
be enough:

1. `UpdateProfileRequest` declares no rule for it, so `validated()` never
   contains the key;
2. `CustomerProfileService::update()` reads three keys by name;
3. `User::$fillable` would refuse it anyway.

Three, because a change to one of them should not become a vulnerability.

The request is **accepted and ignored**, not rejected. Rejecting would tell a
prober which field names the server finds interesting.

Changing a mobile number is a real requirement and will be a real feature: an
OTP re-verification flow of its own, in a later module. It is never a PATCH.

### Changing an email un-verifies it

`email_verified_at` is cleared whenever the address changes. There is no email
verification flow yet, so in practice it is always null — this exists so that
adding one later cannot leave a "verified" flag attached to an address somebody
swapped in afterwards.

Nothing in the UI says an email is verified, because nothing verifies it.

---

## Saved addresses

A customer saves the places they travel from. Module 05's trip planner will offer
them as one-tap origins and destinations, which is why the shape here is
structured rather than a free-text blob.

### The data

```
id · uuid · customer_id · type · label
address_line_1 · address_line_2 · landmark · city · state · postal_code · country_code
formatted_address
latitude · longitude · place_id
is_default · created_at · updated_at
```

`type` is `HOME`, `WORK` or `OTHER` — a fixed set, because the trip planner
cannot offer "Home" as a one-tap origin against a string somebody typed. What the
customer *calls* the place is `label`, which is free text, required for `OTHER`
and defaulted from the type otherwise. "Other" in a list of three Others is
unreadable.

`formatted_address` is composed by the server from the parts, so the app and the
server never disagree about one address. The landmark is deliberately left out of
it: it helps somebody find the door and is shown beside the address, but inside a
one-line address it is noise and useless to a geocoder.

### At most one default, guaranteed by the database

```sql
default_for_customer BIGINT UNSIGNED
  GENERATED ALWAYS AS (IF(is_default = 1, customer_id, NULL)) STORED,
UNIQUE KEY customer_addresses_one_default_unique (default_for_customer)
```

MySQL has no partial indexes, so the generated column holds the customer id only
while the row is the default and NULL otherwise — and MySQL does not collide
NULLs in a unique index. Two concurrent "make this my default" requests cannot
both win, whatever the application does.

`CustomerAddressService` still takes a row lock inside a transaction, because a
clean error beats a constraint violation. But that is the second line of defence,
not the only one, and a test asserts the guarantee by writing around the service
entirely.

**The cost, stated plainly.** MySQL refuses `ON DELETE CASCADE` on a column that
a stored generated column depends on (error 1215), so the foreign key is
`RESTRICT`. Erasing a customer must delete their addresses first. That is the
better trade: a hard delete with addresses still attached fails loudly instead of
silently destroying them, and an erasure path needs an explicit audit trail
anyway.

### The default rules

- **The first address a customer saves becomes their default**, whether or not
  they asked. A list with no default makes the trip planner ask "from where?" to
  somebody who has already answered that once.
- **Setting a new default clears the old one**, inside one transaction.
- **Deleting the default promotes the newest survivor**, deterministically. The
  newest is the best available guess at where somebody is living or working now.
- **`PATCH {"is_default": false}` is ignored.** Un-defaulting by PATCH would
  leave a customer with addresses and no default, which every other rule works to
  avoid. Choosing a different default is what setting one on another address is
  for.
- Deleting the *last* address leaves no default, which is correct — there is
  nothing to promote.

### Deletion is permanent

Hard delete, not soft. An address is personal location data, and a customer who
removes one has asked for it to be gone; keeping a hidden copy is the opposite of
what they said.

**This places a requirement on the order and trip modules**: a historical order or
trip must store a *snapshot* of the address it used, not a reference to a mutable
row. That is the correct design regardless — an order shipped to an address the
customer has since edited should show the address it was shipped to.

### Limits

`ADDRESS_MAX_PER_CUSTOMER`, default 25. An anti-abuse ceiling rather than a
product limit: a traveller with home, work, two sets of parents and a few regular
stops is nowhere near it, and an account cannot be used as free storage. It is
configuration, so it can move without a deployment of new code.

---

## Postal codes are per country

"Six digits" is an Indian rule, not a universal one. The UK's are alphanumeric
and contain a space; Ireland's Eircodes are seven alphanumerics; the UAE has no
postal code system in general use.

| Country | Rule | Required |
| --- | --- | --- |
| IN | `[1-9]\d{5}` | ✅ |
| GB | outward + inward, optional space | ✅ |
| US | `\d{5}(-\d{4})?` | ✅ |
| AE | — | ❌ |
| anything else | length only | ❌ |

A country with no rule is **accepted**, not blocked. An address that cannot be
saved is a worse failure than a postcode nobody checked, and the launch market is
covered exactly.

The client mirrors this table (`postal_code_rules.dart`) so the form can pick a
keyboard and give feedback before the first keystroke reaches a server. It is
only ever allowed to be more permissive than the server, never less — a client
stricter than the server rejects addresses that are actually valid. The numeric
keypad appears only where the format is numeric, because a UK postcode typed on
one cannot be entered at all.

---

## Ownership

**No route carries a customer id.** Not `PATCH /customer/profile/{id}`, not
`GET /customer/{id}/addresses`. The actor is the token, so there is no ownership
check to forget and no id for a caller to change.

Addresses are reached only through `CustomerAddressService::ownedByOrFail()`,
which queries a scope already bound to the caller. Route-model binding would load
the row first and leave the ownership check as a separate step somebody could
omit; this way there is one path to an address and it cannot return one belonging
to anybody else.

**An address owned by somebody else and an address that does not exist give the
identical answer**: 404 `ADDRESS_NOT_FOUND`, with the same message. Distinguishing
them would turn the endpoint into an oracle — walk a range of ids, and
403-versus-404 maps out which ones are real addresses belonging to real customers.

`customer_id` in a request body is inert. It is not fillable on the model, the
form request declares no rule for it, and the service sets ownership from the
authenticated actor. `AddressOwnershipTest` sends `customer_id`, `user_id`,
`customer_uuid` and `created_by` in one payload and asserts the address belongs
to the caller.

---

## The API

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/api/v1/customer/profile` | The signed-in customer |
| PATCH | `/api/v1/customer/profile` | Name and email, nothing else |
| GET | `/api/v1/customer/addresses` | Their addresses, default first |
| POST | `/api/v1/customer/addresses` | Save one |
| GET | `/api/v1/customer/addresses/{uuid}` | One of theirs |
| PATCH | `/api/v1/customer/addresses/{uuid}` | Change one |
| DELETE | `/api/v1/customer/addresses/{uuid}` | Remove one |
| POST | `/api/v1/customer/addresses/{uuid}/default` | Make it the default |

Every one requires `auth:sanctum` + `role:customer` + `abilities:customer`, the
three gates established in Module 03.

Setting the default has **both** a dedicated endpoint and `PATCH {"is_default":
true}`, because they are different intents. The dedicated one changes nothing
else and is safe to retry, which matters for a control somebody taps in a list.

`POST /customer/addresses` honours Module 01's `Idempotency-Key`, so a client
that retries a lost response gets the same address rather than a second one.

New error codes: `ADDRESS_NOT_FOUND` (404) and `ADDRESS_LIMIT_REACHED` (422).

---

## Locating an address — connected in Module 05

The schema carries `latitude`, `longitude`, `place_id` and `formatted_address`
because the trip planner needs to route between saved addresses.

**They stay NULL until the customer locates the address.** Inventing coordinates
from a typed address would produce a route to a place the customer never chose,
and `0, 0` is a real place in the Gulf of Guinea — a route to it is a route into
the Atlantic. `SavedAddress.hasCoordinates` exists so a caller must decide what
to do when they are absent rather than substituting a number.

Module 04 accepted these four fields on the wire and the app never sent any, so
in practice no saved address ever had a position — and Module 05 could not use
one as an end of a journey. That gap is now closed.

The address form has a **Find this address** row. It opens the same
server-mediated place search the trip planner uses, in a search-only mode: the
device's current location is not offered, because an address somebody is
describing from memory should not be pinned to wherever they happen to be
standing, and the saved addresses are not offered because that would be circular.
Choosing a result fills all four fields from the provider's answer, alongside the
lines the customer typed.

Leaving an address unlocated is a perfectly good outcome. It still works as an
address; it simply cannot be one end of a journey yet, and both the form and the
trip planner's picker say so rather than working around it.

See [20-trip-planner.md](20-trip-planner.md) for how the place provider is
configured and why its key never reaches a device.

---

## On the device

**State is scoped to the session, structurally.** `AddressesController.build()`
*watches* the auth state, so ending a session rebuilds the provider from nothing
and starting a new one fetches fresh. There is no cache-clearing step to
remember, because there is no state that survives the session — which is what
makes the Rahul → sign out → Ananya test pass without a single stale frame.

**Nothing is optimistic.** The server owns the one-default rule and the address
limit, so a list updated before the server answers can show a default it rejected
or an address it never saved. Every write re-reads the server's result, and no
screen says "saved" until the server has said so.

**Reads may be stale; writes require connectivity.** A previously loaded list
stays on screen when the network drops. A create, edit or delete that cannot
reach the server fails with "you need a connection to save this. Nothing has been
changed" — an honest statement rather than a queued write that might silently
never land. A queued-sync architecture is a real feature with real conflict rules,
and building half of it would be worse than not building it.

**Forms use a non-lazy scrolling Column, not a ListView.** A `ListView` builds
lazily, so a field scrolled out of view is not in the tree — and a `FormField`
that is not in the tree is never registered with the `Form`, so `validate()`
silently skips it. On a phone that meant tapping Save with a city nothing had
checked.

**The primary action is pinned to the bottom.** A seven-field address form is
taller than a phone, so a Save button at the end of the scroll is invisible on
arrival and is the first thing the keyboard covers.

---

## Accessibility

- The verified number is a labelled panel, not a disabled `TextField`. A
  greyed-out input invites tapping and then does nothing, which reads as a bug.
- **"Verified" and "Default" are words**, not a green tick and a coloured dot.
  Neither state is communicable by colour or shape alone.
- Each row's overflow button is labelled *"Options for Home"*, not "Edit" — the
  menu also deletes, and three identically-labelled buttons are indistinguishable
  to a screen reader.
- Each address row reads as one thing, in the order somebody needs it: label,
  whether it is the default, then where it is.
- Below 320dp of usable width the type selector drops its icons rather than
  wrapping its labels, because the label is the part that carries the meaning.
- Destructive actions are behind a confirmation, never behind a swipe.

---

## Known limitation

Deleting a customer account is blocked while they have saved addresses, by the
`RESTRICT` foreign key. That is deliberate (see above) and the erasure path in a
later module must delete addresses explicitly. Recorded as KI-009.
