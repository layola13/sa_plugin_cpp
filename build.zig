const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // NOTE(Zig 0.17): the old b.sysroot / b.libc_file overrides no longer
    // exist (same as sa_plugin_sla@0.17 and sci@0.17). Cross-compile via
    // -Dtarget plus explicit flags instead.
    const cpp_version = b.option([]const u8, "version", "C++ plugin semantic version.") orelse "0.1.0";
    const optimize = b.standardOptimizeOption(.{});
    const test_filter = b.option([]const u8, "test-filter", "Only run Zig tests whose name contains this filter.");

    const plugin_api = b.createModule(.{
        .root_source_file = b.path("src/plugin_api.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cpp_build_options = b.addOptions();
    cpp_build_options.addOption([]const u8, "version", cpp_version);

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/plugin.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    root_module.addImport("plugin_api", plugin_api);
    root_module.addOptions("cpp_build_options", cpp_build_options);

    const lib = b.addLibrary(.{
        .name = "cpp",
        .root_module = root_module,
        .linkage = .dynamic,
    });
    b.installArtifact(lib);

    const cli_module = b.createModule(.{
        .root_source_file = b.path("src/local_cli.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    cli_module.addImport("plugin_api", plugin_api);
    cli_module.addOptions("cpp_build_options", cpp_build_options);
    const cli = b.addExecutable(.{
        .name = "cpp",
        .root_module = cli_module,
    });
    b.installArtifact(cli);
    const run_cli = b.addRunArtifact(cli);
    // NOTE(Zig 0.17): b.args forwarding was removed (same as sla@0.17);
    // run the installed `cpp` binary directly with arguments instead.
    const run_step = b.step("local-cli", "Run the local cpp CLI driver");
    run_step.dependOn(&run_cli.step);

    const install_sap = b.addInstallFile(b.path("sap.json"), "lib/sap.json");
    b.getInstallStep().dependOn(&install_sap.step);

    const unit_tests = b.addTest(.{
        .root_module = root_module,
        // NOTE(Zig 0.17): TestOptions.filter became filters: []const []const u8.
        .filters = if (test_filter) |f| &.{f} else &.{},
    });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
