// SPDX-License-Identifier: PMPL-1.0
// Route definitions for OPSM Mobile using cadre-router

open CadreRouter.Parser

// Route variant type
type t =
  | Home
  | Search(string)
  | PackageDetail(string, string)  // name, version
  | Install(string, string, string) // registry, name, version
  | Installed
  | Settings
  | NotFound

// Parser using cadre-router combinators
let parser = {
  oneOf([
    top->map(_ => Home),
    s("search")->andThen(str)->map(((_, q)) => Search(q)),
    s("package")->andThen(str)->andThen(str)
      ->map((((_, name), version)) => PackageDetail(name, version)),
    s("install")->andThen(str)->andThen(str)->andThen(str)
      ->map(((((_, reg), name), ver)) => Install(reg, name, ver)),
    s("installed")->map(_ => Installed),
    s("settings")->map(_ => Settings),
  ])
}

// Serialize route to URL string
let toString = (route: t): string => {
  switch route {
  | Home => "/"
  | Search(q) => "/search/" ++ q
  | PackageDetail(name, ver) => "/package/" ++ name ++ "/" ++ ver
  | Install(reg, name, ver) => "/install/" ++ reg ++ "/" ++ name ++ "/" ++ ver
  | Installed => "/installed"
  | Settings => "/settings"
  | NotFound => "/404"
  }
}

// Parse URL to route (with fallback to NotFound)
let fromUrl = (url: string): t => {
  switch CadreRouter.Parser.parse(parser, url) {
  | Some(route) => route
  | None => NotFound
  }
}
