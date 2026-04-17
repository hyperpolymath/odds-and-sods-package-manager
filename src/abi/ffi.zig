// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
//
// OPSM Idris2 ABI — Zig FFI Implementation
// =========================================
// This module implements the C-compatible FFI declared in src/abi/Foreign.idr.
// All functions are exported with the "odds_and_sods_package_manager_" prefix
// to match the Idris2 %foreign declarations.

const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const process = std.process;

// --- Types (must match src/abi/Types.idr) ---

pub const Result = enum(u32) {
    ok = 0,
    @"error" = 1,
    invalid_param = 2,
    out_of_memory = 3,
    null_pointer = 4,
};

/// Opaque library handle.
pub const Handle = struct {
    allocator: std.mem.Allocator,
    config_dir: []const u8,
    runtime_dir: []const u8,
    shim_dir: []const u8,
    last_error: ?[]const u8 = null,
};

// --- Global state ---

var global_allocator = std.heap.c_allocator;

// --- FFI Implementations ---

/// Initialize the OPSM library state.
/// Returns a pointer to a Handle (u64 in Idris).
pub export fn odds_and_sods_package_manager_init() ?*Handle {
    const handle = global_allocator.create(Handle) catch return null;

    // Resolve paths from environment or defaults
    const home = process.getEnvVarOwned(global_allocator, "HOME") catch "/tmp";
    const config_dir = std.fmt.allocPrint(global_allocator, "{s}/.opsm", .{home}) catch ".opsm";
    const runtime_dir = std.fmt.allocPrint(global_allocator, "{s}/runtimes", .{config_dir}) catch ".opsm/runtimes";
    const shim_dir = std.fmt.allocPrint(global_allocator, "{s}/shims", .{config_dir}) catch ".opsm/shims";

    handle.* = .{
        .allocator = global_allocator,
        .config_dir = config_dir,
        .runtime_dir = runtime_dir,
        .shim_dir = shim_dir,
        .last_error = null,
    };

    return handle;
}

/// Free the library handle.
pub export fn odds_and_sods_package_manager_free(handle: ?*Handle) void {
    const h = handle orelse return;
    const allocator = h.allocator;

    allocator.free(h.config_dir);
    allocator.free(h.runtime_dir);
    allocator.free(h.shim_dir);
    if (h.last_error) |err| allocator.free(err);

    allocator.destroy(h);
}

/// Check if library is initialized.
pub export fn odds_and_sods_package_manager_is_initialized(handle: ?*Handle) u32 {
    return if (handle != null) 1 else 0;
}

/// Process data (entry point for commands).
pub export fn odds_and_sods_package_manager_process(handle: ?*Handle, input: u32) u32 {
    const h = handle orelse return 0;
    _ = h;
    _ = input;
    // Placeholder for command dispatch
    return 1; // Ok
}

/// Get string result from library.
/// Returns a C string that must be freed with odds_and_sods_package_manager_free_string.
pub export fn odds_and_sods_package_manager_get_string(handle: ?*Handle) ?[*:0]const u8 {
    const h = handle orelse return null;
    _ = h;
    return null;
}

/// Free a C string returned by the library.
pub export fn odds_and_sods_package_manager_free_string(str: ?[*:0]const u8) void {
    const s = str orelse return;
    global_allocator.free(mem.span(s));
}

/// Process array data.
pub export fn odds_and_sods_package_manager_process_array(handle: ?*Handle, buffer: ?[*]const u8, len: u32) u32 {
    const h = handle orelse return 1; // Error
    _ = h;
    _ = buffer;
    _ = len;
    return 0; // Ok
}

/// Get last error message.
pub export fn odds_and_sods_package_manager_last_error() ?[*:0]const u8 {
    // For now, no thread-local storage of last error, just return null or static
    return null;
}

/// Get library version.
pub export fn odds_and_sods_package_manager_version() [*:0]const u8 {
    return "1.2.0";
}

/// Get build information.
pub export fn odds_and_sods_package_manager_build_info() [*:0]const u8 {
    return "OPSM Unified Zig/Idris2 ABI v1.2.0";
}

/// Register a callback (C ABI).
pub export fn odds_and_sods_package_manager_register_callback(handle: ?*Handle, callback: ?*const anyopaque) u32 {
    const h = handle orelse return 1; // Error
    _ = h;
    _ = callback;
    return 0; // Ok
}
