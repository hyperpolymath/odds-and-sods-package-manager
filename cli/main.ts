#!/usr/bin/env -S deno run --allow-read --allow-env --allow-net
// SPDX-License-Identifier: PMPL-1.0

import { parseArgs } from "@std/cli";
import * as wiring from "./wiring.ts";

const HELP = `opm - Odds-and-sods package manager

USAGE:
  opm <command> [options]

COMMANDS:
  publish <path>     Publish a package through the trust pipeline
  audit <package>    Audit a package for security and sustainability
  status             Show federation and registry status
  help               Show this help message

EXAMPLES:
  opm publish ./my-package
  opm audit @scope/package-name
  opm status

CONFIG:
  Configuration is loaded from (in order):
    1. $OPM_CONFIG environment variable
    2. ./opm.toml (current directory)
    3. ~/.config/opm/opm.toml (user config)
`;

async function main(): Promise<void> {
  const args = parseArgs(Deno.args, {
    boolean: ["help", "version"],
    alias: { h: "help", v: "version" },
  });

  if (args.help || args._.length === 0) {
    console.log(HELP);
    Deno.exit(0);
  }

  if (args.version) {
    console.log("opm 0.1.0");
    Deno.exit(0);
  }

  const command = String(args._[0]);

  switch (command) {
    case "publish": {
      const path = args._[1];
      if (!path) {
        console.error("Error: publish requires a path argument");
        console.error("Usage: opm publish <path>");
        Deno.exit(1);
      }
      try {
        await wiring.publish(String(path));
      } catch (err) {
        console.error(`Error: ${err instanceof Error ? err.message : err}`);
        Deno.exit(1);
      }
      break;
    }

    case "audit": {
      const packageName = args._[1];
      if (!packageName) {
        console.error("Error: audit requires a package argument");
        console.error("Usage: opm audit <package>");
        Deno.exit(1);
      }
      try {
        await wiring.audit(String(packageName));
      } catch (err) {
        console.error(`Error: ${err instanceof Error ? err.message : err}`);
        Deno.exit(1);
      }
      break;
    }

    case "status":
      wiring.status();
      break;

    case "help":
      console.log(HELP);
      break;

    default:
      console.error(`Unknown command: ${command}`);
      console.error("Run 'opm help' for usage information");
      Deno.exit(1);
  }
}

if (import.meta.main) {
  main();
}
