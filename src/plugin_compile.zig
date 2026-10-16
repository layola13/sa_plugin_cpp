const std = @import("std");
const lex = @import("lexer.zig");
const par = @import("parser.zig");
const cg = @import("codegen.zig");
const cpp_rt = @import("cpp_rt.zig");

pub const CompileError = lex.CompileError;
pub const Diag = lex.Diag;

pub const max_source_bytes: usize = 1 << 26;

/// Compile C++ source text to SA text on `out`. Diagnostics go to `diag`.
/// All frontend scratch memory lives in a throwaway arena; only the bytes
/// written to `out` (owned by the caller) and the exported `diag` message
/// survive this call.
pub fn compileSource(gpa: std.mem.Allocator, source: []const u8, out: *std.Io.Writer, diag: *Diag) CompileError!void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const agpa = arena.allocator();
    var adiag = lex.Diag.init(agpa);
    defer {
        if (adiag.msg.len != 0) {
            if (diag.msg.len != 0) gpa.free(diag.msg);
            diag.msg = gpa.dupe(u8, adiag.msg) catch &.{};
            diag.off = adiag.off;
        }
    }
    var lx = lex.Lexer.init(source);
    const toks = try lx.tokenize(agpa, &adiag);
    var parser = par.Parser.create(agpa, source, toks, &adiag);
    defer parser.deinit();
    try parser.parseUnit();
    var abuf: std.Io.Writer.Allocating = .init(gpa);
    defer abuf.deinit();
    var gen = cg.Codegen.init(agpa, &parser, &adiag, &abuf.writer);
    defer gen.deinit();
    try gen.compile();
    if (gen.need_print) try writeAll(out, "@import \"sa_std/io/print.sai\"\n");
    if (gen.need_fmt) try writeAll(out, "@import \"sa_std/fmt.sai\"\n");
    if (gen.str_consts.items.len != 0) try writeAll(out, "@import \"sa_std/string.sai\"\n");
    for (gen.str_consts.items) |sc| {
        (out.print("@const str_{d} = utf8:\"", .{sc.id}) catch return error.CodegenError);
        try writeSaEscaped(out, sc.bytes);
        try writeAll(out, "\"\n");
    }
    try writeAll(out, abuf.written());
    try flushOut(out);
}

/// Compile a `.cpp` file to SA text on `out`.
pub fn compileFile(gpa: std.mem.Allocator, path: []const u8, out: *std.Io.Writer, diag: *Diag) CompileError!void {
    const source = cpp_rt.readFileAlloc(gpa, path, max_source_bytes) catch {
        failDiag(gpa, diag, 0, "cannot read file '{s}'", .{path});
        return error.IoError;
    };
    defer gpa.free(source);
    try compileSource(gpa, source, out, diag);
}

/// Check a file (compile and discard the output).
pub fn checkFile(gpa: std.mem.Allocator, path: []const u8, diag: *Diag) CompileError!void {
    var abuf: std.Io.Writer.Allocating = .init(gpa);
    defer abuf.deinit();
    const out: *std.Io.Writer = &abuf.writer;
    try compileFile(gpa, path, out, diag);
}

/// Compile a file and return the SA text (caller owns).
pub fn buildFileToString(gpa: std.mem.Allocator, path: []const u8, diag: *Diag) CompileError![]u8 {
    var abuf: std.Io.Writer.Allocating = .init(gpa);
    errdefer abuf.deinit();
    const out: *std.Io.Writer = &abuf.writer;
    try compileFile(gpa, path, out, diag);
    const bytes = try gpa.dupe(u8, abuf.written());
    abuf.deinit();
    return bytes;
}

fn writeAll(out: *std.Io.Writer, bytes: []const u8) CompileError!void {
    out.writeAll(bytes) catch return error.CodegenError;
}

fn flushOut(out: *std.Io.Writer) CompileError!void {
    out.flush() catch return error.CodegenError;
}

fn failDiag(gpa: std.mem.Allocator, diag: *Diag, off: usize, comptime fmt: []const u8, args: anytype) void {
    if (diag.msg.len != 0) gpa.free(diag.msg);
    diag.msg = std.fmt.allocPrint(gpa, fmt, args) catch &.{};
    diag.off = off;
}

fn writeSaEscaped(out: *std.Io.Writer, bytes: []const u8) CompileError!void {
    for (bytes) |c| {
        switch (c) {
            '\\' => writeAll(out, "\\\\") catch return error.CodegenError,
            '"' => writeAll(out, "\\\"") catch return error.CodegenError,
            '\n' => writeAll(out, "\\n") catch return error.CodegenError,
            '\r' => writeAll(out, "\\r") catch return error.CodegenError,
            '\t' => writeAll(out, "\\t") catch return error.CodegenError,
            else => out.writeAll(&.{c}) catch return error.CodegenError,
        }
    }
}

/// One-line human rendering of a compile failure.
pub fn describeFailure(gpa: std.mem.Allocator, source: []const u8, diag: *const Diag, err: CompileError) CompileError![]u8 {
    const stage: []const u8 = switch (err) {
        error.LexError => "lex",
        error.ParseError => "parse",
        error.TypeError, error.CodegenError => "lower",
        error.IoError => "io",
        error.OutOfMemory => "oom",
    };
    const line = Diag.lineOf(source, diag.off);
    return try std.fmt.allocPrint(gpa, "{s} error at line {d}: {s}", .{ stage, line, diag.msg });
}

test "end-to-end hello emits @main" {
    const gpa = std.testing.allocator;
    const src =
        \\int add(int a, int b) { return a + b; }
        \\int main() { int x = add(1, 2); std::cout << x << std::endl; return 0; }
    ;
    var diag = Diag.init(gpa);
    defer diag.deinit();
    var abuf: std.Io.Writer.Allocating = .init(gpa);
    defer abuf.deinit();
    try compileSource(gpa, src, &abuf.writer, &diag);
    const sa = abuf.written();
    try std.testing.expect(std.mem.indexOf(u8, sa, "@main() -> i32:") != null);
    try std.testing.expect(std.mem.indexOf(u8, sa, "@add(a: i32, b: i32) -> i32:") != null);
    try std.testing.expect(std.mem.indexOf(u8, sa, "sa_print_bytes") != null);
}
