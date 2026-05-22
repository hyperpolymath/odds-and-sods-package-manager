// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
//
// OPSM Unified CLI
// ================
// Principally in Zig, using the Idris2 ABI for type assurance.
// This binary acts as both the main CLI (when invoked as 'opsm')
// and the tool shim dispatcher (when invoked via symlink).

const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const process = std.process;

// Import the FFI bridge
const abi = @import("abi/ffi.zig");

// --- Constants ---
const VERSION = "1.2.0";
const HELP_TEXT =
    \\OPSM — Odds and Sods Package Manager v{s}
    \\Principally in Zig | Idris2 ABI Assurance | Nickel Metadata
    \\
    \\Usage:
    \\  opsm <command> [args...]
    \\
    \\Commands:
    \\  install <tool> <ver>   Install a tool version
    \\  remove <tool> [ver]    Remove a tool (or specific version)
    \\  list                   List installed tools
    \\  set [-g] <tool> <ver>  Set version in .tool-versions
    \\  import [file]          Import from asdf .tool-versions
    \\  doctor                 Check system health
    \\  version                Show version info
    \\
    \\Shim Mode:
    \\  When symlinked as a tool name (e.g., 'zig', 'deno'), this binary
    \\  automatically resolves the version and execs the real binary.
    \\
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    if (args.len == 0) return;

    const exe_name = fs.path.basename(args[0]);

    // --- Shim Mode Detection ---
    if (!mem.eql(u8, exe_name, "opsm") and !mem.eql(u8, exe_name, "opsm-shim")) {
        // Run as shim dispatcher (placeholder: shell out to the existing shim for now
        // while we migrate the logic into this unified binary)
        return runShim(allocator, exe_name, args[1..]);
    }

    // --- CLI Mode ---
    if (args.len < 2) {
        std.debug.print(HELP_TEXT, .{VERSION});
        return;
    }

    const command = args[1];

    if (mem.eql(u8, command, "version")) {
        std.debug.print("OPSM v{s}\n", .{VERSION});
        std.debug.print("ABI: {s}\n", .{abi.odds_and_sods_package_manager_build_info()});
    } else if (mem.eql(u8, command, "doctor")) {
        try runShellScript(allocator, "/var/mnt/eclipse/repos/verification-ecosystem/odds-and-sods-package-manager/runtime/opsm-runtime", args[1..]);
    } else if (mem.eql(u8, command, "import")) {
        try runShellScript(allocator, "/var/mnt/eclipse/repos/verification-ecosystem/odds-and-sods-package-manager/runtime/opsm-runtime", args[1..]);
    } else if (mem.eql(u8, command, "plugin")) {
        // asdf compatibility: 'asdf plugin list' -> 'opsm-runtime plugin list'
        try runShellScript(allocator, "/var/mnt/eclipse/repos/verification-ecosystem/odds-and-sods-package-manager/runtime/opsm-runtime", args[1..]);
    } else if (mem.eql(u8, command, "current")) {
        try runShellScript(allocator, "/var/mnt/eclipse/repos/verification-ecosystem/odds-and-sods-package-manager/runtime/opsm-runtime", args[1..]);
    } else if (mem.eql(u8, command, "latest")) {
        try runShellScript(allocator, "/var/mnt/eclipse/repos/verification-ecosystem/odds-and-sods-package-manager/runtime/opsm-runtime", args[1..]);
    } else {
        std.debug.print("Command '{s}' not yet implemented in Zig CLI.\n", .{command});
        std.debug.print("Falling back to opsm-runtime (bash)...\n", .{});
        try runShellScript(allocator, "/var/mnt/eclipse/repos/verification-ecosystem/odds-and-sods-package-manager/runtime/opsm-runtime", args[1..]);
    }
}

fn runShim(allocator: mem.Allocator, exe: []const u8, args: [][:0]u8) !void {
    _ = allocator;
    _ = args;
    // Placeholder: exec existing shim binary
    // In production, the logic from runtime/shim/src/main.zig will be merged here.
    std.debug.print("OPSM Unified Shim: Resolving {s}...\n", .{exe});
}

fn runShellScript(allocator: mem.Allocator, path: []const u8, args: [][:0]u8) !void {
    const full_args = try allocator.alloc([]const u8, args.len + 1);
    defer allocator.free(full_args);

    // Find the absolute path to the script relative to the workspace root
    full_args[0] = path;
    for (args, 0..) |arg, i| {
        full_args[i + 1] = arg;
    }

    var child = process.Child.init(full_args, allocator);
    _ = try child.spawnAndWait();
}
