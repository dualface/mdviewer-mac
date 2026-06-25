#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MarkdownViewer"
SCHEME="MDViewerMac"
PROJECT_FILE="MDViewerMac.xcodeproj"
CONFIGURATION="Release"
DESTINATION="platform=macOS"
DEFAULT_VERSION="0.5"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
BUILD_DIR="$ROOT_DIR/.build/release"
DERIVED_DATA_DIR="$BUILD_DIR/DerivedData"
INFO_PLIST="$ROOT_DIR/App/Generated/Info.plist"
ENTITLEMENTS_PLIST="$ROOT_DIR/App/Generated/MDViewerMac.entitlements"

VERSION="${MDVIEWER_VERSION:-$DEFAULT_VERSION}"
TAG=""
REPO=""
REMOTE="origin"
NOTES_FILE=""
DRAFT=0
PRERELEASE=0
SKIP_TESTS=0
SKIP_UPLOAD=0
ALLOW_DIRTY=0
SIGN_APP=1
NOTARIZE_APP=0
SIGNING_IDENTITY="${MDVIEWER_SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${MDVIEWER_NOTARY_PROFILE:-}"

usage() {
    cat <<'EOF'
Usage: scripts/release.sh [options]

Builds the renderer, builds and signs the macOS app in Release mode, packages
the .app as a DMG file, and publishes it to a GitHub Release with the GitHub CLI.

Options:
  --version VERSION    Marketing version. Default: 0.5.
  --tag TAG            Release tag. Defaults to v<version>-<build-number>.
  --repo OWNER/REPO    GitHub repository for gh release commands.
  --remote NAME        Git remote used when pushing a new tag. Default: origin.
  --notes-file PATH    Release notes file. Defaults to GitHub generated notes.
  --draft             Create the GitHub release as a draft.
  --prerelease        Mark the GitHub release as a prerelease.
  --skip-tests        Skip the XCTest step.
  --skip-upload       Build and package locally without creating a GitHub release.
  --allow-dirty       Allow releasing with uncommitted working tree changes.
  --sign              Sign the app with an available local certificate.
  --no-sign           Build without re-signing after xcodebuild.
  --notarize          Notarize and staple the signed app before packaging.
  --signing-identity  Signing identity. If omitted, the script auto-selects
                      Developer ID Application, Apple Distribution, then
                      Apple Development.
                      Can also be set with MDVIEWER_SIGNING_IDENTITY.
  --notary-profile    notarytool keychain profile.
                      Can also be set with MDVIEWER_NOTARY_PROFILE.
  -h, --help          Show this help message.

Examples:
  scripts/release.sh --draft
  scripts/release.sh --tag v0.5-20260626013209 --repo dualface/mdviewer-mac
  scripts/release.sh --skip-upload --allow-dirty
  MDVIEWER_SIGNING_IDENTITY="Developer ID Application: Example, Inc. (TEAMID)" \
    MDVIEWER_NOTARY_PROFILE="mdviewer-notary" \
    scripts/release.sh --sign --notarize
EOF
}

log() {
    printf '\n==> %s\n' "$*"
}

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

require_value() {
    local option="$1"
    local value="${2:-}"
    [[ -n "$value" && "${value:0:1}" != "-" ]] || fail "$option requires a value"
}

detect_signing_identity() {
    local identities
    local identity

    identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

    for pattern in "Developer ID Application" "Apple Distribution" "Apple Development"; do
        identity="$(awk -F'"' -v pattern="$pattern" '$0 ~ pattern { print $2; exit }' <<<"$identities")"
        if [[ -n "$identity" ]]; then
            printf '%s\n' "$identity"
            return
        fi
    done
}

ensure_clean_working_tree() {
    local context="$1"

    if [[ "$ALLOW_DIRTY" -eq 0 && -n "$(git status --porcelain)" ]]; then
        fail "Working tree has uncommitted changes $context. Commit them or pass --allow-dirty."
    fi
}

create_dmg() {
    local app_path="$1"
    local asset_path="$2"
    local staging_dir="$BUILD_DIR/dmg-staging"

    rm -rf "$staging_dir"
    mkdir -p "$staging_dir"

    ditto "$app_path" "$staging_dir/$APP_NAME.app"
    ln -s /Applications "$staging_dir/Applications"

    rm -f "$asset_path"
    hdiutil create \
        -volname "MarkdownViewer $VERSION" \
        -srcfolder "$staging_dir" \
        -ov \
        -format UDZO \
        "$asset_path"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            require_value "$1" "${2:-}"
            VERSION="$2"
            shift 2
            ;;
        --version=*)
            VERSION="${1#*=}"
            shift
            ;;
        --tag)
            require_value "$1" "${2:-}"
            TAG="$2"
            shift 2
            ;;
        --tag=*)
            TAG="${1#*=}"
            shift
            ;;
        --repo)
            require_value "$1" "${2:-}"
            REPO="$2"
            shift 2
            ;;
        --repo=*)
            REPO="${1#*=}"
            shift
            ;;
        --remote)
            require_value "$1" "${2:-}"
            REMOTE="$2"
            shift 2
            ;;
        --remote=*)
            REMOTE="${1#*=}"
            shift
            ;;
        --notes-file)
            require_value "$1" "${2:-}"
            NOTES_FILE="$2"
            shift 2
            ;;
        --notes-file=*)
            NOTES_FILE="${1#*=}"
            shift
            ;;
        --draft)
            DRAFT=1
            shift
            ;;
        --prerelease)
            PRERELEASE=1
            shift
            ;;
        --skip-tests)
            SKIP_TESTS=1
            shift
            ;;
        --skip-upload)
            SKIP_UPLOAD=1
            shift
            ;;
        --allow-dirty)
            ALLOW_DIRTY=1
            shift
            ;;
        --sign)
            SIGN_APP=1
            shift
            ;;
        --no-sign)
            SIGN_APP=0
            shift
            ;;
        --notarize)
            SIGN_APP=1
            NOTARIZE_APP=1
            shift
            ;;
        --signing-identity)
            require_value "$1" "${2:-}"
            SIGNING_IDENTITY="$2"
            shift 2
            ;;
        --signing-identity=*)
            SIGNING_IDENTITY="${1#*=}"
            shift
            ;;
        --notary-profile)
            require_value "$1" "${2:-}"
            NOTARY_PROFILE="$2"
            shift 2
            ;;
        --notary-profile=*)
            NOTARY_PROFILE="${1#*=}"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "Unknown option: $1"
            ;;
    esac
done

cd "$ROOT_DIR"

require_command git
require_command npm
require_command xcodegen
require_command xcodebuild
require_command ditto
require_command hdiutil

if [[ "$SIGN_APP" -eq 1 ]]; then
    require_command codesign
    require_command security
    if [[ -z "$SIGNING_IDENTITY" ]]; then
        SIGNING_IDENTITY="$(detect_signing_identity)"
    fi
    [[ -n "$SIGNING_IDENTITY" ]] || fail "Missing signing identity. Install a signing certificate, pass --signing-identity, or set MDVIEWER_SIGNING_IDENTITY."
    [[ -f "$ENTITLEMENTS_PLIST" ]] || fail "Missing entitlements file: $ENTITLEMENTS_PLIST"
fi

if [[ "$NOTARIZE_APP" -eq 1 ]]; then
    require_command xcrun
    [[ -n "$NOTARY_PROFILE" ]] || fail "Missing notary profile. Pass --notary-profile or set MDVIEWER_NOTARY_PROFILE."
fi

if [[ "$SKIP_UPLOAD" -eq 0 ]]; then
    require_command gh
fi

ensure_clean_working_tree "before release"

if [[ -n "$NOTES_FILE" && ! -f "$NOTES_FILE" ]]; then
    fail "Release notes file does not exist: $NOTES_FILE"
fi

log "Installing renderer dependencies"
(
    cd "$ROOT_DIR/Renderer"
    npm ci
)

log "Building renderer"
(
    cd "$ROOT_DIR/Renderer"
    npm run build
)

log "Generating Xcode project"
xcodegen generate

ensure_clean_working_tree "after renderer build and project generation"

[[ -f "$INFO_PLIST" ]] || fail "Missing generated Info.plist: $INFO_PLIST"

BUILD_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BUILD_NUMBER="${BUILD_TIMESTAMP/-/}"
[[ -n "$VERSION" ]] || fail "Version cannot be empty."

RELEASE_VERSION="$VERSION-$BUILD_NUMBER"

if [[ -z "$TAG" ]]; then
    TAG="v$RELEASE_VERSION"
fi

ASSET_PATH="$DIST_DIR/$APP_NAME-$RELEASE_VERSION-macOS.dmg"
NOTARY_ASSET_PATH="$DIST_DIR/$APP_NAME-$RELEASE_VERSION-macOS-notary.dmg"
VERSION_BUILD_SETTINGS=(
    "MARKETING_VERSION=$VERSION"
    "CURRENT_PROJECT_VERSION=$BUILD_NUMBER"
)

if [[ "$SKIP_TESTS" -eq 0 ]]; then
    log "Running tests"
    xcodebuild \
        -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -destination "$DESTINATION" \
        "${VERSION_BUILD_SETTINGS[@]}" \
        test
else
    log "Skipping tests"
fi

log "Building Release app"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    "${VERSION_BUILD_SETTINGS[@]}" \
    clean build

PRODUCTS_DIR="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION"
APP_PATH="$PRODUCTS_DIR/$APP_NAME.app"

if [[ ! -d "$APP_PATH" ]]; then
    APP_PATH="$(find "$PRODUCTS_DIR" -maxdepth 1 -name '*.app' -type d -print -quit)"
fi

[[ -n "$APP_PATH" && -d "$APP_PATH" ]] || fail "Could not find built .app in $PRODUCTS_DIR"

if [[ "$SIGN_APP" -eq 1 ]]; then
    log "Signing app with $SIGNING_IDENTITY"
    codesign \
        --force \
        --deep \
        --entitlements "$ENTITLEMENTS_PLIST" \
        --options runtime \
        --timestamp \
        --sign "$SIGNING_IDENTITY" \
        "$APP_PATH"

    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
fi

if [[ "$NOTARIZE_APP" -eq 1 ]]; then
    log "Preparing notarization archive"
    create_dmg "$APP_PATH" "$NOTARY_ASSET_PATH"

    log "Submitting app for notarization"
    xcrun notarytool submit "$NOTARY_ASSET_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    log "Stapling notarization ticket"
    xcrun stapler staple "$NOTARY_ASSET_PATH"
    xcrun stapler validate "$NOTARY_ASSET_PATH"
fi

log "Creating DMG"
if [[ "$NOTARIZE_APP" -eq 1 ]]; then
    mv "$NOTARY_ASSET_PATH" "$ASSET_PATH"
else
    create_dmg "$APP_PATH" "$ASSET_PATH"
fi

ensure_tag_on_head() {
    local head_commit
    local tag_commit

    head_commit="$(git rev-parse HEAD)"

    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
        tag_commit="$(git rev-list -n 1 "$TAG")"
        [[ "$tag_commit" == "$head_commit" ]] || fail "Tag $TAG exists but does not point to HEAD."
    else
        log "Creating local tag $TAG"
        git tag -a "$TAG" -m "Release $TAG"
    fi

    git remote get-url "$REMOTE" >/dev/null 2>&1 || fail "Git remote '$REMOTE' is not configured."

    log "Pushing tag $TAG to $REMOTE"
    git push "$REMOTE" "refs/tags/$TAG"
}

publish_release() {
    local repo_args=()
    local create_args=("$TAG" "$ASSET_PATH" --title "$TAG")

    if [[ -n "$REPO" ]]; then
        repo_args=(--repo "$REPO")
    fi

    if gh release view "$TAG" "${repo_args[@]}" >/dev/null 2>&1; then
        log "Uploading asset to existing GitHub release $TAG"
        gh release upload "$TAG" "$ASSET_PATH" --clobber "${repo_args[@]}"
        return
    fi

    ensure_tag_on_head

    if [[ -n "$NOTES_FILE" ]]; then
        create_args+=(--notes-file "$NOTES_FILE")
    else
        create_args+=(--generate-notes)
    fi

    if [[ "$DRAFT" -eq 1 ]]; then
        create_args+=(--draft)
    fi

    if [[ "$PRERELEASE" -eq 1 ]]; then
        create_args+=(--prerelease)
    fi

    log "Creating GitHub release $TAG"
    gh release create "${create_args[@]}" "${repo_args[@]}"
}

if [[ "$SKIP_UPLOAD" -eq 0 ]]; then
    publish_release
else
    log "Skipping GitHub release upload"
fi

log "Release build complete"
printf 'Version: %s\n' "$RELEASE_VERSION"
printf 'Marketing Version: %s\n' "$VERSION"
printf 'Build Number: %s\n' "$BUILD_NUMBER"
printf 'Tag: %s\n' "$TAG"
printf 'Artifact: %s\n' "$ASSET_PATH"
