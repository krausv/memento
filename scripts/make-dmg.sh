#!/bin/bash
# Sestaví distribuovatelné, podepsané Memento.dmg.
#
# Použití:
#   scripts/make-dmg.sh [--sign "Developer ID Application: JMÉNO (TEAMID)"]
#
# Proměnné prostředí:
#   VERSION         marketingová verze (např. 0.2.0); prázdná = z project.yml
#   BUILD_NUMBER    číslo buildu (CFBundleVersion); prázdné = z project.yml
#   SIGN_IDENTITY   podpisová identita (jinak se najde jediná "Developer ID Application", jinak ad-hoc "-")
#   NOTARY_APPLE_ID / NOTARY_TEAM_ID / NOTARY_PASSWORD   pokud jsou všechny nastavené, DMG se notarizuje
#
# Ad-hoc podpis stačí jen pro tento Mac; ostatní Macy ho kvůli Gatekeeperu neotevřou bez pravého kliku.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Memento"
BUILD_DIR="$ROOT/build/release"
APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
DMG="$ROOT/$APP_NAME.dmg"
IDENTITY="${SIGN_IDENTITY:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign) IDENTITY="$2"; shift 2 ;;
        *) echo "neznámý argument: $1" >&2; exit 1 ;;
    esac
done

# --- podpisová identita -------------------------------------------------------
if [[ -z "$IDENTITY" ]]; then
    found="$(security find-identity -v -p codesigning 2>/dev/null \
             | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/' || true)"
    if [[ -n "$found" ]]; then
        IDENTITY="$found"
        echo "› nalezena identita: $IDENTITY"
    else
        IDENTITY="-"
        echo "⚠ Developer ID nenalezeno – podepisuji ad-hoc; DMG poběží jen na tomto Macu."
    fi
fi

# --- build --------------------------------------------------------------------
echo "› generuji projekt a stavím Release"
xcodegen generate -q
rm -rf "$BUILD_DIR"
ARGS=(-scheme "$APP_NAME" -configuration Release -derivedDataPath "$BUILD_DIR" CODE_SIGN_IDENTITY="-")
[[ -n "${VERSION:-}" ]] && ARGS+=(MARKETING_VERSION="$VERSION")
[[ -n "${BUILD_NUMBER:-}" ]] && ARGS+=(CURRENT_PROJECT_VERSION="$BUILD_NUMBER")
xcodebuild "${ARGS[@]}" build | tail -n 3
[[ -d "$APP" ]] || { echo "Build nevytvořil $APP" >&2; exit 1; }

# --- podpis s hardened runtime ------------------------------------------------
echo "› podepisuji aplikaci ($IDENTITY)"
CS_OPTS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then
    CS_OPTS+=(--options runtime --timestamp)
fi
codesign "${CS_OPTS[@]}" "$APP"
codesign --verify --deep --strict --verbose=1 "$APP"

# --- DMG ----------------------------------------------------------------------
echo "› vytvářím $APP_NAME.dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [[ "$IDENTITY" != "-" ]]; then
    echo "› podepisuji DMG"
    codesign --force --sign "$IDENTITY" "$DMG"
fi

# --- notarizace (volitelná) ---------------------------------------------------
if [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_TEAM_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]]; then
    echo "› notarizuji (může trvat několik minut)"
    xcrun notarytool submit "$DMG" \
        --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
fi

echo "✓ hotovo: $DMG"
if [[ "$IDENTITY" == "-" ]]; then
    echo "  (ad-hoc – pro sdílení podepiš Developer ID a notarizuj)"
fi
true
