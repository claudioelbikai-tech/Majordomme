#!/bin/bash
# Fabrique Majordome.app puis Majordome.dmg (à lancer sur un Mac : GitHub le fait pour toi).
#   ./outils/construire.sh            → build/Majordome.app et build/Majordome.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="${GITHUB_RUN_NUMBER:-1}"
APP="build/Majordome.app"

rm -rf build
mkdir -p build

echo "== Compilation (Apple Silicon + Intel)"
swift build -c release --arch arm64 --arch x86_64
BINAIRE="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Majordome"

echo "== Paquet de l'app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINAIRE" "$APP/Contents/MacOS/Majordome"
sed -e "s/@VERSION@/$VERSION/" -e "s/@BUILD@/$BUILD/" Ressources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"

ICONES="build/AppIcon.iconset"
mkdir -p "$ICONES"
for taille in 16 32 128 256 512; do
  sips -z "$taille" "$taille" Ressources/AppIcon.png --out "$ICONES/icon_${taille}x${taille}.png" >/dev/null
  double=$((taille * 2))
  sips -z "$double" "$double" Ressources/AppIcon.png --out "$ICONES/icon_${taille}x${taille}@2x.png" >/dev/null
done
iconutil -c icns "$ICONES" -o "$APP/Contents/Resources/AppIcon.icns"

# Signature locale (« ad hoc ») : indispensable pour qu'une app tourne sur Apple Silicon.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
lipo -info "$APP/Contents/MacOS/Majordome"

echo "== Image disque"
tiffutil -cathidpicheck Ressources/dmg-fond.png Ressources/dmg-fond@2x.png -out build/dmg-fond.tiff
python3 -m venv build/venv
build/venv/bin/pip install --quiet "dmgbuild>=1.6,<2"
build/venv/bin/dmgbuild -s outils/dmg.py -D app="$APP" -D fond=build/dmg-fond.tiff "Majordome" build/Majordome.dmg
hdiutil verify build/Majordome.dmg
ls -lh build/Majordome.dmg
