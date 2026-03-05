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

# Launch as menu bar app (development)
./scripts/build-appstore.sh
open .build/appstore/FabricTray.app
```

> **Note:** SwiftPM executables don't register with the macOS menu bar natively. The `.app` bundle wrapper with `LSUIElement=true` is required for the tray icon to appear.

## App Store Build

The project includes everything needed for Mac App Store submission.

### 1. Add App Icon (required for App Store)

Place PNG icons in `Sources/FabricTray/Resources/Assets.xcassets/AppIcon.appiconset/` using standard macOS naming:

```
icon_16x16.png, icon_16x16@2x.png
icon_32x32.png, icon_32x32@2x.png
icon_128x128.png, icon_128x128@2x.png
icon_256x256.png, icon_256x256@2x.png
icon_512x512.png, icon_512x512@2x.png
```

### 2. Build & Sign

```bash
# Unsigned build (for local testing)
./scripts/build-appstore.sh

# Signed with Hardened Runtime (for notarization / direct distribution)
./scripts/build-appstore.sh --sign "Developer ID Application: Your Name (TEAMID)"

# Archive for App Store submission
./scripts/build-appstore.sh --archive "3rd Party Mac Developer Application: Your Name (TEAMID)"
```

### 3. Submit

```bash
xcrun altool --upload-app -f .build/appstore/FabricTray.pkg -t osx -u YOUR_APPLE_ID
```

### App Store Files

| File | Purpose |
|------|---------|
| `Sources/FabricTray/Resources/Info.plist` | App metadata, version, URL scheme, category |
| `Sources/FabricTray/Resources/FabricTray.entitlements` | App Sandbox + network + Keychain + file access |
| `Sources/FabricTray/Resources/PrivacyInfo.xcprivacy` | Privacy manifest (UserDefaults declaration) |
| `Sources/FabricTray/Resources/Assets.xcassets/` | App icon asset catalog |
| `scripts/build-appstore.sh` | Automated build, sign, and archive |

### Entitlements

The app requests these sandbox entitlements:
- **App Sandbox** — required for App Store
- **Outgoing Network** — Fabric REST API and Microsoft OAuth
- **Keychain Access** — secure token storage
- **User-Selected Files** — export/import via save/open panels

## Configuration

Uses a multi-tenant Entra app by default. Override with environment variables:

```bash
export FABRIC_TRAY_TENANT_ID=organizations
export FABRIC_TRAY_CLIENT_ID=<your-client-id>
```

## Fabric CLI Feature Parity

| Fabric CLI | FabricTray |
|---|---|
| `auth login / logout` | Sign In / Sign Out via OAuth PKCE flow |
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
├── MicrosoftAuthService.swift# OAuth PKCE flow
├── TokenStore.swift          # Keychain token persistence
├── TrayView.swift            # SwiftUI tray UI
├── TrayPreferences.swift     # Density/sizing preferences
├── FabricIcon.swift          # SVG icon loader
├── AppDefaults.swift         # Default configuration
└── Resources/
    ├── Info.plist             # App bundle metadata
    ├── FabricTray.entitlements# Sandbox entitlements
    ├── PrivacyInfo.xcprivacy  # Privacy manifest
    ├── Assets.xcassets/       # App icon asset catalog
    └── Icons/                 # Fabric SVG tray icons

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
