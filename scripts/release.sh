#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MDViewerMac"
SCHEME="MDViewerMac"
PROJECT_FILE="MDViewerMac.xcodeproj"
CONFIGURATION="Release"
DESTINATION="platform=macOS"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
BUILD_DIR="$ROOT_DIR/.build/release"
DERIVED_DATA_DIR="$BUILD_DIR/DerivedData"
INFO_PLIST="$ROOT_DIR/App/Generated/Info.plist"

VERSION=""
TAG=""
REPO=""
REMOTE="origin"
NOTES_FILE=""
DRAFT=0
PRERELEASE=0
SKIP_TESTS=0
SKIP_UPLOAD=0
ALLOW_DIRTY=0

usage() {
    cat <<'EOF'
Usage: scripts/release.sh [options]

Builds the renderer, builds the macOS app in Release mode, packages the .app
as a zip file, and publishes it to a GitHub Release with the GitHub CLI.

Options:
  --tag TAG            Release tag. Defaults to v<CFBundleShortVersionString>.
  --repo OWNER/REPO    GitHub repository for gh release commands.
  --remote NAME        Git remote used when pushing a new tag. Default: origin.
  --notes-file PATH    Release notes file. Defaults to GitHub generated notes.
  --draft             Create the GitHub release as a draft.
  --prerelease        Mark the GitHub release as a prerelease.
  --skip-tests        Skip the XCTest step.
  --skip-upload       Build and package locally without creating a GitHub release.
  --allow-dirty       Allow releasing with uncommitted working tree changes.
  -h, --help          Show this help message.

Examples:
  scripts/release.sh --draft
  scripts/release.sh --tag v0.1.0 --repo dualface/mdviewer-mac
  scripts/release.sh --skip-upload --allow-dirty
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

ensure_clean_working_tree() {
    local context="$1"

    if [[ "$ALLOW_DIRTY" -eq 0 && -n "$(git status --porcelain)" ]]; then
        fail "Working tree has uncommitted changes $context. Commit them or pass --allow-dirty."
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
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

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
[[ -n "$VERSION" ]] || fail "Could not read CFBundleShortVersionString from $INFO_PLIST"

if [[ -z "$TAG" ]]; then
    TAG="v$VERSION"
fi

ASSET_PATH="$DIST_DIR/$APP_NAME-$VERSION-macOS.zip"

if [[ "$SKIP_TESTS" -eq 0 ]]; then
    log "Running tests"
    xcodebuild \
        -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -destination "$DESTINATION" \
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
    clean build

PRODUCTS_DIR="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION"
APP_PATH="$PRODUCTS_DIR/$APP_NAME.app"

if [[ ! -d "$APP_PATH" ]]; then
    APP_PATH="$(find "$PRODUCTS_DIR" -maxdepth 1 -name '*.app' -type d -print -quit)"
fi

[[ -n "$APP_PATH" && -d "$APP_PATH" ]] || fail "Could not find built .app in $PRODUCTS_DIR"

log "Packaging app"
rm -f "$ASSET_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ASSET_PATH"

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
printf 'Version: %s (%s)\n' "$VERSION" "$BUILD_NUMBER"
printf 'Tag: %s\n' "$TAG"
printf 'Artifact: %s\n' "$ASSET_PATH"
