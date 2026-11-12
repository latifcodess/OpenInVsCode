#!/bin/zsh
# Publie une nouvelle version : ./release.sh 1.2 ["Notes de version"]
# Met à jour la version, compile, zippe l'app, commit + tag + push, puis crée la release GitHub.
# Les apps installées la détecteront à leur prochaine ouverture (ou au démarrage de la session).
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?Usage: ./release.sh <version> [notes]}"
NOTES="${2:-}"
APP_NAME="Open in VS Code.app"
BUILT="build/Build/Products/Release/$APP_NAME"
ZIP="dist/OpenInVSCode-$VERSION.zip"

[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "Version invalide : $VERSION"; exit 1; }
git diff --quiet && git diff --cached --quiet || { echo "Il y a des modifications non commitées."; exit 1; }
git rev-parse "v$VERSION" >/dev/null 2>&1 && { echo "Le tag v$VERSION existe déjà."; exit 1; }

# Version marketing + numéro de build incrémenté
BUILD_NUMBER=$(( $(sed -nE 's/^ *CURRENT_PROJECT_VERSION: "([0-9]+)"/\1/p' project.yml) + 1 ))
sed -i '' -E "s/^( *MARKETING_VERSION: )\"[^\"]*\"/\1\"$VERSION\"/" project.yml
sed -i '' -E "s/^( *CURRENT_PROJECT_VERSION: )\"[^\"]*\"/\1\"$BUILD_NUMBER\"/" project.yml

xcodegen generate
rm -rf "$BUILT"
xcodebuild -project OpenInVSCode.xcodeproj -scheme OpenInVSCode -configuration Release \
  -derivedDataPath build -allowProvisioningUpdates build | grep -E "error|BUILD" || true
[[ -d "$BUILT" ]] || { echo "Échec de la compilation"; exit 1; }
codesign --verify --deep --strict "$BUILT"

mkdir -p dist
rm -f "$ZIP"
ditto -c -k --keepParent "$BUILT" "$ZIP"

git add -A
git commit -m "Version $VERSION"
git tag "v$VERSION"
git push origin HEAD "v$VERSION"

if [[ -n "$NOTES" ]]; then
  gh release create "v$VERSION" "$ZIP" --title "Open in VS Code $VERSION" --notes "$NOTES"
else
  gh release create "v$VERSION" "$ZIP" --title "Open in VS Code $VERSION" --generate-notes
fi
echo "Release v$VERSION publiée."
