# Module 17 — order tracking screenshots

Seven images of the tracking screen, produced by
`mobile/tool/capture_tracking_screenshots.dart`:

```bash
cd mobile
flutter test tool/capture_tracking_screenshots.dart --update-goldens
```

| File | What it shows |
| --- | --- |
| `tracking-placed.png` | just placed — one step reached, four still ahead and undated |
| `tracking-cooking.png` | mid-order — three reached, the current one in bold |
| `tracking-ready.png` | ready — four reached, pickup still ahead |
| `tracking-picked-up.png` | terminal — every step reached, and the pickup credential gone |
| `tracking-rejected.png` | refused — the happy path **truncated**, with the customer-safe reason and no Cooking or Ready pretending to still be coming |
| `tracking-cooking-320.png` | the same order at 320 dp, the narrowest width this app supports |
| `tracking-cooking-large-text.png` | the same order at 2× text scale |

## What these are

The real widget tree, the real theme, the real router and the real screen code,
driven by the same fake repository the widget tests use. The fonts are Roboto
and MaterialIcons loaded straight out of the Flutter SDK — the same files a real
build ships — so the type and the icons are the product's own, not stand-ins.
`flutter test` draws every glyph as an empty box without that, and the script
skips rather than writing boxes if the SDK fonts are not found.

## What these are not

**Not a device.** No platform channels, no native safe areas, no keyboard, no
lifecycle. For the tracking screen against a real server on real hardware the
evidence is the on-device suite — `integration_test/module_14_checkout_test.dart`
opens this screen cold on both an Android emulator and an iOS simulator, and
that is what found the Module 17 tracking defect. These images show what it
looks like; the device run shows that it works.

**Not a live server.** The data is a fixture, chosen to put each timeline state
on screen. For the same screen filled by a real Laravel backend, read
`../live-api-run.txt`.

## One blemish, stated rather than cropped

The app bar title renders as two black boxes. Every other string on the screen
resolves against the loaded Roboto; that one — 20 dp, weight 600, inside
`AppBar`'s own `AnimatedDefaultTextStyle` — does not, and the cause was not
found. It is a harness artefact and nothing else: the same title renders
normally on both device runs, and a widget test asserts the screen's title text.
It is left in view rather than cropped out, because a screenshot with something
quietly removed is worth less than one with something visibly unexplained.
