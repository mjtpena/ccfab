# Contributing to FabricTray

Thanks for your interest in contributing! Here's how to get started.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/<your-user>/ccfab.git`
3. Build: `swift build`
4. Run tests: `swift test`

## Running the App

FabricTray is a macOS menu bar app. Because SwiftPM executables don't automatically register with the macOS status bar, you need to launch it as an `.app` bundle:

```bash
swift build
mkdir -p .build/FabricTray.app/Contents/MacOS .build/FabricTray.app/Contents/Resources
cp .build/arm64-apple-macosx/debug/FabricTray .build/FabricTray.app/Contents/MacOS/
cp -R .build/arm64-apple-macosx/debug/FabricTray_FabricTray.bundle .build/FabricTray.app/Contents/Resources/ 2>/dev/null || true
cat > .build/FabricTray.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.fabrictray.app</string>
  <key>CFBundleName</key><string>FabricTray</string>
  <key>CFBundleExecutable</key><string>FabricTray</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
open .build/FabricTray.app
```

## Pull Requests

- Keep changes focused and minimal
- Add tests for new functionality
- Run `swift test` before submitting
- Describe what the PR does and why

## Reporting Issues

Open an issue with:
- What you expected vs what happened
- macOS version and Swift version (`swift --version`)
- Steps to reproduce

## Code Style

- Follow existing Swift conventions in the codebase
- Use `@MainActor` for UI-related classes
- Keep API client methods thin — parsing logic in models
