# SilaFit store screenshots

Renders the App Store and Google Play screenshots (EN + MK) from raw app
captures, using the app's own fonts (Hanken Grotesk / Permanent Marker, with
Golos Text / Shantell Sans for Cyrillic) and palette.

## 1. Capture the app

The app blocks screenshots on every screen. Run it with captures allowed:

```sh
cd frontend
flutter run --dart-define-from-file=env/prod.json --dart-define=ALLOW_SCREENSHOTS=true
```

Never ship a build with `ALLOW_SCREENSHOTS`. Trainer documents stay locked either way.

Capture on an iPhone 6.9" simulator (iPhone 16/17 Pro Max: 1320×2868) in
**dark mode**, then switch the app language and capture again:

```sh
xcrun simctl io booted screenshot today.png
```

| File               | Screen                                              |
|--------------------|-----------------------------------------------------|
| `today.png`        | Today tab with a workout scheduled                  |
| `set-logging.png`  | Active workout tracker, mid-set                     |
| `progress.png`     | Progress tab, exercise 1RM chart                    |
| `nutrition.png`    | Nutrition tab with a logged meal + active diet plan |
| `splits.png`       | My Splits                                           |
| `get-started.png`  | Weekly AI review ("Your next chapter")              |

Put them in `public/screenshots/iphone/en/` and `public/screenshots/iphone/mk/`.
Android uses the iPhone captures unless you also drop Android-emulator
captures into `public/screenshots/android/{en,mk}/`.

## 2. Render and export

```sh
cd tools/store-screenshots
npm install
npm run dev   # http://localhost:3000
```

Pick EN/MK and iPhone / Android / Feature graphic. **Export EN+MK, all sizes**
downloads every locale × size for the selected device as JPEGs. Both stores
reject PNGs with alpha, so the export doesn't make PNGs.

Copy lives in `COPY` at the top of `src/app/page.tsx`. `*word*` sets a word as
the lime marker accent.

The six slides share one scene, `public/bg/carousel-base.jpg`, laid out as a
single strip so the store carousel reads as one panorama. It is scaled so each
glowing node on the line lands on a slide boundary (`NODE0` / `NODE_STEP` in
`page.tsx`); where it runs out it continues as a mirror image behind the first
and last phones. Swapping the base image means re-measuring those two numbers.

**iOS header** (5244×2950, 3840×1646) and **iOS search** (5244×2950,
3840×2560, 1920×1280) are single App Store artworks: copy on the left, three
phones on the right, over a softly blurred centre crop of the same panorama.
Their copy and screens are set in `ARTWORK` in `page.tsx`.
