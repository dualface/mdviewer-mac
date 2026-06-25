# Repository Guidelines

## Project Structure & Module Organization

This repository contains a native macOS Markdown viewer. Swift app code lives in `App/Sources`, with focused files such as `WorkspaceModel.swift`, `RendererWebView.swift`, and `PathResolver.swift`. Unit tests live in `App/Tests`. App metadata and entitlements are generated into `App/Generated` from `project.yml`. Bundled app assets are under `App/Resources`, including the generated offline renderer bundle at `App/Resources/Renderer`.

The renderer source is a separate Vite project in `Renderer`. Edit `Renderer/src/main.js` and `Renderer/src/styles.css`, then rebuild to refresh the bundled files used by the WebView.

## Build, Test, and Development Commands

- `cd Renderer && npm install`: install renderer dependencies from `package-lock.json`.
- `cd Renderer && npm run build`: build the offline renderer bundle and run `scripts/fix-html.mjs`.
- `xcodegen generate`: regenerate `MDViewerMac.xcodeproj` from `project.yml`.
- `xcodebuild -project MDViewerMac.xcodeproj -scheme MDViewerMac -destination 'platform=macOS' build`: build the macOS app.
- `xcodebuild -project MDViewerMac.xcodeproj -scheme MDViewerMac -destination 'platform=macOS' test`: run XCTest unit tests.

Run the renderer build before app builds when changing files under `Renderer/src`.

## Coding Style & Naming Conventions

Swift code uses four-space indentation, SwiftUI view structs, and descriptive type names in `UpperCamelCase`. Functions, properties, enum cases, and local variables use `lowerCamelCase`. Keep domain logic in small model/helper types where possible, and keep UI-specific behavior inside SwiftUI views. JavaScript in the renderer uses ES modules and should stay framework-light, matching the existing Vite setup.

## Testing Guidelines

Tests use XCTest and are located in `App/Tests`. Name test files after the type or behavior under test, for example `PathResolverTests.swift`. Name test methods with `test...` and make expectations explicit with `XCTAssert...`. Add or update tests when changing path resolution, file loading, workspace behavior, or renderer-facing contracts.

## Commit & Pull Request Guidelines

This repository currently has no commit history, so no project-specific commit convention is established. Use short imperative commit messages such as `Add renderer link handling tests`. Pull requests should include a concise summary, test results, and screenshots or screen recordings for visible UI changes. Link related issues when available and mention any generated files, especially updates to `MDViewerMac.xcodeproj` or `App/Resources/Renderer`.

## Security & Configuration Tips

The app is sandboxed and relies on user-selected read-only file access plus app-scoped bookmarks. Preserve these constraints when changing file access code, and avoid adding broad filesystem or network behavior without documenting the reason in `project.yml`.
