#!/usr/bin/env bash
#
# Builds Cadence.app.
#
# Requires only the Xcode Command Line Tools (free): no Xcode project, no
# CocoaPods, no Swift package dependencies to resolve, no network access.
#
#   ./build.sh              release build into ./build/Cadence.app
#   ./build.sh --debug      debug build
#   ./build.sh --install    also copy the result into /Applications
#   ./build.sh --run        launch it when the build finishes

set -euo pipefail

CONFIGURATION="release"
INSTALL=0
RUN=0

for argument in "$@"; do
    case "$argument" in
        --debug)   CONFIGURATION="debug" ;;
        --release) CONFIGURATION="release" ;;
        --install) INSTALL=1 ;;
        --run)     RUN=1 ;;
        -h|--help)
            sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Option inconnue : $argument" >&2
            exit 2
            ;;
    esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Cadence.app ne peut être assemblée que sur macOS." >&2
    echo "Sur une autre plateforme, « swift test » exécute tout de même la logique métier." >&2
    exit 1
fi

APP_NAME="Cadence"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"

echo "▸ Compilation ($CONFIGURATION)…"
swift build -c "$CONFIGURATION" --product "$APP_NAME"
BINARY="$(swift build -c "$CONFIGURATION" --product "$APP_NAME" --show-bin-path)/$APP_NAME"

if [[ ! -x "$BINARY" ]]; then
    echo "Le binaire n'a pas été produit : $BINARY" >&2
    exit 1
fi

echo "▸ Icône…"
if [[ ! -f "$ROOT/Resources/$APP_NAME.icns" ]]; then
    python3 "$ROOT/Tools/make_icon.py" "$ROOT/Resources"
fi

echo "▸ Assemblage du bundle…"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BINARY" "$CONTENTS/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/$APP_NAME.icns" "$CONTENTS/Resources/$APP_NAME.icns"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# An ad-hoc signature is what lets macOS remember the calendar permission across
# rebuilds. Without it, TCC treats every build as a different application and asks
# again — or silently refuses.
echo "▸ Signature ad hoc…"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || {
    echo "  (signature impossible — l'application fonctionnera, mais macOS redemandera"
    echo "   l'accès aux calendriers à chaque reconstruction)"
}

# Clears the quarantine flag the build itself never sets, but which a copy through
# a browser or an archive would.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "▸ Terminé : $APP"

if [[ $INSTALL -eq 1 ]]; then
    echo "▸ Installation dans /Applications…"
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"
    APP="/Applications/$APP_NAME.app"
fi

if [[ $RUN -eq 1 ]]; then
    open "$APP"
fi
