# App icon and logo: Detents

## Intent

Haptic Pod has no icon: the home screen shows the blank default. It needs one, plus a logo for the
README and GitHub.

The look is clean, minimal and black and white. It must not resemble Apple's logo or the iPod.
Rule out:

- an apple shape
- a white or silver body
- a screen above a wheel
- MENU or ⏮⏭ labels
- a wheel with a centre button

## Approaches considered

1. **Detents** (chosen): a ring of 24 short ticks with one long tick at 12 o'clock. It shows the
   app's own feature, 24 felt clicks per turn. The cost is that the ticks blur at tiny sizes. The
   20–29 pt sizes get a 12-tick version to fix this (see below).
2. **Notched ring:** a thick ring with a gap and a marker. Crisper at small sizes, but it says
   "knob" rather than "this app's 24 clicks".
3. **Ring and dot:** friendly, but the most generic of the three.

An earlier round of colour ideas (amber-lit dial, ripple, moon) was dropped for black and white.

## The mark

The design canvas is 1024 × 1024 with the centre at (512, 512). All sizes scale from it.

- **Short ticks:** 23 of them, every 15°, spaced as if there were 24, with the tick at 12 o'clock
  replaced by the long one.
  - Each runs radially from r = 205 to r = 248.
  - Stroke 21, round caps.
- **Long tick:** at 12 o'clock, from r = 150 to r = 325, stroke 34, round caps.
- **Colours:** pure black #000000 and white #FFFFFF. No grey, gradient or shadow.
- **Small sizes (≤ 87 px):** 12 short ticks every 30°, strokes ×1.4, so they read as ticks and not
  a grey ring. *(builder call)*

## Deliverables

- **`HapticPod/Assets.xcassets/AppIcon.appiconset`**, with three versions:
  - **Any (light):** white ticks on black. Black is the brand.
  - **Dark:** white ticks on a transparent background, which iOS puts on its own dark background.
  - **Tinted:** white ticks on transparent, which iOS recolours.
- **Sizes:** the 1024 master, plus explicit small-size PNGs so the 12-tick version is used where
  it applies. If Xcode's single-size mode can't do this, ship the 1024 only and accept the blur.
  *(builder call)*
- **iOS 26:** the asset catalogue icon gets the system's glass treatment automatically. No
  Icon Composer `.icon` file for now. *(builder call: it can be added later from the same
  geometry.)*
- **`docs/logo.svg` and `docs/logo-dark.svg`:**
  - Black ticks on transparent for light pages, white for dark ones.
  - Shown at the top of the README via `<picture>` with `prefers-color-scheme`.
- **`scripts/make_icon.swift`:**
  - Draws every PNG and both SVGs from the numbers above using CoreGraphics. No third-party
    tools; none are installed.
  - Rerun it to change the mark.
- **`project.yml`:** adds the asset catalogue and `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`.

## Done when

- The icon shows on the iPhone home screen in light, dark and tinted modes, and in Settings and
  Spotlight.
- The README shows the logo in both GitHub themes.
