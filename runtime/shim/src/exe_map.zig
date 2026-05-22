// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Exe-to-Tool Name Mapping
// ========================
// Maps executable names to their parent tool name for cases where
// the binary name differs from the .tool-versions entry.
//
// Most tools (zig, deno, just, nickel, etc.) have executables matching
// their tool name. This table covers the exceptions.
//
// Generated from runtime/core/*.ncl plugin definitions.
// Update when adding plugins with mismatched exe/tool names.

const std = @import("std");

/// Static mapping of executable name → tool name.
/// Only entries where they differ are listed.
const exe_to_tool = [_]struct { exe: []const u8, tool: []const u8 }{
    // arangodb
    .{ .exe = "arangosh", .tool = "arangodb" },
    // bebop
    .{ .exe = "bebopc", .tool = "bebop" },
    // erlang (multiple executables)
    .{ .exe = "erl", .tool = "erlang" },
    .{ .exe = "erlc", .tool = "erlang" },
    .{ .exe = "rebar3", .tool = "erlang" },
    .{ .exe = "escript", .tool = "erlang" },
    // fortran
    .{ .exe = "gfortran", .tool = "fortran" },
    // rekor
    .{ .exe = "rekor-cli", .tool = "rekor" },
    // surrealdb
    .{ .exe = "surreal", .tool = "surrealdb" },
    // golang
    .{ .exe = "go", .tool = "golang" },
    .{ .exe = "gofmt", .tool = "golang" },
    // nodejs (asdf compat)
    .{ .exe = "node", .tool = "nodejs" },
    .{ .exe = "npm", .tool = "nodejs" },
    .{ .exe = "npx", .tool = "nodejs" },
    // haskell
    .{ .exe = "ghc", .tool = "haskell" },
    .{ .exe = "ghci", .tool = "haskell" },
    .{ .exe = "cabal", .tool = "haskell" },
    .{ .exe = "stack", .tool = "haskell" },
    // ocaml
    .{ .exe = "ocaml", .tool = "ocaml" },
    .{ .exe = "ocamlopt", .tool = "ocaml" },
    .{ .exe = "opam", .tool = "ocaml" },
    // ruby
    .{ .exe = "ruby", .tool = "ruby" },
    .{ .exe = "gem", .tool = "ruby" },
    .{ .exe = "bundle", .tool = "ruby" },
    .{ .exe = "irb", .tool = "ruby" },
};

/// Look up the tool name for an executable.
/// Returns the tool name if found in the mapping, otherwise returns
/// the exe_name itself (most tools match).
pub fn resolve(exe_name: []const u8) []const u8 {
    for (exe_to_tool) |entry| {
        if (std.mem.eql(u8, entry.exe, exe_name)) {
            return entry.tool;
        }
    }
    return exe_name;
}
