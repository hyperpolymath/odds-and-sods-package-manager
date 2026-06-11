// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// OPSM Unified CLI — Build Configuration

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main CLI (unified binary)
    const exe = b.addExecutable(.{
        .name = "opsm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/opsm.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.linkLibC();
    b.installArtifact(exe);

    // FFI Bridge as a shared library (for Idris2 to call)
    const ffi = b.addLibrary(.{
        .name = "odds_and_sods_package_manager",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/abi/ffi.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    ffi.linkLibC();
    b.installArtifact(ffi);
}
