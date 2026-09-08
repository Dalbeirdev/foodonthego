# 33 — Multi-tenancy and tenant isolation

**Module 14T.** Inserted between Modules 14 and 15 at the client's direction,
because payments attach to orders, orders attach to restaurants, and money moves
per tenant. Retrofitting a tenant dimension into payment and reconciliation
tables afterwards is the expensive version of this.

The constraint itself is stated in [07-security.md](07-security.md). This
document is how it is built.

---

## The shape of the problem

A restaurant is a tenant. Owners, managers and staff reach only the restaurants
they are explicitly assigned to. A super administrator may reach more than one,
and which ones is a decision somebody made, not a consequence of their role
string.

Before this module a restaurant was not owned by anybody in any structural
sense: `owner_name`, `owner_phone` and `owner_email` are contact strings for the
platform to ring. There was no assignment table, no `app/Policies` directory, and
not one `Gate::` or `->authorize()` call in the codebase.

---

## Four decisions

### The tenant role lives on the assignment, not on the user

`users.role` cannot describe somebody who owns one restaurant and cooks at
another, and any model that tries will eventually grant the wrong one. So
`restaurant_user.tenant_role` says what a person may do *at that restaurant*, and
`users.role` keeps its existing job: which surface they sign in to.

**Both are checked.** A customer account with an assignment row reaches nothing,
because the surface gate fails first — which means a mistaken or malicious insert
into `restaurant_user` is not by itself a way in. There is a test for exactly
that.

### There is no `restaurants.owner_id`

An owner is an assignment whose role is `owner`. One place to look, one place to
revoke. Two sources of truth for "who owns this" is how a removed owner keeps
their access.

### Revoked, never deleted

Assignments and grants are withdrawn by `status`. A dismissed manager is a
revoked row, not a missing one, and the difference matters the first time
somebody asks who had access in March. Every read filters on it, and the filter
lives in an `active()` scope so it cannot be remembered in one query and
forgotten in the next.

### A super administrator with no grant reaches nothing

Breadth comes from a `platform_tenant_grants` row: either `scope = 'all'` or one
named restaurant, with a `tenant_role` for the depth. With no row, nothing.

That default is the whole point. "Super admin can see everything" is the sentence
that turns one compromised platform account into every restaurant's data, and it
is usually true by omission rather than by decision. Here the omission denies —
and there is deliberately no policy `before()` hook, because that hook is how the
omission usually gets in.

---

## The layers, and what each does

| Layer | Question it answers |
| --- | --- |
| `auth:sanctum` | is there a session at all |
| `role:` middleware | is this the kind of account that belongs on this surface |
| `TenantAccessService` | which restaurants, and how deeply |
| `RestaurantPolicy` | is this *action* within that depth |

**The role gate is a surface check and never a tenancy check.** On its own it
would let any `restaurant_manager` reach every restaurant on the platform, which
is precisely the failure this module exists to prevent.

`TenantAccessService` is the only implementation of reachability. The policy, the
query scopes and every controller ask it. Two implementations of a tenancy rule
is one implementation and one hole, and the hole is always in the copy somebody
wrote in a hurry for a new endpoint.

---

## Scoping happens in the query

`Restaurant::query()->reachableBy($user)` is a `whereIn` against a subquery. A
lookup that finds a row and *then* compares a tenant id has already decided the
row exists, and the difference between "not yours" and "not real" is what an
attacker is enumerating for. Applied to a single-record lookup it makes both
cases the same empty result and the same 404, with the same message — asserted by
a test that compares the two responses field by field.

### The indirect path

This is where real holes live, and it is why `BelongsToTenant` exists.

Scoping `/restaurants/{restaurant}/menu/items` is easy: the tenant is in the URL.
The dangerous shape is **`/menu/items/{item}`** — a resource reached by its own
identifier, where nothing in the request names a restaurant. The obvious
implementation:

```php
MenuItem::query()->where('uuid', $uuid)->first();   // hands one tenant's prices to another
```

is correct-looking and passes every test somebody writes about menu items. The
scope reaches back through the owning restaurant and filters there, so there is
no moment at which an unscoped row exists to be checked or forgotten.

Both shapes are routed and both are tested. If only the nested one were, a pass
would say nothing about the dangerous one.

---

## The surface

Deliberately minimal, and **not the operator dashboard**:

| Route | Why it exists |
| --- | --- |
| `GET /restaurant/restaurants` | list isolation |
| `GET /restaurant/restaurants/{id}` | single-record isolation, and the identical-404 property |
| `PATCH /restaurant/restaurants/{id}` | **write** isolation — reads and writes fail differently often enough that testing one proves little about the other |
| `GET /restaurant/restaurants/{id}/menu/items` | child collection, the easy shape |
| `GET /restaurant/menu/items/{item}` | **the indirect path** |
| `GET /admin/restaurants` | grant scoping, and the no-grant-reaches-nothing assertion |

A service method cannot be IDOR-tested; only a route can. This is the thinnest
surface that makes the requirement's "every cross-tenant read/write/API/IDOR
attempt must be security-tested" actually satisfiable.

**No login mints a token for these roles yet.** That is deliberate and unchanged
by this module: the isolation is what is being built, and authenticating an
operator is a later module. The boundary exists first so that login arrives
behind something already tested rather than alongside something new.

---

## What is tested

22 tests in `tests/Feature/Api/Tenancy/TenantIsolationTest.php`, all over HTTP
with real tokens: list, read, write, the indirect path, revoked assignments,
suspended and deactivated accounts, the surface gate, an assignment that must not
promote a customer, super-admin with and without grants, platform-wide grants,
revoked grants, a support agent scoped to one tenant, and role depth.

Seven negative controls, each applied to shipping code and reverted:

| Control | Tests it broke |
| --- | --- |
| single-tenant lookup loses its scope | 6 |
| indirect path loses its scope | 1 |
| platform role implies platform-wide access | 4 |
| revoked assignments count as access | 1 |
| surface check dropped | 3 |
| suspended/disabled treated as usable | 2 |
| write action drops to staff depth | 1 |

**Every one fired.**

### One bug the controls found first

`accountUsable()` originally read `$user->is_active === true`. The column
defaults to true in the database, so a model that has not round-tripped since
creation holds `NULL` — and `=== true` read that absence as a disabled account.

Denying by accident looks like security and is not. It made every "this account
reaches nothing" assertion pass whether the boundary worked or not, which is the
one bug a tenancy suite must never have. Only an explicit `false` denies now, and
both switches have their own test.

---

## Not built

- **No login for any of the six operator roles.** Unchanged, and the reason the
  routes above have no way to be reached in production yet.
- **No staff management endpoints.** Assignments and grants are rows; the screens
  that create them belong to the operator module. `manageStaff` exists on the
  policy so the depth is decided, not so anything calls it yet.
- **Tenant scoping for resources that do not exist yet** — orders, payments,
  settlements. `BelongsToTenant` is the seam they attach to.
- **An audit log** of who granted what. `granted_by_user_id`, `granted_at` and
  `revoked_at` are the minimum needed to answer the question without one; the log
  itself is Module 18.
