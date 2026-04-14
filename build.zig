const std = @import("std");
const tarea_step = @import("src/step.zig");

pub const DebtConfig = tarea_step.DebtConfig;

pub fn build(b: *std.Build) void {
    const mod_name = "tarea";

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create options module with sensible defaults
    const opts = b.addOptions();
    opts.addOption(bool, "allow_todo_in_release", false);
    opts.addOption(bool, "allow_fixme_in_release", false);
    opts.addOption(bool, "allow_custom_in_release", false);

    // Create the main module with options embedded
    const lib_mod = b.addModule(mod_name, .{
        .root_source_file = b.path("src/lib/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib_mod.addOptions("tarea_options", opts);

    // Documentation step
    const docs_step = b.step("docs", "Generate the documentation");

    const docs_lib = b.addLibrary(.{
        .name = mod_name,
        .root_module = lib_mod,
    });

    const docs = b.addInstallDirectory(.{
        .source_dir = docs_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    docs_step.dependOn(&docs.step);

    const tests_step = b.step("tests", "Run the test suite");

    const unit_tests = b.addTest(.{
        .name = "Unit Tests",
        .root_module = lib_mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    tests_step.dependOn(&run_unit_tests.step);

    const integration_tests = b.addTest(.{
        .name = "Integration Tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/suite.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = mod_name,
                    .module = lib_mod,
                },
            },
        }),
    });

    const run_integration_tests = b.addRunArtifact(integration_tests);
    tests_step.dependOn(&run_integration_tests.step);
}

/// Add a build step that scans for tarea markers, reports debt, and enforces budget.
pub fn addDebtStep(b: *std.Build, config: DebtConfig) *std.Build.Step {
    return tarea_step.addDebtStep(b, config);
}
