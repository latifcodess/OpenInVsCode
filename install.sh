#!/bin/zsh
# Génère le projet, compile en Release, installe dans /Applications et active l'extension Finder.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Open in VS Code.app"
EXT_ID="ch.latifcodess.OpenInVSCode.FinderExtension"
BUILT="build/Build/Products/Release/$APP_NAME"
DEST="/Applications/$APP_NAME"

xcodegen generate
xcodebuild -project OpenInVSCode.xcodeproj -scheme OpenInVSCode -configuration Release \
  -derivedDataPath build -allowProvisioningUpdates build | grep -E "error|BUILD" || true
[[ -d "$BUILT" ]] || { echo "Échec de la compilation"; exit 1; }

# Évite que macOS charge la copie du dossier build au lieu de celle de /Applications
pluginkit -r "$BUILT/Contents/PlugIns/FinderExtension.appex" 2>/dev/null || true

rm -rf "$DEST"
ditto "$BUILT" "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
pluginkit -a "$DEST/Contents/PlugIns/FinderExtension.appex"
pluginkit -e use -i "$EXT_ID"
killall Finder || true

echo "Installé : $DEST"
pluginkit -m -i "$EXT_ID" -v
