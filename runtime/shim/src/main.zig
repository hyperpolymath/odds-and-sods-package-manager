// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// OPSM Shim Dispatcher
// ====================
// Universal shim binary for OPSM runtime version management.
//
// Every tool managed by OPSM has a symlink in ~/.opsm/shims/ pointing
// to this single binary. When invoked, it:
//
//   1. Reads argv[0] to determine the tool name (e.g., "zig", "deno")
//   2. Walks up the directory tree looking for .tool-versions
//   3. Falls back to ~/.opsm/tool-versions (global)
//   4. Resolves the real binary path: ~/.opsm/runtimes/<tool>/<version>/...
//   5. exec's the real binary with the original arguments
//
// Design goals:
//   - <1ms overhead (no interpreter startup, no shell, no network)
//   - Single static binary (~40KB)
//   - Compatible with asdf's .tool-versions format
//   - Zero allocations on the hot path (stack buffers only)
//
// This replaces asdf's bash shims which add 50-200ms per invocation.

const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const os = std.os;
const posix = std.posix;
const exe_map = @import("exe_map.zig");

/// Maximum path length we support (matches Linux PATH_MAX).
const MAX_PATH: usize = 4096;

/// Maximum line length in .tool-versions files.
const MAX_LINE: usize = 512;

/// Maximum version string length.
const MAX_VERSION: usize = 128;

/// OPSM directories (overridable via environment).
const ENV_RUNTIME_DIR = "OPSM_RUNTIME_DIR";
const ENV_SHIM_DIR = "OPSM_SHIM_DIR";
const ENV_CONFIG_DIR = "OPSM_CONFIG_DIR";

/// Default paths (relative to HOME).
const DEFAULT_RUNTIME_SUBDIR = ".opsm/runtimes";
const DEFAULT_CONFIG_SUBDIR = ".opsm";
const TOOL_VERSIONS_FILE = ".tool-versions";

// -----------------------------------------------------------------------
// Version resolution
// -----------------------------------------------------------------------

/// Result of version resolution.
const Resolution = struct {
    /// The resolved version string (points into version_buf).
    version: []const u8,
    /// Source file that provided this version.
    source: []const u8,
};

/// Resolve the version for a given tool by walking up the directory tree.
///
/// Precedence (same as asdf):
///   1. .tool-versions in current directory, walking up to /
///   2. ~/.opsm/tool-versions (global default)
///   3. Legacy files (.nvmrc, .ruby-version, etc.) — future
fn resolveVersion(
    tool_name: []const u8,
    version_buf: *[MAX_VERSION]u8,
    source_buf: *[MAX_PATH]u8,
) ?Resolution {
    // Get current working directory.
    var cwd_buf: [MAX_PATH]u8 = undefined;
    const cwd = posix.getcwd(&cwd_buf) catch return null;

    // Walk up directory tree looking for .tool-versions.
    var dir_buf: [MAX_PATH]u8 = undefined;
    @memcpy(dir_buf[0..cwd.len], cwd);
    var dir_len: usize = cwd.len;

    while (true) {
        // Try .tool-versions in this directory.
        if (tryToolVersionsFile(
            dir_buf[0..dir_len],
            tool_name,
            version_buf,
            source_buf,
        )) |res| {
            return res;
        }

        // Move to parent directory.
        if (dir_len == 1 and dir_buf[0] == '/') break; // reached root
        // Find last '/' and truncate.
        var i: usize = dir_len;
        while (i > 0) : (i -= 1) {
            if (dir_buf[i - 1] == '/') {
                dir_len = if (i == 1) 1 else i - 1;
                break;
            }
        }
        if (i == 0) break;
    }

    // Fallback: global tool-versions.
    const home = std.posix.getenv("HOME") orelse return null;
    var global_dir_buf: [MAX_PATH]u8 = undefined;
    const config_dir = std.posix.getenv(ENV_CONFIG_DIR) orelse blk: {
        // Build default path: $HOME/.opsm
        const len = home.len + 1 + DEFAULT_CONFIG_SUBDIR.len;
        if (len >= MAX_PATH) break :blk home;
        @memcpy(global_dir_buf[0..home.len], home);
        global_dir_buf[home.len] = '/';
        @memcpy(global_dir_buf[home.len + 1 ..][0..DEFAULT_CONFIG_SUBDIR.len], DEFAULT_CONFIG_SUBDIR);
        break :blk global_dir_buf[0..len];
    };

    // Try both .tool-versions (asdf compat) and tool-versions (OPSM native) in config dir.
    return tryToolVersionsFile(config_dir, tool_name, version_buf, source_buf) orelse
        tryToolVersionsFileNamed(config_dir, "tool-versions", tool_name, version_buf, source_buf);
}

/// Try to read a version for the given tool from a .tool-versions file
/// in the specified directory.
fn tryToolVersionsFile(
    dir: []const u8,
    tool_name: []const u8,
    version_buf: *[MAX_VERSION]u8,
    source_buf: *[MAX_PATH]u8,
) ?Resolution {
    return tryToolVersionsFileNamed(dir, TOOL_VERSIONS_FILE, tool_name, version_buf, source_buf);
}

/// Try to read a version for the given tool from a named file in a directory.
fn tryToolVersionsFileNamed(
    dir: []const u8,
    filename: []const u8,
    tool_name: []const u8,
    version_buf: *[MAX_VERSION]u8,
    source_buf: *[MAX_PATH]u8,
) ?Resolution {
    // Build path: dir/<filename>
    var path_buf: [MAX_PATH]u8 = undefined;
    const tv_name = filename;
    const path_len = dir.len + 1 + tv_name.len;
    if (path_len >= MAX_PATH) return null;

    @memcpy(path_buf[0..dir.len], dir);
    path_buf[dir.len] = '/';
    @memcpy(path_buf[dir.len + 1 ..][0..tv_name.len], tv_name);
    path_buf[path_len] = 0;

    // Open and read the whole file (these are tiny — typically <1KB).
    const file = fs.openFileAbsoluteZ(@ptrCast(&path_buf), .{}) catch return null;
    defer file.close();

    var file_buf: [8192]u8 = undefined;
    const bytes_read = file.readAll(&file_buf) catch return null;
    const contents = file_buf[0..bytes_read];

    // Parse line by line.
    var line_start: usize = 0;
    while (line_start < contents.len) {
        // Find end of line.
        var line_end = line_start;
        while (line_end < contents.len and contents[line_end] != '\n') : (line_end += 1) {}
        const line = contents[line_start..line_end];
        line_start = line_end + 1;

        const trimmed = mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Parse: <tool> <version> [extra...]
        var it = mem.tokenizeAny(u8, trimmed, &std.ascii.whitespace);
        const parsed_tool = it.next() orelse continue;
        const parsed_version = it.next() orelse continue;

        if (mem.eql(u8, parsed_tool, tool_name)) {
            if (parsed_version.len >= MAX_VERSION) return null;
            @memcpy(version_buf[0..parsed_version.len], parsed_version);
            @memcpy(source_buf[0..path_len], path_buf[0..path_len]);
            return Resolution{
                .version = version_buf[0..parsed_version.len],
                .source = source_buf[0..path_len],
            };
        }
    }

    return null;
}

// -----------------------------------------------------------------------
// Binary resolution
// -----------------------------------------------------------------------

/// Find the real binary for a tool at a given version.
/// Searches: <runtime_dir>/<tool>/<version>/bin/<exe>
///           <runtime_dir>/<tool>/<version>/<exe>
fn findRealBinary(
    tool_name: []const u8,
    version: []const u8,
    exe_name: []const u8,
    out_buf: *[MAX_PATH]u8,
) ?[]const u8 {
    const home = std.posix.getenv("HOME") orelse return null;
    const runtime_dir = std.posix.getenv(ENV_RUNTIME_DIR) orelse blk: {
        var buf: [MAX_PATH]u8 = undefined;
        const subdir = DEFAULT_RUNTIME_SUBDIR;
        const len = home.len + 1 + subdir.len;
        if (len >= MAX_PATH) break :blk null;
        @memcpy(buf[0..home.len], home);
        buf[home.len] = '/';
        @memcpy(buf[home.len + 1 ..][0..subdir.len], subdir);
        break :blk buf[0..len];
    } orelse return null;

    // Try common binary locations in order of likelihood:
    //   <tool>/<version>/bin/<exe>         (go, node, etc.)
    //   <tool>/<version>/<exe>             (just, gleam, etc.)
    //   <tool>/<version>/<tool>-sdk/bin/<exe>  (dart-sdk/bin/dart)
    //   <tool>/<version>/<tool>/bin/<exe>  (some tools nest)
    const candidates = [_][]const u8{ "bin", "", "sdk/bin", "dart-sdk/bin" };
    for (candidates) |subdir| {
        var path_buf: [MAX_PATH]u8 = undefined;
        var pos: usize = 0;

        inline for (.{runtime_dir}) |seg| {
            if (pos + seg.len >= MAX_PATH) return null;
            @memcpy(path_buf[pos..][0..seg.len], seg);
            pos += seg.len;
        }

        // /<tool>/<version>
        for ([_][]const u8{ tool_name, version }) |seg| {
            if (pos + 1 + seg.len >= MAX_PATH) return null;
            path_buf[pos] = '/';
            pos += 1;
            @memcpy(path_buf[pos..][0..seg.len], seg);
            pos += seg.len;
        }

        // /bin or nothing
        if (subdir.len > 0) {
            if (pos + 1 + subdir.len >= MAX_PATH) return null;
            path_buf[pos] = '/';
            pos += 1;
            @memcpy(path_buf[pos..][0..subdir.len], subdir);
            pos += subdir.len;
        }

        // /<exe>
        if (pos + 1 + exe_name.len >= MAX_PATH) return null;
        path_buf[pos] = '/';
        pos += 1;
        @memcpy(path_buf[pos..][0..exe_name.len], exe_name);
        pos += exe_name.len;
        path_buf[pos] = 0;

        // Check if it exists and is executable.
        const stat = fs.cwd().statFile(path_buf[0..pos]) catch continue;
        _ = stat;
        @memcpy(out_buf[0..pos], path_buf[0..pos]);
        out_buf[pos] = 0;
        return out_buf[0..pos];
    }

    return null;
}

// -----------------------------------------------------------------------
// Entry point
// -----------------------------------------------------------------------

/// Write a message to stderr (no allocations, no formatting).
fn writeErr(msg: []const u8) void {
    _ = posix.write(2, msg) catch {};
}

pub fn main() void {
    // 1. Determine tool name from argv[0] (basename of the symlink).
    const args = std.os.argv;
    if (args.len == 0) {
        writeErr("opsm-shim: no argv[0]\n");
        std.process.exit(1);
    }

    const argv0: []const u8 = mem.span(args[0]);
    const exe_name = fs.path.basename(argv0);

    // If invoked as "opsm-shim" directly, show help.
    if (mem.eql(u8, exe_name, "opsm-shim")) {
        writeErr("OPSM Shim Dispatcher v0.1.0\n\n");
        writeErr("This binary is not meant to be called directly.\n");
        writeErr("It should be symlinked from ~/.opsm/shims/<tool-name>.\n\n");
        writeErr("Each symlink resolves the tool version from .tool-versions\n");
        writeErr("(walking up the directory tree) and exec's the real binary.\n\n");
        writeErr("Setup:\n");
        writeErr("  ln -s ~/.opsm/shims/opsm-shim ~/.opsm/shims/zig\n");
        writeErr("  ln -s ~/.opsm/shims/opsm-shim ~/.opsm/shims/deno\n\n");
        writeErr("Environment:\n");
        writeErr("  OPSM_RUNTIME_DIR  Where runtimes are installed (default: ~/.opsm/runtimes)\n");
        writeErr("  OPSM_CONFIG_DIR   Where global config lives   (default: ~/.opsm)\n");
        std.process.exit(0);
    }

    // 2. Map executable name to tool name (e.g., "erlc" → "erlang").
    const tool_name = exe_map.resolve(exe_name);

    // 3. Resolve version from .tool-versions using the tool name.
    var version_buf: [MAX_VERSION]u8 = undefined;
    var source_buf: [MAX_PATH]u8 = undefined;

    const resolution = resolveVersion(tool_name, &version_buf, &source_buf) orelse {
        writeErr("opsm-shim: no version set for '");
        writeErr(tool_name);
        writeErr("'");
        if (!mem.eql(u8, exe_name, tool_name)) {
            writeErr(" (via ");
            writeErr(exe_name);
            writeErr(")");
        }
        writeErr("\n  Set a version with: echo '");
        writeErr(tool_name);
        writeErr(" <version>' >> .tool-versions\n  Or globally: echo '");
        writeErr(tool_name);
        writeErr(" <version>' >> ~/.opsm/tool-versions\n");
        std.process.exit(1);
    };

    // 4. Find the real binary (search under the tool's install dir for the exe name).
    var real_path_buf: [MAX_PATH]u8 = undefined;
    const real_path = findRealBinary(
        tool_name,
        resolution.version,
        exe_name,
        &real_path_buf,
    ) orelse {
        writeErr("opsm-shim: ");
        writeErr(tool_name);
        writeErr(" ");
        writeErr(resolution.version);
        writeErr(" is not installed\n  Install with: opsm runtime install ");
        writeErr(tool_name);
        writeErr(" ");
        writeErr(resolution.version);
        writeErr("\n  (version from: ");
        writeErr(resolution.source);
        writeErr(")\n");
        std.process.exit(1);
    };

    // 4. Exec the real binary.
    // Build null-terminated argv for execve.
    var exec_args: [256]?[*:0]const u8 = .{null} ** 256;
    const real_path_z: [*:0]const u8 = @ptrCast(real_path_buf[0 .. real_path.len + 1]);
    exec_args[0] = real_path_z;

    var i: usize = 1;
    while (i < args.len and i < 255) : (i += 1) {
        exec_args[i] = args[i];
    }
    exec_args[i] = null;

    const argv_ptr: [*:null]const ?[*:0]const u8 = @ptrCast(&exec_args);
    const env = std.c.environ;
    _ = std.posix.execvpeZ(real_path_z, argv_ptr, env) catch {};

    // If we get here, exec failed.
    writeErr("opsm-shim: exec failed for ");
    writeErr(real_path);
    writeErr("\n");
    std.process.exit(126);
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "basename extraction" {
    const result = fs.path.basename("/home/user/.opsm/shims/zig");
    try std.testing.expectEqualStrings("zig", result);
}

test "basename extraction bare" {
    const result = fs.path.basename("deno");
    try std.testing.expectEqualStrings("deno", result);
}
