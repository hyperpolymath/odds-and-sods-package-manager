// SPDX-License-Identifier: PMPL-1.0
// Main OPSM Mobile Application - TEA architecture with routing

open Tea
open TauriFFI

// =============================================================================
// Model
// =============================================================================

type model = {
  currentRoute: Route.t,
  packages: array<TauriFFI.package>,
  searchQuery: string,
  searchResults: option<TauriFFI.searchResult>,
  selectedPackage: option<TauriFFI.package>,
  installedPackages: array<TauriFFI.package>,
  installStatus: TauriFFI.installStatus,
  error: option<string>,
  loading: bool,
}

let initialModel = {
  currentRoute: Home,
  packages: [],
  searchQuery: "",
  searchResults: None,
  selectedPackage: None,
  installedPackages: [],
  installStatus: NotStarted,
  error: None,
  loading: false,
}

// =============================================================================
// Messages
// =============================================================================

type msg =
  | UrlChanged(Route.t)
  | Navigate(Route.t)
  | UpdateSearchQuery(string)
  | SearchPackages(string)
  | SearchResult(result<TauriFFI.searchResult, Tauri_Command.commandError>)
  | SelectPackage(string, string)
  | PackageInfoLoaded(result<TauriFFI.package, Tauri_Command.commandError>)
  | InstallPackage(string, string, string)
  | InstallComplete(result<unit, Tauri_Command.commandError>)
  | LoadInstalled
  | InstalledLoaded(result<array<TauriFFI.package>, Tauri_Command.commandError>)
  | ClearError

// =============================================================================
// Update
// =============================================================================

let update = (msg: msg, model: model): (model, Cmd.t<msg>) => {
  switch msg {
  | UrlChanged(route) =>
      // Handle route changes (from browser back/forward)
      let newModel = {...model, currentRoute: route}

      // Load data based on route
      switch route {
      | Home => (newModel, Cmd.none)
      | Search(query) => (
          {...newModel, searchQuery: query, loading: true},
          TauriFFI.searchPackages(query, "npm", result => SearchResult(result)),
        )
      | PackageDetail(name, version) => (
          {...newModel, loading: true},
          TauriFFI.getPackageInfo(name, version, result => PackageInfoLoaded(result)),
        )
      | Install(registry, name, version) => (
          {...newModel, installStatus: Installing},
          TauriFFI.installPackage(registry, name, version, result => InstallComplete(result)),
        )
      | Installed => (
          {...newModel, loading: true},
          TauriFFI.listInstalled(result => InstalledLoaded(result)),
        )
      | Settings => (newModel, Cmd.none)
      | NotFound => (newModel, Cmd.none)
      }

  | Navigate(route) =>
      // Programmatic navigation
      (
        {...model, currentRoute: route},
        CadreTeaRouter.Router.push(Route.toString(route)),
      )

  | UpdateSearchQuery(query) =>
      ({...model, searchQuery: query}, Cmd.none)

  | SearchPackages(query) =>
      (
        {...model, loading: true, error: None},
        TauriFFI.searchPackages(query, "npm", result => SearchResult(result)),
      )

  | SearchResult(Ok(result)) =>
      (
        {...model, searchResults: Some(result), loading: false},
        Cmd.none,
      )

  | SearchResult(Error(err)) =>
      (
        {...model, error: Some(Tauri_Command.CommandError.toString(err)), loading: false},
        Cmd.none,
      )

  | SelectPackage(name, version) =>
      (
        {...model, loading: true},
        TauriFFI.getPackageInfo(name, version, result => PackageInfoLoaded(result)),
      )

  | PackageInfoLoaded(Ok(pkg)) =>
      ({...model, selectedPackage: Some(pkg), loading: false}, Cmd.none)

  | PackageInfoLoaded(Error(err)) =>
      (
        {...model, error: Some(Tauri_Command.CommandError.toString(err)), loading: false},
        Cmd.none,
      )

  | InstallPackage(registry, name, version) =>
      (
        {...model, installStatus: Installing, error: None},
        TauriFFI.installPackage(registry, name, version, result => InstallComplete(result)),
      )

  | InstallComplete(Ok()) =>
      (
        {...model, installStatus: Installed},
        Cmd.batch([
          Cmd.message(Navigate(Installed)),
          TauriFFI.listInstalled(result => InstalledLoaded(result)),
        ]),
      )

  | InstallComplete(Error(err)) =>
      (
        {
          ...model,
          installStatus: Failed(Tauri_Command.CommandError.toString(err)),
          error: Some(Tauri_Command.CommandError.toString(err)),
        },
        Cmd.none,
      )

  | LoadInstalled =>
      (
        {...model, loading: true},
        TauriFFI.listInstalled(result => InstalledLoaded(result)),
      )

  | InstalledLoaded(Ok(packages)) =>
      ({...model, installedPackages: packages, loading: false}, Cmd.none)

  | InstalledLoaded(Error(err)) =>
      (
        {...model, error: Some(Tauri_Command.CommandError.toString(err)), loading: false},
        Cmd.none,
      )

  | ClearError => ({...model, error: None}, Cmd.none)
  }
}

// =============================================================================
// View
// =============================================================================

let viewPackage = (pkg: TauriFFI.package, dispatch) => {
  <div className="package-card">
    <h3> {React.string(pkg.name ++ " v" ++ pkg.version)} </h3>
    <p className="registry"> {React.string("Registry: " ++ pkg.registry)} </p>
    {switch pkg.description {
    | Some(desc) => <p className="description"> {React.string(desc)} </p>
    | None => React.null
    }}
    {switch pkg.license {
    | Some(license) => <p className="license"> {React.string("License: " ++ license)} </p>
    | None => React.null
    }}
    <button
      onClick={_ => dispatch(Navigate(PackageDetail(pkg.name, pkg.version)))}
    >
      {React.string("View Details")}
    </button>
    <button
      onClick={_ => dispatch(InstallPackage(pkg.registry, pkg.name, pkg.version))}
    >
      {React.string("Install")}
    </button>
  </div>
}

let viewHome = (model, dispatch) => {
  <div className="home">
    <h1> {React.string("OPSM - Odds and Sods Package Manager")} </h1>
    <p> {React.string("Federated, multi-language package manager with formal verification")} </p>

    <div className="search-box">
      <input
        type_="text"
        placeholder="Search packages..."
        value={model.searchQuery}
        onChange={e => {
          let value = ReactEvent.Form.target(e)["value"]
          dispatch(UpdateSearchQuery(value))
        }}
        onKeyDown={e => {
          if ReactEvent.Keyboard.key(e) == "Enter" && model.searchQuery != "" {
            dispatch(SearchPackages(model.searchQuery))
          }
        }}
      />
      <button
        onClick={_ => {
          if model.searchQuery != "" {
            dispatch(SearchPackages(model.searchQuery))
          }
        }}
        disabled={model.searchQuery == ""}
      >
        {React.string("Search")}
      </button>
    </div>

    <div className="quick-actions">
      <button onClick={_ => dispatch(Navigate(Installed))}>
        {React.string("View Installed Packages")}
      </button>
      <button onClick={_ => dispatch(Navigate(Settings))}>
        {React.string("Settings")}
      </button>
    </div>
  </div>
}

let viewSearch = (model, dispatch) => {
  <div className="search-page">
    <h2> {React.string("Search Results: " ++ model.searchQuery)} </h2>

    {if model.loading {
      <p> {React.string("Loading...")} </p>
    } else {
      switch model.searchResults {
      | Some(results) =>
        <div className="search-results">
          <p> {React.string(`Found ${Belt.Int.toString(results.total)} packages`)} </p>
          <div className="package-list">
            {Belt.Array.map(results.packages, pkg => viewPackage(pkg, dispatch))
              ->React.array}
          </div>
        </div>
      | None => <p> {React.string("No results yet")} </p>
      }
    }}
  </div>
}

let viewPackageDetail = (model, dispatch) => {
  <div className="package-detail">
    {if model.loading {
      <p> {React.string("Loading package details...")} </p>
    } else {
      switch model.selectedPackage {
      | Some(pkg) =>
        <div>
          <h2> {React.string(pkg.name)} </h2>
          <p className="version"> {React.string("Version: " ++ pkg.version)} </p>
          <p className="registry"> {React.string("Registry: " ++ pkg.registry)} </p>

          {switch pkg.description {
          | Some(desc) => <p className="description"> {React.string(desc)} </p>
          | None => React.null
          }}

          {switch pkg.license {
          | Some(license) => <p className="license"> {React.string("License: " ++ license)} </p>
          | None => React.null
          }}

          {switch pkg.homepage {
          | Some(url) =>
            <p className="homepage">
              <a href={url} target="_blank"> {React.string("Homepage")} </a>
            </p>
          | None => React.null
          }}

          <button
            onClick={_ => dispatch(InstallPackage(pkg.registry, pkg.name, pkg.version))}
            disabled={switch model.installStatus {
            | Installing => true
            | _ => false
            }}
          >
            {React.string(switch model.installStatus {
            | NotStarted => "Install"
            | Installing => "Installing..."
            | Installed => "Installed"
            | Failed(_) => "Install Failed - Retry"
            })}
          </button>
        </div>
      | None => <p> {React.string("Package not found")} </p>
      }
    }}
  </div>
}

let viewInstalled = (model, dispatch) => {
  <div className="installed-page">
    <h2> {React.string("Installed Packages")} </h2>

    {if model.loading {
      <p> {React.string("Loading installed packages...")} </p>
    } else if Belt.Array.length(model.installedPackages) == 0 {
      <p> {React.string("No packages installed yet")} </p>
    } else {
      <div className="package-list">
        {Belt.Array.map(model.installedPackages, pkg => viewPackage(pkg, dispatch))
          ->React.array}
      </div>
    }}
  </div>
}

let viewSettings = (_model, _dispatch) => {
  <div className="settings-page">
    <h2> {React.string("Settings")} </h2>
    <p> {React.string("Settings page coming soon...")} </p>
  </div>
}

let viewError = (error, dispatch) => {
  <div className="error-banner">
    <p> {React.string("Error: " ++ error)} </p>
    <button onClick={_ => dispatch(ClearError)}>
      {React.string("Dismiss")}
    </button>
  </div>
}

let view = (model: model, dispatch): React.element => {
  <div className="app">
    <nav className="nav">
      <button onClick={_ => dispatch(Navigate(Home))}>
        {React.string("Home")}
      </button>
      <button onClick={_ => dispatch(Navigate(Installed))}>
        {React.string("Installed")}
      </button>
      <button onClick={_ => dispatch(Navigate(Settings))}>
        {React.string("Settings")}
      </button>
    </nav>

    {switch model.error {
    | Some(err) => viewError(err, dispatch)
    | None => React.null
    }}

    <main className="main-content">
      {switch model.currentRoute {
      | Home => viewHome(model, dispatch)
      | Search(query) => viewSearch(model, dispatch)
      | PackageDetail(_, _) => viewPackageDetail(model, dispatch)
      | Install(_, _, _) => <p> {React.string("Installing...")} </p>
      | Installed => viewInstalled(model, dispatch)
      | Settings => viewSettings(model, dispatch)
      | NotFound => <div> <h2> {React.string("404 - Page Not Found")} </h2> </div>
      }}
    </main>
  </div>
}

// =============================================================================
// Subscriptions
// =============================================================================

let subscriptions = (_model: model): Sub.t<msg> => {
  // Subscribe to URL changes from browser back/forward
  CadreTeaRouter.Router.urlChanges(url =>
    UrlChanged(Route.fromUrl(url))
  )
}

// =============================================================================
// Init
// =============================================================================

let init = (_flags: unit): (model, Cmd.t<msg>) => {
  // Get initial route from current URL
  let currentUrl = CadreTeaRouter.Router.getCurrentUrl()
  let initialRoute = Route.fromUrl(currentUrl)

  let model = {...initialModel, currentRoute: initialRoute}

  // Load data for initial route
  let cmd = switch initialRoute {
  | Installed => TauriFFI.listInstalled(result => InstalledLoaded(result))
  | _ => Cmd.none
  }

  (model, cmd)
}

// =============================================================================
// App
// =============================================================================

module App = MakeWithDispatch({
  type nonrec model = model
  type nonrec msg = msg
  type flags = unit
  let init = init
  let update = update
  let view = view
  let subscriptions = subscriptions
})

// =============================================================================
// Entry Point
// =============================================================================

switch ReactDOM.querySelector("#root") {
| Some(root) => {
    let rootElement = ReactDOM.Client.createRoot(root)
    rootElement->ReactDOM.Client.Root.render(<App flags=() />)
  }
| None => Console.error("Root element not found")
}
