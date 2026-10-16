const std = @import("std");
const builtin = @import("builtin");
const plugin = @import("plugin.zig");
const plugin_api = @import("plugin_api");
const cpp_build_options = @import("cpp_build_options");
const cpp_rt = @import("cpp_rt.zig");

/// Returns true when the token is one of the cpp plugin's top-level commands,
/// i.e. something that should be dispatched as `cpp <command> ...`.  When the
/// caller already included the literal "cpp" marker this is false, so the
/// legacy `cpp cpp <cmd>` form keeps working verbatim.
fn isTopLevelCppCommand(token: []const u8) bool {
    const commands = [_][]const u8{
        "init", "skills", "check", "build", "build-exe", "test", "help",
    };
    for (commands) |cmd| {
        if (std.mem.eql(u8, token, cmd)) return true;
    }
    return false;
}

pub fn main(init: std.process.Init) !void {
    cpp_rt.set(init.io);
    const allocator = std.heap.page_allocator;

    var args_it: std.process.Args.Iterator = if (comptime builtin.os.tag == .windows)
        try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator)
    else
        std.process.Args.Iterator.init(init.minimal.args);
    defer args_it.deinit();

    var argv_list: std.array_list.Managed([:0]u8) = .init(allocator);
    defer {
        for (argv_list.items) |s| allocator.free(s);
        argv_list.deinit();
    }
    while (args_it.next()) |arg| {
        try argv_list.append(try allocator.dupeSentinel(u8, arg, 0));
    }
    const argv = try argv_list.toOwnedSlice();
    defer {
        for (argv) |s| allocator.free(s);
        allocator.free(argv);
    }

    var obuf: [8192]u8 = undefined;
    var ostream: std.Io.File.Writer = .init(.stdout(), init.io, &obuf);
    var ebuf: [8192]u8 = undefined;
    var estream: std.Io.File.Writer = .init(.stderr(), init.io, &ebuf);
    const stdout_writer = &ostream.interface;
    const stderr_writer = &estream.interface;

    if (argv.len >= 2 and (std.mem.eql(u8, argv[1], "--version") or std.mem.eql(u8, argv[1], "-V"))) {
        try ostream.interface.print("cpp {s}{c}", .{ cpp_build_options.version, 10 });
        try ostream.interface.flush();
        try estream.interface.flush();
        return;
    }

    // `cpp` as a global binary is invoked as `cpp <command> ...`; the plugin
    // dispatcher requires argv[1] to be the literal "cpp" marker.
    // Normalize standalone help and top-level commands to that legacy shape,
    // while preserving explicit `cpp cpp ...` invocations.
    var synthesized: ?[][]const u8 = null;
    defer if (synthesized) |s| allocator.free(s);

    const needs_help = blk: {
        if (argv.len < 2) break :blk true;
        break :blk std.mem.eql(u8, argv[1], "-h") or std.mem.eql(u8, argv[1], "--help");
    };
    const should_synthesize = blk: {
        if (needs_help) break :blk true;
        if (argv.len < 2) break :blk false;
        if (std.mem.eql(u8, argv[1], "cpp")) break :blk false;
        break :blk isTopLevelCppCommand(argv[1]);
    };
    const args: []const []const u8 = if (should_synthesize) blk: {
        const synth_len = if (needs_help) (if (argv.len > 2) argv.len + 1 else 3) else argv.len + 1;
        const synth = try allocator.alloc([]const u8, synth_len);
        synth[0] = argv[0];
        synth[1] = "cpp";
        if (needs_help) {
            synth[2] = "help";
            if (argv.len > 2) {
                for (argv[2..], 0..) |a, i| synth[i + 3] = a;
            }
        } else {
            synth[2] = argv[1];
            if (argv.len > 2) {
                for (argv[2..], 0..) |a, i| synth[i + 3] = a;
            }
        }
        synthesized = synth;
        break :blk synth;
    } else argv;

    var ctx = plugin_api.Context{
        .allocator = allocator,
    };

    const maybe_code = try plugin.runCppCommandImpl(&ctx, args, stdout_writer, stderr_writer);
    try ostream.interface.flush();
    try estream.interface.flush();
    const code = maybe_code orelse 1;
    if (code != 0) std.process.exit(code);
}
