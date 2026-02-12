// SPDX-License-Identifier: PMPL-1.0
@@warning("-44-45")
open Types

// =============================================================================
// Deno FFI Bindings
// =============================================================================

module Deno = {
  @val @scope("Deno") external args: array<string> = "args"
  @val @scope("Deno") external exit: int => unit = "exit"
}

// =============================================================================
// CLI Help
// =============================================================================

let printHelp = () => {
  Console.log("opsm - Odds-and-sods Package Manager")
  Console.log("")
  Console.log("USAGE:")
  Console.log("  opsm <command> [options]")
  Console.log("")
  Console.log("COMMANDS:")
  Console.log("  publish <path>    Publish a package through the trust pipeline")
  Console.log("  audit <package>   Audit a package for sustainability and compliance")
  Console.log("  status            Show service status and configuration")
  Console.log("  help              Show this help message")
  Console.log("")
  Console.log("CONFIGURATION:")
  Console.log("  Config file search order:")
  Console.log("  1. $OPSM_CONFIG environment variable")
  Console.log("  2. ./opsm.toml (local directory)")
  Console.log("  3. ~/.config/opsm/opsm.toml (user config)")
  Console.log("")
  Console.log("EXAMPLES:")
  Console.log("  opsm publish ./my-package")
  Console.log("  opsm audit @scope/package")
  Console.log("  opsm status")
}

let printVersion = () => {
  Console.log("opsm 0.1.0")
}

// =============================================================================
// Command Parsing
// =============================================================================

type command =
  | Publish(string)
  | Audit(string)
  | Status
  | Help
  | Version
  | Unknown(string)

let parseArgs = (args: array<string>): command => {
  switch args->Array.get(0) {
  | None => Help
  | Some("help") | Some("-h") | Some("--help") => Help
  | Some("version") | Some("-v") | Some("--version") => Version
  | Some("publish") =>
    switch args->Array.get(1) {
    | Some(path) => Publish(path)
    | None => {
        Console.error("Error: publish requires a path argument")
        Help
      }
    }
  | Some("audit") =>
    switch args->Array.get(1) {
    | Some(pkg) => Audit(pkg)
    | None => {
        Console.error("Error: audit requires a package argument")
        Help
      }
    }
  | Some("status") => Status
  | Some(cmd) => Unknown(cmd)
  }
}

// =============================================================================
// Main Entry Point
// =============================================================================

let main = async () => {
  let args = Deno.args
  let command = parseArgs(args)

  switch command {
  | Help => {
      printHelp()
      Deno.exit(0)
    }
  | Version => {
      printVersion()
      Deno.exit(0)
    }
  | Unknown(cmd) => {
      Console.error(`Unknown command: ${cmd}`)
      Console.error("Run 'opsm help' for usage information")
      Deno.exit(1)
    }
  | Publish(path) => {
      let config = await Config.loadConfigOrExample()
      switch await Wiring.runPublish(config, path) {
      | Ok(_) => Deno.exit(0)
      | Error(e) => {
          Console.error(`Publish failed: ${e}`)
          Deno.exit(1)
        }
      }
    }
  | Audit(pkg) => {
      let config = await Config.loadConfigOrExample()
      switch await Wiring.runAudit(config, pkg) {
      | Ok(_) => Deno.exit(0)
      | Error(e) => {
          Console.error(`Audit failed: ${e}`)
          Deno.exit(1)
        }
      }
    }
  | Status => {
      let config = await Config.loadConfigOrExample()
      switch await Wiring.runStatus(config) {
      | Ok(_) => Deno.exit(0)
      | Error(e) => {
          Console.error(`Status check failed: ${e}`)
          Deno.exit(1)
        }
      }
    }
  }
}

// Run main
let _ = main()
