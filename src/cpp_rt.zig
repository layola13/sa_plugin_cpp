const std = @import("std");
const builtin = @import("builtin");

/// Process-wide default `std.Io` for plugin library code.
///
/// Same role as `sla_rt.zig` in sa_plugin_sla@0.17: Zig 0.17 removed ambient
/// filesystem access, so library code uses this instead of threading `Io`
/// through the whole C++ call graph:
/// * standalone entry points (`cpp`, test drivers) call `set(init.io)` once
///   at startup (zero cost: std already built one);
/// * the `.so` plugin entry never calls `set`; the first `get()` lazily
///   creates a process-lifetime `Threaded` Io.
var current: ?std.Io = null;
var threaded_storage: ?std.Io.Threaded = null;

pub fn set(io: std.Io) void {
    current = io;
}

pub fn get() std.Io {
    if (current) |io| return io;
    threaded_storage = std.Io.Threaded.init(std.heap.page_allocator, .{ .argv0 = .empty });
    const io = threaded_storage.?.io();
    current = io;
    return io;
}

/// Owned environment-variable lookup for library code that has no
/// `std.process.Init` in scope (0.17 removed `std.process.getEnvVarOwned`).
pub fn getEnvOwned(gpa: std.mem.Allocator, key: []const u8) ?[]u8 {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return null;
    if (builtin.link_libc == false) return null;
    var i: usize = 0;
    while (std.c.environ[i]) |entry| : (i += 1) {
        const pair = std.mem.span(entry);
        if (pair.len <= key.len) continue;
        if (!std.mem.eql(u8, pair[0..key.len], key)) continue;
        if (pair[key.len] != '=') continue;
        return gpa.dupe(u8, pair[key.len + 1 ..]) catch null;
    }
    return null;
}

/// Adapts any duck-typed writer (`writeAll`, e.g. a host-stream sink) to a
/// `*std.Io.Writer`. Same shape as `sio.ForwardWriter` (sci@0.17
/// `src/sa_io.zig`), inlined here so this repo stays self-contained.
pub fn ForwardWriter(comptime W: type) type {
    return struct {
        const Self = @This();

        io_writer: std.Io.Writer,
        wrapped: W,
        storage: [8192]u8 = std.mem.zeroes([8192]u8),

        const vtable: std.Io.Writer.VTable = .{ .drain = drain };

        pub fn init(wrapped: W) Self {
            return Self{
                .io_writer = .{ .buffer = &.{}, .end = 0, .vtable = &vtable },
                .wrapped = wrapped,
                .storage = std.mem.zeroes([8192]u8),
            };
        }

        pub fn writer(self: *Self) *std.Io.Writer {
            self.io_writer.buffer = &self.storage;
            if (self.io_writer.end > self.storage.len) self.io_writer.end = 0;
            return &self.io_writer;
        }

        fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
            const self: *Self = @fieldParentPtr("io_writer", w);
            if (w.end != 0) {
                self.wrapped.writeAll(w.buffer[0..w.end]) catch return error.WriteFailed;
                w.end = 0;
            }
            var total: usize = 0;
            for (data, 0..) |slice, i| {
                const reps: usize = if (i == data.len - 1) splat else 1;
                var r: usize = 0;
                while (r < reps) : (r += 1) {
                    self.wrapped.writeAll(slice) catch return error.WriteFailed;
                    total += slice.len;
                }
            }
            return total;
        }
    };
}

/// Snapshot the LIVE process environment into a map (works from the
/// `.so` plugin context too, where the ambient Io may carry an empty
/// environ). Used for spawning host tools with a working PATH.
pub fn liveEnvMap(gpa: std.mem.Allocator) !std.process.Environ.Map {
    var map = std.process.Environ.Map.init(gpa);
    errdefer map.deinit();
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return map;
    if (builtin.link_libc == false) return map;
    var i: usize = 0;
    while (std.c.environ[i]) |entry| : (i += 1) {
        const pair = std.mem.span(entry);
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        map.put(pair[0..eq], pair[eq + 1 ..]) catch continue;
    }
    return map;
}

/// Run a host tool (e.g. `sa`) with inherited stdio; returns its exit code.
/// `argv[0]` is resolved against the live process PATH.
pub fn runHost(gpa: std.mem.Allocator, argv: []const []const u8) u8 {
    const io = get();
    var env = liveEnvMap(gpa) catch return 1;
    defer env.deinit();
    var child = std.process.spawn(io, .{ .argv = argv, .environ_map = &env }) catch return 1;
    const term = child.wait(io) catch return 1;
    return switch (term) {
        .exited => |c| c,
        else => 1,
    };
}

/// Read an entire file (cwd-relative or absolute) into an owned slice.
pub fn readFileAlloc(gpa: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    const io = get();
    if (std.fs.path.isAbsolute(path)) {
        var file = try std.Io.Dir.openFileAbsolute(io, path, .{});
        defer file.close(io);
        var rbuf: [8192]u8 = undefined;
        var r = file.reader(io, &rbuf);
        return try r.interface.allocRemaining(gpa, .limited(max_bytes));
    }
    var dir = std.Io.Dir.cwd();
    var file = try dir.openFile(io, path, .{});
    defer file.close(io);
    var rbuf: [8192]u8 = undefined;
    var r = file.reader(io, &rbuf);
    return try r.interface.allocRemaining(gpa, .limited(max_bytes));
}

/// Write bytes to a file, creating or truncating it.
pub fn writeFile(path: []const u8, bytes: []const u8) !void {
    const io = get();
    var dir = std.Io.Dir.cwd();
    var file = try dir.createFile(io, path, .{});
    defer file.close(io);
    var wbuf: [8192]u8 = undefined;
    var w = file.writer(io, &wbuf);
    try w.interface.writeAll(bytes);
    try w.interface.flush();
}
