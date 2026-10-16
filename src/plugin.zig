const std = @import("std");
const plugin_api = @import("plugin_api");
const cpp_rt = @import("cpp_rt.zig");
const plugin_skills = @import("plugin_skills.zig");
const plugin_commands = @import("plugin_commands.zig");

pub const runCppCommandImpl = plugin_commands.runCppCommandImpl;

const HostStreamSink = struct {
    stream: plugin_api.HostStream,

    pub fn writeAll(self: HostStreamSink, bytes: []const u8) !void {
        const wa = self.stream.write_all orelse return error.WriteFailed;
        if (wa(self.stream.ctx, bytes.ptr, bytes.len) != @intFromEnum(plugin_api.AbiStatus.ok)) return error.WriteFailed;
    }
};

fn runCppCommandAbi(
    ctx: *const plugin_api.Context,
    argv: [*]const [*:0]const u8,
    argv_len: usize,
    stdout: plugin_api.HostStream,
    stderr: plugin_api.HostStream,
    out_code: *u8,
) callconv(.c) u32 {
    out_code.* = 0;
    const allocator = std.heap.page_allocator;
    var local_ctx = ctx.*;
    local_ctx.allocator = allocator;

    const args = allocator.alloc([]const u8, argv_len) catch return @intFromEnum(plugin_api.AbiStatus.failed);
    defer allocator.free(args);
    for (0..argv_len) |i| {
        args[i] = std.mem.span(argv[i]);
    }

    var out_fw = cpp_rt.ForwardWriter(HostStreamSink).init(.{ .stream = stdout });
    var err_fw = cpp_rt.ForwardWriter(HostStreamSink).init(.{ .stream = stderr });
    const stdout_writer = out_fw.writer();
    const stderr_writer = err_fw.writer();

    const result = runCppCommandImpl(&local_ctx, args, stdout_writer, stderr_writer) catch {
        stdout_writer.flush() catch {};
        stderr_writer.flush() catch {};
        return @intFromEnum(plugin_api.AbiStatus.failed);
    };
    stdout_writer.flush() catch {};
    stderr_writer.flush() catch {};
    if (result) |code| {
        out_code.* = code;
        return @intFromEnum(plugin_api.AbiStatus.ok);
    }
    return @intFromEnum(plugin_api.AbiStatus.unknown_command);
}

const descriptor = plugin_api.PluginDescriptor{
    .abi_version = plugin_api.abi_version,
    .descriptor_size = @as(u32, @intCast(@sizeOf(plugin_api.PluginDescriptor))),
    .name = "cpp",
    .init = null,
    .prebuild = null,
    .postbuild = null,
    .handle_command = runCppCommandAbi,
    .skills_ptr = plugin_skills.skills[0..].ptr,
    .skills_len = plugin_skills.skills.len,
};

pub export const saasm_plugin_descriptor_v1: plugin_api.PluginDescriptor = descriptor;
pub export fn saasm_plugin_descriptor_v1_fn(out: *plugin_api.PluginDescriptor) callconv(.c) void {
    out.* = descriptor;
}

test {
    _ = @import("lexer.zig");
    _ = @import("parser.zig");
    _ = @import("codegen.zig");
    _ = @import("plugin_compile.zig");
}
