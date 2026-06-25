# MDViewer Mac

MDViewer Mac is a native macOS Markdown viewer built with SwiftUI and WKWebView. It loads an offline renderer bundle inside the app, making it useful for browsing local Markdown documents, code snippets, images, and documentation workspaces.

## Features

- Open a single Markdown file or an entire folder workspace.
- Browse workspace files with a native sidebar.
- Preview Markdown, images, plain text, and code files.
- Render Mermaid diagrams, KaTeX math, tables, task lists, footnotes, and definition lists.
- Highlight code with highlight.js.
- Resolve relative image paths and Markdown links inside the active workspace.
- Use multiple preview tabs, refresh, light/dark/system themes, font size controls, and preview width settings.
- Access only user-selected files and folders through macOS sandbox permissions.

## Requirements

- macOS 14.0 or later.
- Xcode 26.0 or a compatible version.
- Node.js and npm for building the WebView renderer.
- XcodeGen for generating the Xcode project from `project.yml`.

## Project Structure

```text
App/
  Sources/              SwiftUI app source code
  Tests/                XCTest unit tests
  Resources/            App assets and offline renderer bundle
  Generated/            Info.plist and entitlements generated from project.yml
Renderer/
  src/                  Markdown renderer source
  scripts/              Build post-processing scripts
project.yml             XcodeGen project configuration
MDViewerMac.xcodeproj   Generated Xcode project
```

## Quick Start

Install dependencies and build the renderer:

```bash
cd Renderer
npm install
npm run build
cd ..
```

Generate the Xcode project:

```bash
xcodegen generate
```

Build the app:

```bash
xcodebuild -project MDViewerMac.xcodeproj -scheme MDViewerMac -destination 'platform=macOS' build
```

Run tests:

```bash
xcodebuild -project MDViewerMac.xcodeproj -scheme MDViewerMac -destination 'platform=macOS' test
```

You can also open `MDViewerMac.xcodeproj` in Xcode, select the `MDViewerMac` scheme, and run the app from there.

## Development Notes

Swift app code lives in `App/Sources`. The main modules cover workspace state, path resolution, tab modeling, and WKWebView rendering integration. Tests live in `App/Tests` and currently cover file item loading and path resolution behavior.

The renderer is a separate Vite project. After changing files under `Renderer/src`, rebuild it with:

```bash
cd Renderer
npm run build
```

The build output is written to `App/Resources/Renderer` and bundled into the macOS app so Markdown rendering works offline.

## Release

Use `scripts/release.sh` to build, package, and publish a GitHub Release. The script installs renderer dependencies with `npm ci`, builds the offline renderer, regenerates the Xcode project, runs XCTest, builds the app in Release mode, packages the `.app` as a zip file, and uploads it with the GitHub CLI.

Before publishing, authenticate the GitHub CLI:

```bash
gh auth login
```

Create a draft release using the version from `App/Generated/Info.plist`:

```bash
scripts/release.sh --draft
```

Build locally without uploading:

```bash
scripts/release.sh --skip-upload --allow-dirty
```

Useful options include `--tag v0.1.0`, `--repo owner/repo`, `--notes-file RELEASE_NOTES.md`, `--prerelease`, and `--skip-tests`. The script requires a clean working tree by default; pass `--allow-dirty` only for local packaging.

## Sandbox and File Access

The app uses macOS App Sandbox. File access depends on user-selected files or directories and app-scoped bookmarks. Keep the read-only access model intact when changing file handling, and avoid adding broad filesystem permissions without documenting the reason.

## Contributing

Before submitting changes, run the renderer build and XCTest suite. Include screenshots or recordings for visible UI changes. Add tests for path resolution, file loading, and renderer protocol changes.
