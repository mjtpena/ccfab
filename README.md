# FabricTray

A native macOS menu bar app for [Microsoft Fabric](https://www.microsoft.com/en-us/microsoft-fabric). Browse tenants, workspaces, and items — run notebooks, manage access, assign capacities, and more — all from a compact tray icon.

Inspired by [CCMenu](https://ccmenu.org) and the [Microsoft Fabric CLI](https://microsoft.github.io/fabric-cli/).

## Features

- **OAuth sign-in** with Microsoft Entra ID (tokens stored in macOS Keychain)
- **Workspace & item browser** — file-browser-style navigation with breadcrumbs
- **Full Fabric CLI parity** — create, rename, delete workspaces and items
- **Run items** — execute notebooks, pipelines, and Spark jobs with optional parameters
- **Job monitoring** — live polling of running/completed jobs
- **Capacity management** — assign and unassign capacities to workspaces
- **Access control** — view, add, and remove workspace role assignments
- **Sensitivity labels** — set and remove labels on items
- **Export/Import** — export item definitions to JSON, import them back
- **Shortcuts & uploads** — create OneLake shortcuts, upload files via DFS API
- **Lakehouse tables** — list and load tables
- **Density settings** — compact / standard / comfortable sizing (S / M / L)
- **Custom Fabric icon** — template-based menu bar icon adapts to light/dark mode

## Requirements

- macOS 13+
- Swift 5.9+
- A Microsoft Entra app registration (or use the built-in defaults)

## Quick Start

```bash
# Build
swift build

# Run tests
swift test

# Launch as menu bar app
mkdir -p .build/FabricTray.app/Contents/{MacOS,Resources}
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

> **Note:** SwiftPM executables don't register with the macOS menu bar natively. The `.app` bundle wrapper with `LSUIElement=true` is required for the tray icon to appear.

## Configuration

Uses a multi-tenant Entra app by default. Override with environment variables:

```bash
export FABRIC_TRAY_TENANT_ID=organizations
export FABRIC_TRAY_CLIENT_ID=<your-client-id>
```

## Fabric CLI Feature Parity

| Fabric CLI | FabricTray |
|---|---|
| `auth login / logout` | Sign In / Sign Out via OAuth device code flow |
| `ls` / `cd` | Breadcrumb navigation + searchable item list |
| `open` | Open-in-browser per item (context menu) |
| `run` / `start` | Run button with optional execution parameters |
| `job list` | Live job status polling with cancel support |
| `mkdir` | Create workspace / create item (+ button) |
| `rm` | Delete workspace / item (context menu) |
| `mv` / `rename` | Rename workspace / item (context menu) |
| `capacity assign / unassign` | Capacity management (context menu) |
| `acl list / add / remove` | Role assignment viewer with add/remove |
| `label set / remove` | Sensitivity label management |
| `export / import` | Export/import item definitions as JSON |
| `ln` (shortcuts) | Create OneLake shortcuts |
| `cp` (upload) | Upload files to OneLake via DFS API |
| `table list / load` | Lakehouse table listing and loading |

## Project Structure

```
Sources/FabricTray/
├── FabricTrayApp.swift       # @main App entry, MenuBarExtra
├── Models.swift              # Data types, ActionKind enum
├── AppState.swift            # Central @MainActor state management
├── FabricAPIClient.swift     # Fabric REST API communication
├── MicrosoftAuthService.swift# OAuth device code flow
├── TokenStore.swift          # Keychain token persistence
├── TrayView.swift            # SwiftUI tray UI
├── TrayPreferences.swift     # Density/sizing preferences
├── FabricIcon.swift          # SVG icon loader
├── AppDefaults.swift         # Default configuration
└── Resources/Icons/          # Fabric SVG tray icon

Tests/FabricTrayTests/
├── ModelsTests.swift
├── PendingActionTests.swift
├── TrayPreferencesTests.swift
├── FabricAPIClientTests.swift
└── AppStateTests.swift
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[MIT](LICENSE)
