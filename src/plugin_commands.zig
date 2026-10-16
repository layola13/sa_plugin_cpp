const std = @import("std");
const plugin_api = @import("plugin_api");
const build_options = @import("cpp_build_options");
const compile = @import("plugin_compile.zig");
const skills = @import("plugin_skills.zig");
const cpp_rt = @import("cpp_rt.zig");

const help_text =
    \\usage: cpp <command> [options]
    \\       sa cpp <command> [options]
    \\
    \\Commands:
    \\  init       [path]
    \\  skills     [--json]
    \\  check      [file]
    \\  build      [file] [--out <file.sa>]
    \\  build-exe  [file] [-o <exe>]  (delegates to host `sa build-exe`)
    \\  test       [file]             (delegates to host `sa test`)
    \\
    \\Options:
    \\  --out <file>   Write the emitted SA text here (default: <stem>.sa)
    \\  -o <exe>       Native output for build-exe
    \\  --json         Emit JSON where supported
    \\  -h, --help     Show this help message
    \\
;

pub fn runCppCommandImpl(ctx: *const plugin_api.Context, args: []const []const u8, stdout: *std.Io.Writer, stderr: *std.Io.Writer) anyerror!?u8 {
    const gpa = ctx.allocator;
    if (args.len < 2) {
        try stdout.writeAll(help_text);
        try stdout.flush();
        return 0;
    }
    // Accept both `cpp <cmd>` (local binary) and `sa cpp <cmd>` (host dispatch).
    var cmd_at: usize = 1;
    if (std.mem.eql(u8, args[1], "cpp")) {
        if (args.len < 3) {
            try stdout.writeAll(help_text);
            try stdout.flush();
            return 0;
        }
        cmd_at = 2;
    }
    const cmd = args[cmd_at];
    const rest = args[cmd_at + 1 ..];
    if (std.mem.eql(u8, cmd, "-h") or std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "help")) {
        try stdout.writeAll(help_text);
        try stdout.flush();
        return 0;
    }
    if (std.mem.eql(u8, cmd, "--version") or std.mem.eql(u8, cmd, "-V")) {
        try stdout.print("cpp {s}\n", .{build_options.version});
        try stdout.flush();
        return 0;
    }
    if (std.mem.eql(u8, cmd, "skills")) {
        const as_json = hasFlag(rest, "--json");
        if (as_json) {
            try skills.writeSkillsJson(stdout);
        } else {
            try skills.writeSkillsText(stdout);
        }
        return 0;
    }
    if (std.mem.eql(u8, cmd, "init")) {
        return try cmdInit(gpa, rest, stdout, stderr);
    }
    if (std.mem.eql(u8, cmd, "check")) {
        return try cmdCheck(gpa, rest, stdout, stderr);
    }
    if (std.mem.eql(u8, cmd, "build")) {
        return try cmdBuild(gpa, rest, stdout, stderr);
    }
    if (std.mem.eql(u8, cmd, "build-exe")) {
        return try cmdBuildExe(gpa, rest, stdout, stderr);
    }
    if (std.mem.eql(u8, cmd, "test")) {
        return try cmdTest(gpa, rest, stdout, stderr);
    }
    try stderr.print("cpp: unknown command '{s}'\n", .{cmd});
    try stderr.flush();
    return null;
}

fn hasFlag(args: []const []const u8, flag: []const u8) bool {
    for (args) |a| {
        if (std.mem.eql(u8, a, flag)) return true;
    }
    return false;
}

fn flagValue(args: []const []const u8, flag: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], flag) and i + 1 < args.len) return args[i + 1];
    }
    return null;
}

fn positional(args: []const []const u8) ?[]const u8 {
    for (args) |a| {
        if (a.len == 0) continue;
        if (a[0] == '-') continue;
        return a;
    }
    return null;
}

fn writeDiag(gpa: std.mem.Allocator, stderr: *std.Io.Writer, path: []const u8, diag: *compile.Diag, err: compile.CompileError) !void {
    // Re-read the source for a line number (best effort; fall back to raw msg).
    const source = cpp_rt.readFileAlloc(gpa, path, compile.max_source_bytes) catch {
        try stderr.print("cpp: {s}: {s}\n", .{ path, diag.msg });
        try stderr.flush();
        return;
    };
    defer gpa.free(source);
    const text = try compile.describeFailure(gpa, source, diag, err);
    defer gpa.free(text);
    try stderr.print("cpp: {s}: {s}\n", .{ path, text });
    try stderr.flush();
}

fn cmdInit(gpa: std.mem.Allocator, args: []const []const u8, stdout: *std.Io.Writer, stderr: *std.Io.Writer) !?u8 {
    const dest = positional(args) orelse ".";
    const mod_path = try std.fmt.allocPrint(gpa, "{s}/cpp.mod", .{dest});
    defer gpa.free(mod_path);
    const src_path = try std.fmt.allocPrint(gpa, "{s}/src/main.cpp", .{dest});
    defer gpa.free(src_path);
    // Refuse to overwrite.
    if (cpp_rt.readFileAlloc(gpa, mod_path, 1024)) |old| {
        gpa.free(old);
        try stderr.print("cpp: '{s}' already exists, refusing to overwrite\n", .{mod_path});
        try stderr.flush();
        return 1;
    } else |_| {}
    const mod_content =
        \\[package]
        \\name = "app"
        \\version = "0.1.0"
        \\
    ;
    const main_content =
        \\#include <iostream>
        \\
        \\int add(int a, int b) {
        \\    return a + b;
        \\}
        \\
        \\int main() {
        \\    int x = add(40, 2);
        \\    std::cout << x << std::endl;
        \\    return 0;
        \\}
        \\
    ;
    cpp_rt.writeFile(mod_path, mod_content) catch {
        try stderr.print("cpp: cannot write '{s}' (create '{s}/src' first?)\n", .{ mod_path, dest });
        try stderr.flush();
        return 1;
    };
    cpp_rt.writeFile(src_path, main_content) catch {
        try stderr.print("cpp: cannot write '{s}' (create '{s}/src' first?)\n", .{ src_path, dest });
        try stderr.flush();
        return 1;
    };
    try stdout.print("cpp: initialized '{s}'\n", .{dest});
    try stdout.flush();
    return 0;
}

fn cmdCheck(gpa: std.mem.Allocator, args: []const []const u8, stdout: *std.Io.Writer, stderr: *std.Io.Writer) !?u8 {
    const path = positional(args) orelse {
        try stderr.writeAll("cpp: check needs a file\n");
        try stderr.flush();
        return 1;
    };
    var diag = compile.Diag.init(gpa);
    defer diag.deinit();
    compile.checkFile(gpa, path, &diag) catch |err| {
        try writeDiag(gpa, stderr, path, &diag, err);
        return 1;
    };
    try stdout.print("{s}: ok\n", .{path});
    try stdout.flush();
    return 0;
}

fn defaultSaOut(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    if (std.mem.endsWith(u8, path, ".cpp")) {
        return try std.fmt.allocPrint(gpa, "{s}.sa", .{path[0 .. path.len - 4]});
    }
    return try std.fmt.allocPrint(gpa, "{s}.sa", .{path});
}

fn cmdBuild(gpa: std.mem.Allocator, args: []const []const u8, stdout: *std.Io.Writer, stderr: *std.Io.Writer) !?u8 {
    const path = positional(args) orelse {
        try stderr.writeAll("cpp: build needs a file\n");
        try stderr.flush();
        return 1;
    };
    const out_override = flagValue(args, "--out");
    var diag = compile.Diag.init(gpa);
    defer diag.deinit();
    const sa = compile.buildFileToString(gpa, path, &diag) catch |err| {
        try writeDiag(gpa, stderr, path, &diag, err);
        return 1;
    };
    defer gpa.free(sa);
    if (out_override) |o| {
        cpp_rt.writeFile(o, sa) catch {
            try stderr.print("cpp: cannot write '{s}'\n", .{o});
            try stderr.flush();
            return 1;
        };
        try stdout.print("cpp: wrote '{s}'\n", .{o});
        try stdout.flush();
        return 0;
    }
    const def = try defaultSaOut(gpa, path);
    defer gpa.free(def);
    cpp_rt.writeFile(def, sa) catch {
        try stderr.print("cpp: cannot write '{s}'\n", .{def});
        try stderr.flush();
        return 1;
    };
    try stdout.print("cpp: wrote '{s}'\n", .{def});
    try stdout.flush();
    return 0;
}



fn cmdBuildExe(gpa: std.mem.Allocator, args: []const []const u8, stdout: *std.Io.Writer, stderr: *std.Io.Writer) !?u8 {
    const path = positional(args) orelse {
        try stderr.writeAll("cpp: build-exe needs a file\n");
        try stderr.flush();
        return 1;
    };
    const exe_out = flagValue(args, "-o") orelse "a.out";
    var diag = compile.Diag.init(gpa);
    defer diag.deinit();
    const sa = compile.buildFileToString(gpa, path, &diag) catch |err| {
        try writeDiag(gpa, stderr, path, &diag, err);
        return 1;
    };
    defer gpa.free(sa);
    const sa_path = try defaultSaOut(gpa, path);
    defer gpa.free(sa_path);
    cpp_rt.writeFile(sa_path, sa) catch {
        try stderr.print("cpp: cannot write '{s}'\n", .{sa_path});
        try stderr.flush();
        return 1;
    };
    const code = cpp_rt.runHost(gpa, &.{ "sa", "build-exe", sa_path, "-o", exe_out });
    if (code != 0) {
        try stderr.print("cpp: host `sa build-exe` failed (code {d}); SA kept at '{s}'\n", .{ code, sa_path });
        try stderr.flush();
        return code;
    }
    try stdout.print("cpp: built '{s}'\n", .{exe_out});
    try stdout.flush();
    return 0;
}

fn cmdTest(gpa: std.mem.Allocator, args: []const []const u8, stdout: *std.Io.Writer, stderr: *std.Io.Writer) !?u8 {
    const path = positional(args) orelse {
        try stderr.writeAll("cpp: test needs a file\n");
        try stderr.flush();
        return 1;
    };
    var diag = compile.Diag.init(gpa);
    defer diag.deinit();
    const sa = compile.buildFileToString(gpa, path, &diag) catch |err| {
        try writeDiag(gpa, stderr, path, &diag, err);
        return 1;
    };
    defer gpa.free(sa);
    const sa_path = try defaultSaOut(gpa, path);
    defer gpa.free(sa_path);
    cpp_rt.writeFile(sa_path, sa) catch {
        try stderr.print("cpp: cannot write '{s}'\n", .{sa_path});
        try stderr.flush();
        return 1;
    };
    const code = cpp_rt.runHost(gpa, &.{ "sa", "test", sa_path });
    if (code != 0) {
        try stderr.print("cpp: host `sa test` failed (code {d}); SA kept at '{s}'\n", .{ code, sa_path });
        try stderr.flush();
        return code;
    }
    try stdout.print("cpp: tests passed for '{s}'\n", .{path});
    try stdout.flush();
    return 0;
}
