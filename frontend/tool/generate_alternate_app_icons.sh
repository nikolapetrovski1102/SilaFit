#!/bin/sh
# Builds the app icon files flutter_launcher_icons can't:
#   - iOS AppIcon (dark, the default) and AppIconLight (the alternate the user
#     can pick in Settings). flutter_launcher_icons still writes to the old
#     ios/Runner path, so pubspec.yaml has it skip iOS entirely.
#   - Android ic_launcher_light: legacy PNGs for API < 26 plus the adaptive
#     icon XML, which reuses the shared ic_launcher_foreground drawable.
# macOS only (uses sips). Run from anywhere:
#   dart run flutter_launcher_icons && tool/generate_alternate_app_icons.sh
set -eu
cd "$(dirname "$0")/.."

DARK=assets/branding/app_icon_dark.png
LIGHT=assets/branding/app_icon_light.png
CATALOG=ios/SilaFit/Assets.xcassets

# "<point size> <scale>" pairs - the iPhone/iPad/marketing sizes Xcode's
# single-size catalog still accepts alongside the 1024pt master.
IOS_SIZES="20 2
20 3
29 2
29 3
38 2
38 3
40 2
40 3
60 2
60 3
64 2
64 3
68 2
76 2
83.5 2
1024 1"

ios_set() {
  src=$1
  dir=$CATALOG/$2.appiconset
  rm -f "$dir"/Icon-App-*.png
  mkdir -p "$dir"
  images=""
  echo "$IOS_SIZES" | while read -r pt scale; do
    px=$(echo "$pt * $scale" | bc | cut -d. -f1)
    file="Icon-App-${pt}x${pt}@${scale}x.png"
    sips -s format png -z "$px" "$px" "$src" --out "$dir/$file" >/dev/null
  done
  for pair in $(echo "$IOS_SIZES" | tr ' ' ':'); do
    pt=${pair%:*}
    scale=${pair#*:}
    images="$images{\"size\":\"${pt}x${pt}\",\"idiom\":\"universal\",\"filename\":\"Icon-App-${pt}x${pt}@${scale}x.png\",\"scale\":\"${scale}x\",\"platform\":\"ios\"},"
  done
  images="$images{\"size\":\"1024x1024\",\"idiom\":\"ios-marketing\",\"filename\":\"Icon-App-1024x1024@1x.png\",\"scale\":\"1x\"}"
  printf '{"images":[%s],"info":{"version":1,"author":"xcode"}}\n' "$images" \
    > "$dir/Contents.json"
}

ios_set "$DARK" AppIcon
ios_set "$LIGHT" AppIconLight

RES=android/app/src/main/res
for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density=${pair%:*}
  px=${pair#*:}
  sips -s format png -z "$px" "$px" "$LIGHT" \
    --out "$RES/mipmap-$density/ic_launcher_light.png" >/dev/null
done

cat > "$RES/mipmap-anydpi-v26/ic_launcher_light.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/ic_launcher_light_background"/>
  <foreground>
      <inset
          android:drawable="@drawable/ic_launcher_foreground"
          android:inset="16%" />
  </foreground>
</adaptive-icon>
XML

echo "Generated iOS AppIcon + AppIconLight and Android ic_launcher_light."
