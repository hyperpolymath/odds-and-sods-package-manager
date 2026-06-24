<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# OPSM Mobile - Native iOS/Android Wrapper

Native mobile app for OPSM (Odds and Sods Package Manager) using Tauri 2.0 with ReScript TEA architecture.

## Architecture

```
┌─────────────────────────────────┐
│   ReScript TEA App              │
│   ├─ Route.res (cadre-router)   │
│   ├─ App.res (TEA with routing) │
│   └─ TauriFFI.res (commands)    │
└────────────┬────────────────────┘
             │ Tauri FFI
┌────────────▼────────────────────┐
│   Tauri 2.0 (Rust)              │
│   ├─ iOS (Swift + Rust)         │
│   └─ Android (Kotlin + Rust)    │
└────────────┬────────────────────┘
             │ HTTP REST API
┌────────────▼────────────────────┐
│   OPSM Phoenix Backend (Elixir)  │
│   (100% code reuse from CLI)    │
└─────────────────────────────────┘
```

## Technology Stack

- **UI Layer**: ReScript + rescript-tea (The Elm Architecture)
- **Routing**: cadre-router + cadre-tea-router (type-safe URL routing)
- **Native Layer**: Tauri 2.0 (compiles to native iOS/Android)
- **Backend**: OPSM Phoenix (Elixir) - reuses existing CLI codebase

## Features

- ✅ Type-safe routing with cadre-router
- ✅ TEA architecture for predictable state management
- ✅ Full package search and installation
- ✅ View installed packages
- ✅ Integration with all 8 OPSM registries (npm, Hex, Crates, PyPI, Nimble, Idris2, Git, Agentic)

## Prerequisites

- **Deno** (JavaScript runtime) - https://deno.land/
- **ReScript** - Installed via Deno
- **Tauri CLI** - `cargo install tauri-cli`
- **Rust** - https://rustup.rs/
- **For iOS**: macOS with Xcode
- **For Android**: Android Studio and Android SDK

## Setup

### 1. Install Dependencies

```bash
cd opsm_mobile

# ReScript dependencies are managed via Deno
# No npm/node_modules needed!
```

### 2. Build ReScript Code

```bash
deno task build
```

This compiles ReScript (.res) files to JavaScript (.res.js).

### 3. Run on Desktop (Developsment)

```bash
# In one terminal: watch for ReScript changes
deno task dev

# In another terminal: run Tauri dev server
deno task tauri
```

The app will open as a native desktop window (for testing before mobile deployment).

### 4. Build for Mobile

#### Android

```bash
# Initialize Android project (first time only)
deno task tauri:android

# Or manually:
# cargo tauri android init
# cargo tauri android build
```

#### iOS

```bash
# Initialize iOS project (first time only)
deno task tauri:ios

# Or manually:
# cargo tauri ios init
# cargo tauri ios build
```

## Project Structure

```
opsm_mobile/
├── src/
│   ├── Route.res            # Route definitions (cadre-router)
│   ├── App.res              # Main TEA app with routing
│   └── TauriFFI.res         # Tauri command bindings
├── docs/
│   └── ARCHITECTURE.adoc    # Detailed architecture documentation
├── index.html               # Entry point
├── rescript.json            # ReScript config
├── deno.json                # Deno import map + tasks
└── README.md                # This file
```

## How It Works

### 1. Type-Safe Routing

Routes are defined as ReScript variants using cadre-router:

```rescript
type t =
  | Home
  | Search(string)
  | PackageDetail(string, string)
  | Install(string, string, string)
  | Installed
  | Settings
  | NotFound
```

### 2. TEA Architecture

The app follows The Elm Architecture pattern with rescript-tea:

- **Model**: Single source of truth for app state
- **View**: Pure function of model (React components)
- **Update**: Pure function handling all messages
- **Commands**: Descriptions of side effects (API calls, navigation)
- **Subscriptions**: External event sources (URL changes)

### 3. Tauri Commands

ReScript code calls Rust backend via typed commands:

```rescript
// TauriFFI.res
let searchCommand = Tauri_Command.defineCommand(
  ~name="search_packages",
  ~encode=((query, registry)) => {...},
  ~decode=decodeSearchResult,
)

// Wrap for TEA
let searchPackages = (query, registry, toMsg) =>
  Tea.Cmd.call(callbacks => {
    let _ = Tauri_Command.execute(searchCommand, (query, registry))
      ->Promise.thenResolve(result => callbacks.enqueue(toMsg(result)))
  })
```

### 4. Rust Tauri Backend

Rust commands communicate with Elixir Phoenix backend:

```rust
#[tauri::command]
async fn search_packages(query: String, registry: String) -> Result<SearchResult, String> {
    let url = format!("http://localhost:4000/api/packages/search?q={}&registry={}", query, registry);
    let response = reqwest::Client::new().get(&url).send().await?;
    response.json::<SearchResult>().await.map_err(|e| e.to_string())
}
```

## Developsment Workflow

1. **Start API host** (mounts `Opsm.Api.Router` from `opsm_mobile/api`):
   ```bash
   # from your host app directory
   mix phx.server
   ```

2. **Run Tauri dev** (in opsm_mobile directory):
   ```bash
   deno task dev     # Terminal 1: ReScript watch
   deno task tauri   # Terminal 2: Tauri dev
   ```

3. **Make changes** to `.res` files - they auto-compile and hot-reload

4. **Build for mobile**:
   ```bash
   deno task tauri:android  # Android
   deno task tauri:ios      # iOS
   ```

## Benefits of This Architecture

1. **100% Code Reuse**: All OPSM Elixir logic (dependency resolution, trust pipeline, registry adapters) is reused via API
2. **Type Safety**: Routes, messages, and API calls are fully type-checked by ReScript compiler
3. **Predictable State**: TEA architecture guarantees state consistency
4. **Native Performance**: Tauri compiles to true native apps (not web views)
5. **Standard Compliance**: Uses approved tech stack (ReScript, Rust, Elixir)
6. **Zero npm**: Deno manages dependencies without node_modules

## API Endpoints Required

The Phoenix backend must expose these endpoints:

- `POST /api/packages/install` - Install a package
- `GET /api/packages/search` - Search packages
- `GET /api/packages/:name/:version` - Get package info
- `POST /api/lockfile/audit` - Audit dependencies
- `GET /api/packages/installed` - List installed packages

## Next Steps

1. ✅ Create Phoenix API endpoints
2. ✅ Implement Tauri Rust commands
3. ✅ Build ReScript UI with TEA + routing
4. [ ] Test on desktop
5. [ ] Test on iOS simulator
6. [ ] Test on Android emulator
7. [ ] Publish to app stores

## License

PMPL-1.0
