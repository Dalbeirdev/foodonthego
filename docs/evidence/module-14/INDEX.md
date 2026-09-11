# Module 14 — screenshot index

Sixteen images. All rendered from the real applications against a real Laravel
server on a real MySQL database. None is a mock-up.

## Customer app — Flutter, 393 × 852, staging build

| File | Screen | What it evidences |
| --- | --- | --- |
| `state-01-checkout.png` | Checkout | restaurant, pickup window, journey, order lines, subtotal and total |
| `state-02-no-charges-and-payment-notice.png` | Checkout (foot) | "No additional charges are currently configured", both edit controls readable, the CTA, the payment notice, the hold time |
| `state-03-configured-charges.png` | Checkout | the same order with 5% tax and a ₹15 packaging fee configured — ₹32.90, ₹15, total ₹705.90, and the "no charges" sentence gone |
| `state-04-expired-quote.png` | Checkout | a quote past its ten-minute hold, offering a refresh |
| `state-05-blocked.png` | Checkout | a sold-out line refused in the server's words, with no payment notice under a disabled button |
| `state-06-dark.png` | Checkout | the same screen on a phone set to dark |
| `state-07-cart.png` | Cart | lines with their configuration, quantity steppers, subtotal |
| `state-08-cart-foot.png` | Cart (foot) | the way on to a pickup time |
| `state-09-pickup-times.png` | Pickup time | the windows the kitchen can meet |
| `state-10-pickup-explanation.png` | Pickup time | how each window was worked out, and the zone the times are in |

States 02 and 03 are each other's control: the same screen and the same code
path, with only the restaurant's commercial configuration changed between them.

## Web shells — React

| File | Application | Viewport |
| --- | --- | --- |
| `restaurant-1440.png` | Restaurant dashboard | 1440 × 900 |
| `restaurant-390.png` | Restaurant dashboard | 390 × 844 |
| `restaurant-dark.png` | Restaurant dashboard | 1440 × 900, dark |
| `admin-1440.png` | Admin panel | 1440 × 900 |
| `admin-390.png` | Admin panel | 390 × 844 |
| `admin-dark.png` | Admin panel | 1440 × 900, dark |

## Screenshot QA

- **No secrets.** No API key, password, token, payment card, production hostname
  or real person's data appears in any image.
- **No real PII.** The customer is a development persona; the restaurant is
  named `[TEST] Highway Spice Kitchen` so a fixture can never be mistaken for a
  business.
- **The flask button** in the bottom-left corner of the Flutter images is the
  development harness. It exists in non-production builds and is compiled out of
  a production one. It is in the pictures because it is in the binary a reviewer
  would install.
- **The font is a stand-in.** Flutter web fetches its default font from a CDN
  this build environment blocks; without a substitute the app renders with no
  glyphs at all. DejaVu Sans was bundled temporarily and reverted immediately —
  Liberation Sans was tried first and rejected because it has no `U+20B9`, so
  every price rendered as an empty box. Layout, colour, spacing, icons,
  navigation and every figure shown are the product's own.
