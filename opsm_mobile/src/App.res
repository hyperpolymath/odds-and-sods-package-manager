// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// Main OPSM Mobile Application - TEA architecture with routing

open Tea
open OpsmCommands

// =============================================================================
// Model
// =============================================================================

type model = {
  currentRoute: Route.t,
  packages: array<OpsmCommands.package>,
  searchQuery: string,
  searchResults: option<OpsmCommands.searchResult>,
  selectedPackage: option<OpsmCommands.package>,
  installedPackages: array<OpsmCommands.package>,
  installStatus: OpsmCommands.installStatus,
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
  | SearchResult(result<OpsmCommands.searchResult, OpsmCommands.ipcError>)
  | SelectPackage(string, string)
  | PackageInfoLoaded(result<OpsmCommands.package, OpsmCommands.ipcError>)
  | InstallPackage(string, string, string)
  | InstallComplete(result<unit, OpsmCommands.ipcError>)
  | LoadInstalled
  | InstalledLoaded(result<array<OpsmCommands.package>, OpsmCommands.ipcError>)
  | ClearError

// =============================================================================
// Update
// =============================================================================

let update = (msg: msg, model: model): (model, Cmd.t<msg>) => {
  switch msg {
  | UrlChanged(route) =>
      let newModel = {...model, currentRoute: route}
      switch route {
      | Home => (newModel, Cmd.none)
      | Search(query) => (
          {...newModel, searchQuery: query, loading: true},
          OpsmCommands.searchPackages(query, "npm", result => SearchResult(result)),
        )
      | PackageDetail(name, version) => (
          {...newModel, loading: true},
          OpsmCommands.getPackageInfo(name, version, result => PackageInfoLoaded(result)),
        )
      | Install(registry, name, version) => (
          {...newModel, installStatus: Installing},
          OpsmCommands.installPackage(registry, name, version, result => InstallComplete(result)),
        )
      | Installed => (
          {...newModel, loading: true},
          OpsmCommands.listInstalled(result => InstalledLoaded(result)),
        )
      | Settings => (newModel, Cmd.none)
      | NotFound => (newModel, Cmd.none)
      }

  | Navigate(route) =>
      (
        {...model, currentRoute: route},
        CadreTeaRouter.Router.push(Route.toString(route)),
      )

  | UpdateSearchQuery(query) =>
      ({...model, searchQuery: query}, Cmd.none)

  | SearchPackages(query) =>
      (
        {...model, loading: true, error: None},
        OpsmCommands.searchPackages(query, "npm", result => SearchResult(result)),
      )

  | SearchResult(Ok(result)) =>
      ({...model, searchResults: Some(result), loading: false}, Cmd.none)

  | SearchResult(Error(err)) =>
      ({...model, error: Some(IpcError.toString(err)), loading: false}, Cmd.none)

  | SelectPackage(name, version) =>
      (
        {...model, loading: true},
        OpsmCommands.getPackageInfo(name, version, result => PackageInfoLoaded(result)),
      )

  | PackageInfoLoaded(Ok(pkg)) =>
      ({...model, selectedPackage: Some(pkg), loading: false}, Cmd.none)

  | PackageInfoLoaded(Error(err)) =>
      ({...model, error: Some(IpcError.toString(err)), loading: false}, Cmd.none)

  | InstallPackage(registry, name, version) =>
      (
        {...model, installStatus: Installing, error: None},
        OpsmCommands.installPackage(registry, name, version, result => InstallComplete(result)),
      )

  | InstallComplete(Ok()) =>
      (
        {...model, installStatus: Installed},
        Cmd.batch([
          Cmd.message(Navigate(Installed)),
          OpsmCommands.listInstalled(result => InstalledLoaded(result)),
        ]),
      )

  | InstallComplete(Error(err)) =>
      (
        {
          ...model,
          installStatus: Failed(IpcError.toString(err)),
          error: Some(IpcError.toString(err)),
        },
        Cmd.none,
      )

  | LoadInstalled =>
      (
        {...model, loading: true},
        OpsmCommands.listInstalled(result => InstalledLoaded(result)),
      )

  | InstalledLoaded(Ok(packages)) =>
      ({...model, installedPackages: packages, loading: false}, Cmd.none)

  | InstalledLoaded(Error(err)) =>
      ({...model, error: Some(IpcError.toString(err)), loading: false}, Cmd.none)

  | ClearError => ({...model, error: None}, Cmd.none)
  }
}

// =============================================================================
// View helpers
// =============================================================================

let viewPackage = (pkg: OpsmCommands.package, dispatch) => {
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
    <button onClick={_ => dispatch(Navigate(PackageDetail(pkg.name, pkg.version)))}>
      {React.string("View Details")}
    </button>
    <button onClick={_ => dispatch(InstallPackage(pkg.registry, pkg.name, pkg.version))}>
      {React.string("Install")}
    </button>
  </div>
}

let viewHome = (model, dispatch) => {
  <div className="home">
    <h1> {React.string("OPSM — Odds & Sods Package Manager")} </h1>
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
          if model.searchQuery != "" { dispatch(SearchPackages(model.searchQuery)) }
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
            {Belt.Array.map(results.packages, pkg => viewPackage(pkg, dispatch))->React.array}
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
            disabled={switch model.installStatus { | Installing => true | _ => false }}
          >
            {React.string(switch model.installStatus {
            | NotStarted => "Install"
            | Installing => "Installing..."
            | Installed => "Installed"
            | Failed(_) => "Install Failed — Retry"
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
        {Belt.Array.map(model.installedPackages, pkg => viewPackage(pkg, dispatch))->React.array}
      </div>
    }}
  </div>
}

let viewSettings = (_model, _dispatch) => {
  <div className="settings-page">
    <h2> {React.string("Settings")} </h2>
    <p> {React.string("Settings page — coming soon")} </p>
  </div>
}

let viewError = (error, dispatch) => {
  <div className="error-banner">
    <p> {React.string("Error: " ++ error)} </p>
    <button onClick={_ => dispatch(ClearError)}> {React.string("Dismiss")} </button>
  </div>
}

let view = (model: model, dispatch): React.element => {
  <div className="app">
    <nav className="nav">
      <button onClick={_ => dispatch(Navigate(Home))}> {React.string("Home")} </button>
      <button onClick={_ => dispatch(Navigate(Installed))}> {React.string("Installed")} </button>
      <button onClick={_ => dispatch(Navigate(Settings))}> {React.string("Settings")} </button>
    </nav>
    {switch model.error {
    | Some(err) => viewError(err, dispatch)
    | None => React.null
    }}
    <main className="main-content">
      {switch model.currentRoute {
      | Home => viewHome(model, dispatch)
      | Search(_) => viewSearch(model, dispatch)
      | PackageDetail(_, _) => viewPackageDetail(model, dispatch)
      | Install(_, _, _) => <p> {React.string("Installing...")} </p>
      | Installed => viewInstalled(model, dispatch)
      | Settings => viewSettings(model, dispatch)
      | NotFound => <div> <h2> {React.string("404 — Page Not Found")} </h2> </div>
      }}
    </main>
  </div>
}

// =============================================================================
// Subscriptions / Init / App
// =============================================================================

let subscriptions = (_model: model): Sub.t<msg> =>
  CadreTeaRouter.Router.urlChanges(url => UrlChanged(Route.fromUrl(url)))

let init = (_flags: unit): (model, Cmd.t<msg>) => {
  let currentUrl = CadreTeaRouter.Router.getCurrentUrl()
  let initialRoute = Route.fromUrl(currentUrl)
  let model = {...initialModel, currentRoute: initialRoute}
  let cmd = switch initialRoute {
  | Installed => OpsmCommands.listInstalled(result => InstalledLoaded(result))
  | _ => Cmd.none
  }
  (model, cmd)
}

module App = MakeWithDispatch({
  type nonrec model = model
  type nonrec msg = msg
  type flags = unit
  let init = init
  let update = update
  let view = view
  let subscriptions = subscriptions
})

switch ReactDOM.querySelector("#root") {
| Some(root) => {
    let rootElement = ReactDOM.Client.createRoot(root)
    rootElement->ReactDOM.Client.Root.render(<App flags=() />)
  }
| None => Console.error("Root element not found")
}
