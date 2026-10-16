const std = @import("std");
const lex = @import("lexer.zig");
const par = @import("parser.zig");

pub const CompileError = lex.CompileError;
pub const Diag = lex.Diag;

// ---------------------------------------------------------------------------
// Resolved value kinds (SA-level).
// ---------------------------------------------------------------------------

const VKind = enum {
    i32,
    i64,
    f64,
    boolean,
    ptr,
    slice, // fat const-char pointer: 16B {ptr,len} behind a ptr register
    none, // void

    fn saName(self: VKind) []const u8 {
        return switch (self) {
            .i32, .boolean => "i32",
            .i64 => "i64",
            .f64 => "f64",
            .ptr, .slice => "ptr",
            .none => "void",
        };
    }

    fn isInt(self: VKind) bool {
        return self == .i32 or self == .i64 or self == .boolean;
    }

    fn isScalar(self: VKind) bool {
        return self == .i32 or self == .i64 or self == .f64 or self == .boolean;
    }
};

/// Resolved type: scalar/pointer kind plus struct identity for aggregates.
const RType = struct {
    kind: VKind = .i32,
    sid: ?usize = null, // struct index when kind == .ptr and it is a struct
    elem_kind: VKind = .i32, // pointee kind when kind == .ptr
    elem_sid: ?usize = null,
};

const Val = struct {
    txt: []const u8,
    kind: VKind,
    owned: bool, // temp holds an owned (alloc/call) value needing release/transfer
    is_temp: bool,
    sid: ?usize = null,
};

const Binding = struct {
    name: []const u8,
    kind: VKind,
    sid: ?usize = null,
    elem_kind: VKind = .i32,
    elem_sid: ?usize = null,
    arr_len: ?usize = null,
    owned: bool,
    depth: usize,
};

const Temp = struct {
    name: []const u8,
    owned: bool,
    live: bool,
    depth: usize,
};

const LoopCtx = struct {
    cont_label: ?[]const u8, // null for switch
    break_label: []const u8,
    depth: usize,
};

const LField = struct {
    name: []const u8,
    kind: VKind,
};

const Layout = struct {
    name: []const u8,
    fields: []LField,
    offsets: []usize,
    size: usize,
};

const FuncRef = struct {
    full: []const u8,
    ret_kind: VKind,
    ret_sid: ?usize,
    params: []RType,
    is_method: bool,
    is_static: bool,
    sid: ?usize, // struct index for `this`
};

const StrConst = struct {
    bytes: []const u8,
    id: usize,
};

fn primSize(kind: VKind) usize {
    return switch (kind) {
        .i32, .boolean => 4,
        .i64, .f64, .ptr, .slice => 8,
        .none => 0,
    };
}

// ---------------------------------------------------------------------------
// Codegen
// ---------------------------------------------------------------------------

pub const Codegen = struct {
    gpa: std.mem.Allocator,
    p: *par.Parser,
    diag: *Diag,
    out: *std.Io.Writer,
    tmp_n: usize = 0,
    lbl_n: usize = 0,
    layouts: std.array_list.Managed(Layout),
    funcrefs: std.array_list.Managed(FuncRef),
    str_consts: std.array_list.Managed(StrConst),
    need_print: bool = false,
    need_fmt: bool = false,
    // Per-function state:
    bindings: std.array_list.Managed(Binding),
    temps: std.array_list.Managed(Temp),
    loops: std.array_list.Managed(LoopCtx),
    depth: usize = 0,
    terminated: bool = false,
    ret_kind: VKind = .none,
    ret_sid: ?usize = null,
    cur_qual: []const u8 = "",
    cur_sid: ?usize = null, // struct index when inside a method
    is_main: bool = false,

    pub fn init(gpa: std.mem.Allocator, parser: *par.Parser, diag: *Diag, out: *std.Io.Writer) Codegen {
        return .{
            .gpa = gpa,
            .p = parser,
            .diag = diag,
            .out = out,
            .layouts = .init(gpa),
            .funcrefs = .init(gpa),
            .str_consts = .init(gpa),
            .bindings = .init(gpa),
            .temps = .init(gpa),
            .loops = .init(gpa),
        };
    }

    pub fn deinit(self: *Codegen) void {
        self.layouts.deinit();
        self.funcrefs.deinit();
        self.str_consts.deinit();
        self.bindings.deinit();
        self.temps.deinit();
        self.loops.deinit();
    }

    fn err(self: *Codegen, off: usize, comptime fmt: []const u8, args: anytype) CompileError {
        self.diag.fail(off, fmt, args);
        return error.CodegenError;
    }

    fn emit(self: *Codegen, comptime fmt: []const u8, args: anytype) CompileError!void {
        self.out.print("  " ++ fmt ++ "\n", args) catch return error.CodegenError;
    }

    fn emitLabel(self: *Codegen, name: []const u8) CompileError!void {
        self.out.print("{s}:\n", .{name}) catch return error.CodegenError;
    }

    fn newTemp(self: *Codegen) CompileError![]const u8 {
        const n = try std.fmt.allocPrint(self.gpa, "cpp_t_{d}", .{self.tmp_n});
        self.tmp_n += 1;
        return n;
    }

    fn newHidden(self: *Codegen, what: []const u8) CompileError![]const u8 {
        const n = try std.fmt.allocPrint(self.gpa, "cpp_{s}_{d}", .{ what, self.tmp_n });
        self.tmp_n += 1;
        return n;
    }

    fn newLabel(self: *Codegen, what: []const u8) CompileError![]const u8 {
        const n = try std.fmt.allocPrint(self.gpa, "L_cpp_{s}_{d}", .{ what, self.lbl_n });
        self.lbl_n += 1;
        return n;
    }

    fn checkUserName(self: *Codegen, name: []const u8, off: usize) CompileError!void {
        if (std.mem.startsWith(u8, name, "cpp_")) {
            return self.err(off, "identifier '{s}' is reserved (cpp_ prefix is used by the lowering)", .{name});
        }
    }

    // -- types ---------------------------------------------------------------

    fn resolveType(self: *Codegen, ty: par.CType, off: usize) CompileError!RType {
        if (ty.prim == .auto_) {
            return self.err(off, "'auto' needs an initializer to infer from", .{});
        }
        if (ty.prim == .void_) {
            if (ty.ptr > 0) return .{ .kind = .ptr, .elem_kind = .i32 };
            return .{ .kind = .none };
        }
        if (ty.ptr > 0) {
            // `char*` / `const char*` are fat string slices in v0.1 lowering.
            if (ty.ptr == 1 and ty.prim == .char8) {
                return .{ .kind = .slice };
            }
            // Pointer: record pointee for deref/index.
            var elem_kind: VKind = .i32;
            var elem_sid: ?usize = null;
            if (ty.ptr == 1) {
                switch (ty.prim) {
                    .i32 => elem_kind = .i32,
                    .i64 => elem_kind = .i64,
                    .f64 => elem_kind = .f64,
                    .boolean => elem_kind = .boolean,
                    .char8 => elem_kind = .i32,
                    .named => {
                        const si = self.findStruct(ty.name) orelse {
                            return self.err(off, "unknown type '{s}'", .{ty.name});
                        };
                        elem_kind = .ptr;
                        elem_sid = si;
                    },
                    else => elem_kind = .i32,
                }
            }
            return .{ .kind = .ptr, .elem_kind = elem_kind, .elem_sid = elem_sid };
        }
        switch (ty.prim) {
            .i32 => return .{ .kind = .i32 },
            .i64 => return .{ .kind = .i64 },
            .f64 => return .{ .kind = .f64 },
            .boolean => return .{ .kind = .boolean },
            .char8 => return .{ .kind = .i32 },
            .named => {
                if (self.findStruct(ty.name)) |si| {
                    return .{ .kind = .ptr, .sid = si };
                }
                // Enum types lower to plain i32.
                for (self.p.enums.items) |e| {
                    if (std.mem.eql(u8, e.name, ty.name)) return .{ .kind = .i32 };
                    const q = std.fmt.allocPrint(self.gpa, "{s}{s}", .{ e.qual, e.name }) catch continue;
                    defer self.gpa.free(q);
                    if (std.mem.eql(u8, q, ty.name)) {
                        // Owned by the arena in real pipelines; freed at return.
                        return .{ .kind = .i32 };
                    }
                }
                return self.err(off, "unknown type '{s}'", .{ty.name});
            },
            else => return self.err(off, "unsupported type", .{}),
        }
    }

    fn findStruct(self: *Codegen, name: []const u8) ?usize {
        // Match simple or qualified (qual+name) struct names.
        for (self.p.structs.items, 0..) |s, i| {
            if (std.mem.eql(u8, s.name, name)) return i;
            const q = std.fmt.allocPrint(self.gpa, "{s}{s}", .{ s.qual, s.name }) catch continue;
            const match = std.mem.eql(u8, q, name);
            self.gpa.free(q);
            if (match) return i;
        }
        return null;
    }

    fn computeLayouts(self: *Codegen) CompileError!void {
        for (self.p.structs.items) |*s| {
            var fields: std.array_list.Managed(LField) = .init(self.gpa);
            defer fields.deinit();
            var offsets: std.array_list.Managed(usize) = .init(self.gpa);
            defer offsets.deinit();
            var off: usize = 0;
            for (s.fields) |f| {
                const rt = try self.resolveType(f.ty, s.off);
                if (rt.kind == .none) {
                    return self.err(s.off, "struct '{s}' has void field '{s}'", .{ s.name, f.name });
                }
                if (rt.kind == .ptr and rt.sid != null) {
                    return self.err(s.off, "nested structs are not supported in v0.1 (field '{s}')", .{f.name});
                }
                const sz = primSize(rt.kind);
                const align_to = @min(sz, @as(usize, 8));
                if (off % align_to != 0) off += align_to - (off % align_to);
                try fields.append(.{ .name = f.name, .kind = rt.kind });
                try offsets.append(off);
                off += sz;
            }
            try self.layouts.append(.{
                .name = s.name,
                .fields = try fields.toOwnedSlice(),
                .offsets = try offsets.toOwnedSlice(),
                .size = off,
            });
        }
    }

    fn indexFuncs(self: *Codegen) CompileError!void {
        for (self.p.funcs.items) |*f| {
            if (f.is_dtor) continue;
            const full = try std.fmt.allocPrint(self.gpa, "{s}{s}", .{ f.qual, f.name });
            for (self.funcrefs.items) |r| {
                if (std.mem.eql(u8, r.full, full)) {
                    return self.err(f.off, "duplicate function '{s}'", .{full});
                }
            }
            var params: std.array_list.Managed(RType) = .init(self.gpa);
            defer params.deinit();
            for (f.params) |pm| {
                try params.append(try self.resolveType(pm.ty, f.off));
            }
            var ret_sid: ?usize = null;
            const ret_kind: VKind = blk: {
                if (f.ret.isVoid()) break :blk .none;
                const rt = try self.resolveType(f.ret, f.off);
                ret_sid = rt.sid;
                break :blk rt.kind;
            };
            var sid: ?usize = null;
            if (f.is_ctor or f.is_dtor) {
                // Ctors/dtors carry the class in their name ("Box_ctor").
                const base = if (std.mem.endsWith(u8, f.name, "_ctor")) f.name[0 .. f.name.len - 5] else if (std.mem.endsWith(u8, f.name, "_dtor")) f.name[0 .. f.name.len - 5] else f.name;
                sid = self.findStruct(base);
            } else if (f.is_method and !f.is_static) {
                // `this` struct: qual is like "Point_" or "N_Point_".
                const q = f.qual;
                const stripped = if (std.mem.endsWith(u8, q, "_")) q[0 .. q.len - 1] else q;
                // Last component after qual prefix.
                if (std.mem.lastIndexOfScalar(u8, stripped, '_')) |li| {
                    sid = self.findStruct(stripped[li + 1 ..]);
                } else {
                    sid = self.findStruct(stripped);
                }
            }
            try self.funcrefs.append(.{
                .full = full,
                .ret_kind = ret_kind,
                .ret_sid = ret_sid,
                .params = try params.toOwnedSlice(),
                .is_method = f.is_method,
                .is_static = f.is_static,
                .sid = sid,
            });
        }
    }

    fn findFunc(self: *Codegen, name: []const u8) ?*FuncRef {
        for (self.funcrefs.items) |*r| {
            if (std.mem.eql(u8, r.full, name)) return r;
        }
        // Try current qualifier prefix.
        if (self.cur_qual.len != 0) {
            const q = std.fmt.allocPrint(self.gpa, "{s}{s}", .{ self.cur_qual, name }) catch return null;
            defer self.gpa.free(q);
            for (self.funcrefs.items) |*r| {
                if (std.mem.eql(u8, r.full, q)) return r;
            }
        }
        return null;
    }

    // -- entry -----------------------------------------------------------------

    pub fn compile(self: *Codegen) CompileError!void {
        try self.computeLayouts();
        try self.indexFuncs();
        for (self.p.funcs.items) |*f| {
            if (f.is_dtor) continue;
            try self.genFunc(f);
        }
        // Header: imports + string consts, then the buffered body.
        // (Body is emitted directly to out; header first: two-phase via buffer.)
    }

    // -- helpers ---------------------------------------------------------------

    fn lookup(self: *Codegen, name: []const u8) ?*Binding {
        var i = self.bindings.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.bindings.items[i].name, name)) return &self.bindings.items[i];
        }
        return null;
    }

    fn addBinding(self: *Codegen, name: []const u8, kind: VKind, sid: ?usize, owned: bool) CompileError!*Binding {
        try self.bindings.append(.{
            .name = name,
            .kind = kind,
            .sid = sid,
            .owned = owned,
            .depth = self.depth,
        });
        return &self.bindings.items[self.bindings.items.len - 1];
    }

    fn addTemp(self: *Codegen, name: []const u8, owned: bool) CompileError!void {
        try self.temps.append(.{ .name = name, .owned = owned, .live = true, .depth = self.depth });
    }

    fn killVal(self: *Codegen, v: Val) CompileError!void {
        if (!v.is_temp or !v.owned) return;
        for (self.temps.items) |*t| {
            if (t.live and std.mem.eql(u8, t.name, v.txt)) {
                t.live = false;
                try self.emit("!{s}", .{v.txt});
                return;
            }
        }
    }

    /// Release all live owned bindings/temps with depth > mark, in reverse.
    fn releaseAbove(self: *Codegen, mark: usize) CompileError!void {
        // Interleave by reverse creation order across both lists is ideal;
        // reverse-each is sound (all uses precede this point).
        var i = self.temps.items.len;
        while (i > 0) {
            i -= 1;
            const t = &self.temps.items[i];
            if (t.live and t.owned and t.depth > mark) {
                t.live = false;
                try self.emit("!{s}", .{t.name});
            }
        }
        var j = self.bindings.items.len;
        while (j > mark) {
            j -= 1;
            const b = &self.bindings.items[j];
            if (b.owned and b.depth > mark) {
                b.owned = false;
                try self.emit("!{s}", .{b.name});
            }
        }
    }

    fn popTo(self: *Codegen, mark: usize) void {
        while (self.bindings.items.len > mark) {
            _ = self.bindings.pop();
        }
        while (self.temps.items.len > 0 and self.temps.items[self.temps.items.len - 1].depth > mark) {
            _ = self.temps.pop();
        }
        // Temps created at shallower depths stay; deeper ones are all dead now.
        for (self.temps.items) |*t| {
            if (t.depth > mark) t.live = false;
        }
    }

    fn releaseAll(self: *Codegen, except_temp: ?[]const u8) CompileError!void {
        var i = self.temps.items.len;
        while (i > 0) {
            i -= 1;
            const t = &self.temps.items[i];
            if (t.live and t.owned) {
                if (except_temp) |e| {
                    if (std.mem.eql(u8, t.name, e)) continue;
                }
                t.live = false;
                try self.emit("!{s}", .{t.name});
            }
        }
        var j = self.bindings.items.len;
        while (j > 0) {
            j -= 1;
            const b = &self.bindings.items[j];
            if (b.owned) {
                b.owned = false;
                try self.emit("!{s}", .{b.name});
            }
        }
    }

    // -- functions ---------------------------------------------------------------

    fn genFunc(self: *Codegen, f: *par.Func) CompileError!void {
        const ref = self.findFuncExact(f) orelse return self.err(f.off, "internal: function not indexed", .{});
        self.bindings.clearRetainingCapacity();
        self.temps.clearRetainingCapacity();
        self.loops.clearRetainingCapacity();
        self.depth = 0;
        self.terminated = false;
        self.cur_qual = f.qual;
        self.cur_sid = ref.sid;
        self.is_main = std.mem.eql(u8, f.name, "main") and f.qual.len == 0 and !f.is_method;

        if (self.is_main and f.params.len != 0) {
            return self.err(f.off, "main with parameters is not supported in v0.1", .{});
        }
        if (f.is_ctor) {
            // Ctors are emitted as @Qual_Name_ctor(this: ptr): void-style.
            // Only reachable via `Type x;` lowering.
        }

        // Header.
        const fname: []const u8 = if (self.is_main) "main" else ref.full;
        // Build param list text.
        var plist: std.array_list.Managed(u8) = .init(self.gpa);
        defer plist.deinit();
        {
            var aw: std.Io.Writer.Allocating = .init(self.gpa);
            defer aw.deinit();
            const pw: *std.Io.Writer = &aw.writer;
            var first = true;
            if (ref.is_method and !ref.is_static) {
                (pw.print("this: ptr", .{})) catch return error.CodegenError;
                first = false;
            }
            for (f.params, 0..) |pm, i| {
                const rt = ref.params[i];
                if (!first) (pw.writeAll(", ")) catch return error.CodegenError;
                first = false;
                try self.checkUserName(pm.name, f.off);
                (pw.print("{s}: {s}", .{ pm.name, rt.kind.saName() })) catch return error.CodegenError;
            }
            try plist.appendSlice(aw.written());
        }
        const ret_ann: []const u8 = blk: {
            if (self.is_main) break :blk " -> i32";
            if (ref.ret_kind == .none) break :blk "";
            break :blk try std.fmt.allocPrint(self.gpa, " -> {s}", .{ref.ret_kind.saName()});
        };
        defer if (!std.mem.eql(u8, ret_ann, "") and !std.mem.eql(u8, ret_ann, " -> i32")) self.gpa.free(ret_ann);
        self.out.print("@{s}({s}){s}:\n", .{ fname, plist.items, ret_ann }) catch return error.CodegenError;

        self.ret_kind = if (self.is_main) .i32 else ref.ret_kind;
        self.ret_sid = ref.ret_sid;

        // Bind params (borrowed).
        self.depth = 1;
        if (ref.is_method and !ref.is_static) {
            _ = try self.addBinding("this", .ptr, ref.sid, false);
        }
        for (f.params, 0..) |pm, i| {
            const rt = ref.params[i];
            const b = try self.addBinding(pm.name, rt.kind, rt.sid, false);
            b.elem_kind = rt.elem_kind;
            b.elem_sid = rt.elem_sid;
        }
        const mark = self.bindings.items.len;
        for (f.body) |s| {
            try self.genStmt(s);
            if (self.terminated) {
                // Dead tail after return: stop emitting.
                break;
            }
        }
        if (!self.terminated) {
            if (self.is_main) {
                try self.releaseAbove(mark);
                try self.emit("ret 0", .{});
            } else if (ref.ret_kind == .none) {
                try self.releaseAbove(mark);
                try self.emit("ret", .{});
            } else {
                return self.err(f.off, "function '{s}' may fall off the end without returning", .{ref.full});
            }
        }
        self.depth = 0;
    }

    fn findFuncExact(self: *Codegen, f: *par.Func) ?*FuncRef {
        const full = std.fmt.allocPrint(self.gpa, "{s}{s}", .{ f.qual, f.name }) catch return null;
        defer self.gpa.free(full);
        for (self.funcrefs.items) |*r| {
            if (std.mem.eql(u8, r.full, full)) return r;
        }
        return null;
    }

    // -- statements ------------------------------------------------------------------

    fn genBlock(self: *Codegen, body: []par.Sid) CompileError!void {
        const mark = self.bindings.items.len;
        const tmark = self.temps.items.len;
        self.depth += 1;
        for (body) |s| {
            if (self.terminated) {
                return self.err(self.p.stmts.items[s].off, "unreachable code", .{});
            }
            try self.genStmt(s);
        }
        try self.releaseAbove(mark);
        self.popTo(mark);
        // Pop temps created in the block.
        while (self.temps.items.len > tmark) {
            _ = self.temps.pop();
        }
        self.depth -= 1;
    }

    fn genStmt(self: *Codegen, id: par.Sid) CompileError!void {
        const st = self.p.stmts.items[id];
        switch (st.kind) {
            .decl => |d| try self.genDecl(st.off, d.ty, d.name, d.init, d.has_init, d.array_len),
            .expr_stmt => |e| {
                const v = try self.genExpr(e);
                // cout chains print eagerly and yield nothing.
                const ek = self.p.exprs.items[e].kind;
                if (ek == .cout_chain) return;
                try self.killVal(v);
            },
            .if_ => |ifs| try self.genIf(st.off, ifs.cond, ifs.then_body, ifs.else_body, ifs.has_else),
            .while_ => |w| try self.genWhile(w.cond, w.body),
            .do_while => |d| try self.genDoWhile(d.body, d.cond),
            .for_ => |f| try self.genFor(st.off, f.init, f.cond, f.has_cond, f.step, f.has_step, f.body),
            .range_for => |r| try self.genRangeFor(st.off, r.ty, r.var_name, r.iterable, r.body),
            .switch_ => |s| try self.genSwitch(st.off, s.scrutinee, s.cases),
            .return_ => |r| try self.genReturn(st.off, r.value, r.has_value),
            .break_ => try self.genBreak(st.off),
            .continue_ => try self.genContinue(st.off),
            .block => |b| try self.genBlock(b),
        }
    }

    /// Zero-fill every field of a freshly allocated struct (v0.1 default
    /// construction semantics when no user constructor exists).
    fn zeroFillStruct(self: *Codegen, base: []const u8, layout: Layout) CompileError!void {
        for (layout.fields, 0..) |fld, k| {
            const zero: []const u8 = if (fld.kind == .f64) "0.0" else "0";
            try self.emit("store {s} + {d}, {s} as {s}", .{ base, layout.offsets[k], zero, fld.kind.saName() });
        }
    }

    fn constArrayLen(self: *Codegen, e: par.Eid, off: usize) CompileError!usize {
        _ = off;
        const ex = self.p.exprs.items[e];
        if (ex.kind != .int_lit) {
            return self.err(ex.off, "array size must be a constant in v0.1", .{});
        }
        const v = par.parseIntLit(ex.kind.int_lit) catch {
            return self.err(ex.off, "bad array size", .{});
        };
        if (v <= 0) return self.err(ex.off, "array size must be positive", .{});
        return @intCast(v);
    }

    fn genDecl(self: *Codegen, off: usize, ty: par.CType, name: []const u8, init_e: par.Eid, has_init: bool, array_len: ?par.Eid) CompileError!void {
        try self.checkUserName(name, off);
        if (self.lookup(name) != null) {
            // Shadowing: allowed only across depths.
            const old = self.lookup(name).?;
            if (old.depth == self.depth) {
                return self.err(off, "duplicate variable '{s}'", .{name});
            }
        }
        // Array declaration (array_len marker present).
        if (array_len) |alen_e| {
            const rt = try self.resolveType(ty, off);
            if (rt.kind == .none or !rt.kind.isScalar()) {
                return self.err(off, "arrays of '{s}' are not supported in v0.1", .{name});
            }
            const n = try self.constArrayLen(alen_e, off);
            const esz = primSize(rt.kind);
            try self.emit("{s} = alloc {d}", .{ name, n * esz });
            const b = try self.addBinding(name, .ptr, null, true);
            b.elem_kind = rt.kind;
            b.arr_len = n;
            if (has_init) {
                const ie = self.p.exprs.items[init_e];
                if (ie.kind != .init_list) {
                    return self.err(ie.off, "array '{s}' initializer must be a brace list", .{name});
                }
                if (ie.kind.init_list.len != n) {
                    return self.err(ie.off, "array '{s}' needs {d} initializers, got {d}", .{ name, n, ie.kind.init_list.len });
                }
                const addr = try self.newTemp();
                try self.addTemp(addr, false);
                for (ie.kind.init_list, 0..) |item, k| {
                    const v = try self.genExpr(item);
                    const cv = try self.conv(v, rt.kind, self.p.exprs.items[item].off);
                    try self.emit("{s} = add {s}, {d}", .{ addr, name, k * esz });
                    try self.emit("store {s} + 0, {s} as {s}", .{ addr, cv.txt, rt.kind.saName() });
                    try self.killVal(cv);
                }
            }
            return;
        }
        if (ty.prim == .auto_ and array_len == null) {
            if (!has_init) return self.err(off, "'auto' needs an initializer", .{});
            const v = try self.genExpr(init_e);
            if (v.kind == .none) return self.err(off, "cannot declare 'auto' void", .{});
            try self.bindDecl(name, v, .{ .kind = v.kind, .sid = v.sid }, off);
            return;
        }
        const rt = try self.resolveType(ty, off);
        if (rt.kind == .none) {
            return self.err(off, "cannot declare void variable '{s}'", .{name});
        }
        if (rt.kind == .ptr and rt.sid != null) {
            // Struct value: alloc + optional init.
            const layout = self.layouts.items[rt.sid.?];
            try self.emit("{s} = alloc {d}", .{ name, layout.size });
            _ = try self.addBinding(name, .ptr, rt.sid, true);
            if (has_init) {
                const ie = self.p.exprs.items[init_e];
                if (ie.kind != .init_list) {
                    return self.err(ie.off, "struct '{s}' needs a brace init list", .{name});
                }
                if (ie.kind.init_list.len != layout.fields.len) {
                    return self.err(ie.off, "struct '{s}' needs {d} initializers, got {d}", .{ name, layout.fields.len, ie.kind.init_list.len });
                }
                for (ie.kind.init_list, 0..) |item, k| {
                    const v = try self.genExpr(item);
                    const cv = try self.conv(v, layout.fields[k].kind, self.p.exprs.items[item].off);
                    try self.emit("store {s} + {d}, {s} as {s}", .{ name, layout.offsets[k], cv.txt, layout.fields[k].kind.saName() });
                    try self.killVal(cv);
                }
            } else {
                // Default-init: call default ctor if one was defined.
                const sdef = self.p.structs.items[rt.sid.?];
                const ctor_name = std.fmt.allocPrint(self.gpa, "{s}{s}_ctor", .{ sdef.qual, sdef.name }) catch return error.CodegenError;
                defer self.gpa.free(ctor_name);
                if (self.findFunc(ctor_name)) |_| {
                    try self.emit("call @{s}({s})", .{ ctor_name, name });
                } else {
                    try self.zeroFillStruct(name, layout);
                }
            }
            return;
        }
        // Scalar / plain pointer.
        if (!has_init) {
            const zero: []const u8 = switch (rt.kind) {
                .f64 => "0.0",
                else => "0",
            };
            try self.emit("{s} = {s}", .{ name, zero });
            _ = try self.addBinding(name, rt.kind, null, true);
            return;
        }
        const v = try self.genExpr(init_e);
        try self.bindDecl(name, v, rt, off);
    }

    /// Declare a fresh binding (shadows outer depths; same-depth duplicates
    /// are rejected by the caller via checkUserName/scope rules).
    fn bindDecl(self: *Codegen, name: []const u8, v: Val, rt: RType, off: usize) CompileError!void {
        const cv = try self.conv(v, rt.kind, off);
        const b = try self.addBinding(name, rt.kind, rt.sid, true);
        b.elem_kind = rt.elem_kind;
        b.elem_sid = rt.elem_sid;
        try self.storeToName(name, cv, rt.kind);
    }

    /// Emit `name = <value>` with copy-vs-move discipline:
    /// scalars from named sources are COPIED (source stays live);
    /// temps are transferred; pointers/structs MOVE (source disowned).
    /// Callers handle the target's release-old and owned flag.
    fn storeToName(self: *Codegen, name: []const u8, cv: Val, rt_kind: VKind) CompileError!void {
        if (!cv.is_temp and rt_kind.isScalar()) {
            if (self.lookup(cv.txt)) |_| {
                const cp = try self.newTemp();
                try self.addTemp(cp, false);
                if (rt_kind == .f64) {
                    try self.emit("{s} = fadd {s}, 0.0", .{ cp, cv.txt });
                } else {
                    try self.emit("{s} = add {s}, 0", .{ cp, cv.txt });
                }
                try self.emit("{s} = {s}", .{ name, cp });
                return;
            }
            try self.emit("{s} = {s}", .{ name, cv.txt });
            return;
        }
        try self.emit("{s} = {s}", .{ name, cv.txt });
        if (cv.is_temp and cv.owned) {
            for (self.temps.items) |*t| {
                if (t.live and std.mem.eql(u8, t.name, cv.txt)) t.live = false;
            }
        } else if (!cv.is_temp) {
            if (self.lookup(cv.txt)) |src| src.owned = false; // move
        }
    }

    /// Evaluate a condition to a value used directly by `br`.
    /// No hidden binding is created: transient temps die silently, owned
    /// temps stay live until the single post-merge scope-end release, and
    /// names are borrowed. This keeps both sides of a merge in agreement.
    fn condVal(self: *Codegen, e: par.Eid) CompileError!Val {
        const c = try self.genExpr(e);
        return self.conv(c, .i32, self.p.exprs.items[e].off);
    }

    fn genIf(self: *Codegen, _: usize, cond: par.Eid, then_body: []par.Sid, else_body: []par.Sid, has_else: bool) CompileError!void {
        const cv = try self.condVal(cond);
        const l_then = try self.newLabel("then");
        const l_merge = try self.newLabel("endif");
        if (has_else) {
            const l_else = try self.newLabel("else");
            try self.emit("br {s} -> {s}, {s}", .{ cv.txt, l_then, l_else });
            try self.emitLabel(l_then);
            try self.genBlock(then_body);
            if (!self.terminated) try self.emit("jmp {s}", .{l_merge});
            self.terminated = false;
            try self.emitLabel(l_else);
            try self.genBlock(else_body);
            if (!self.terminated) try self.emit("jmp {s}", .{l_merge});
            self.terminated = false;
            try self.emitLabel(l_merge);
        } else {
            try self.emit("br {s} -> {s}, {s}", .{ cv.txt, l_then, l_merge });
            try self.emitLabel(l_then);
            try self.genBlock(then_body);
            if (!self.terminated) try self.emit("jmp {s}", .{l_merge});
            self.terminated = false;
            try self.emitLabel(l_merge);
        }
    }

    fn genWhile(self: *Codegen, cond: par.Eid, body: []par.Sid) CompileError!void {
        const l_top = try self.newLabel("while");
        const l_body = try self.newLabel("wbody");
        const l_end = try self.newLabel("wend");
        try self.emitLabel(l_top);
        const cv = try self.condVal(cond);
        try self.emit("br {s} -> {s}, {s}", .{ cv.txt, l_body, l_end });
        try self.emitLabel(l_body);
        try self.loops.append(.{ .cont_label = l_top, .break_label = l_end, .depth = self.depth });
        try self.genBlock(body);
        _ = self.loops.pop();
        if (!self.terminated) try self.emit("jmp {s}", .{l_top});
        self.terminated = false;
        try self.emitLabel(l_end);
    }

    fn genDoWhile(self: *Codegen, body: []par.Sid, cond: par.Eid) CompileError!void {
        const l_body = try self.newLabel("do");
        const l_end = try self.newLabel("dend");
        try self.emitLabel(l_body);
        try self.loops.append(.{ .cont_label = l_body, .break_label = l_end, .depth = self.depth });
        try self.genBlock(body);
        _ = self.loops.pop();
        if (!self.terminated) {
            const cv = try self.condVal(cond);
            try self.emit("br {s} -> {s}, {s}", .{ cv.txt, l_body, l_end });
        }
        self.terminated = false;
        try self.emitLabel(l_end);
    }

    fn genFor(self: *Codegen, _: usize, init_s: []par.Sid, cond: par.Eid, has_cond: bool, step: par.Eid, has_step: bool, body: []par.Sid) CompileError!void {
        const mark = self.bindings.items.len;
        const tmark = self.temps.items.len;
        self.depth += 1;
        for (init_s) |s| {
            try self.genStmt(s);
        }
        const l_top = try self.newLabel("for");
        const l_body = try self.newLabel("fbody");
        const l_step = try self.newLabel("fstep");
        const l_end = try self.newLabel("fend");
        try self.emitLabel(l_top);
        if (has_cond) {
            const cv = try self.condVal(cond);
            try self.emit("br {s} -> {s}, {s}", .{ cv.txt, l_body, l_end });
        } else {
            try self.emit("jmp {s}", .{l_body});
        }
        try self.emitLabel(l_body);
        try self.loops.append(.{ .cont_label = l_step, .break_label = l_end, .depth = self.depth });
        try self.genBlock(body);
        _ = self.loops.pop();
        if (!self.terminated) try self.emit("jmp {s}", .{l_step});
        self.terminated = false;
        try self.emitLabel(l_step);
        if (has_step) {
            const sv = try self.genExpr(step);
            try self.killVal(sv);
        }
        try self.emit("jmp {s}", .{l_top});
        try self.emitLabel(l_end);
        try self.releaseAbove(mark);
        self.popTo(mark);
        while (self.temps.items.len > tmark) {
            _ = self.temps.pop();
        }
        self.depth -= 1;
    }

    fn genRangeFor(self: *Codegen, off: usize, ty: par.CType, var_name: []const u8, iterable: par.Eid, body: []par.Sid) CompileError!void {
        try self.checkUserName(var_name, off);
        const ie = self.p.exprs.items[iterable];
        if (ie.kind != .ident) {
            return self.err(ie.off, "range-for needs a local array variable in v0.1", .{});
        }
        const arr = self.lookup(ie.kind.ident) orelse {
            return self.err(ie.off, "unknown variable '{s}'", .{ie.kind.ident});
        };
        const n = arr.arr_len orelse {
            return self.err(ie.off, "range-for needs a fixed-size array in v0.1", .{});
        };
        const elem_kind = arr.elem_kind;
        var want = try self.resolveType(ty, off);
        if (ty.prim == .auto_) want = .{ .kind = elem_kind };
        if (want.kind != elem_kind) {
            return self.err(off, "range variable type mismatch", .{});
        }
        const mark = self.bindings.items.len;
        const tmark = self.temps.items.len;
        self.depth += 1;
        const idx = try self.newHidden("i");
        try self.emit("{s} = 0", .{idx});
        _ = try self.addBinding(idx, .i32, null, true);
        const l_top = try self.newLabel("rfor");
        const l_body = try self.newLabel("rbody");
        const l_end = try self.newLabel("rend");
        try self.emitLabel(l_top);
        const cc = try self.newTemp();
        try self.addTemp(cc, false);
        try self.emit("{s} = slt {s}, {d}", .{ cc, idx, n });
        try self.emit("br {s} -> {s}, {s}", .{ cc, l_body, l_end });
        try self.emitLabel(l_body);
        try self.loops.append(.{ .cont_label = l_top, .break_label = l_end, .depth = self.depth });
        const addr = try self.newTemp();
        try self.addTemp(addr, false);
        const esz = primSize(elem_kind);
        try self.emit("{s} = mul {s}, {d}", .{ addr, idx, esz });
        const base2 = try self.newTemp();
        try self.addTemp(base2, false);
        try self.emit("{s} = add {s}, {s}", .{ base2, ie.kind.ident, addr });
        const lv = try self.newTemp();
        try self.addTemp(lv, false);
        try self.emit("{s} = load {s} + 0 as {s}", .{ lv, base2, elem_kind.saName() });
        _ = try self.addBinding(var_name, elem_kind, null, true);
        try self.emit("{s} = {s}", .{ var_name, lv });
        try self.genBlock(body);
        _ = self.loops.pop();
        if (!self.terminated) {
            const ni = try self.newTemp();
            try self.addTemp(ni, false);
            try self.emit("{s} = add {s}, 1", .{ ni, idx });
            try self.emit("!{s}", .{idx});
            try self.emit("{s} = {s}", .{ idx, ni });
            if (self.lookup(idx)) |b| b.owned = true;
            try self.emit("jmp {s}", .{l_top});
        }
        self.terminated = false;
        try self.emitLabel(l_end);
        try self.releaseAbove(mark);
        self.popTo(mark);
        while (self.temps.items.len > tmark) {
            _ = self.temps.pop();
        }
        self.depth -= 1;
    }

    fn genSwitch(self: *Codegen, _: usize, scrutinee: par.Eid, cases: []par.SwitchCase) CompileError!void {
        const sv = try self.genExpr(scrutinee);
        if (!sv.kind.isInt()) {
            return self.err(self.p.exprs.items[scrutinee].off, "switch needs an integer", .{});
        }
        const sw = try self.newHidden("sw");
        _ = try self.addBinding(sw, sv.kind, null, true);
        try self.storeToName(sw, sv, sv.kind);
        for (cases, 0..) |c, i| {
            if (c.value == null and i != cases.len - 1) {
                return self.err(self.p.exprs.items[scrutinee].off, "default must be the last case in v0.1", .{});
            }
        }
        const l_end = try self.newLabel("swend");
        // Pre-assign deterministic case labels.
        const case_base = self.lbl_n;
        self.lbl_n += 1;
        var next_labels: std.array_list.Managed([]const u8) = .init(self.gpa);
        defer next_labels.deinit();
        for (0..cases.len) |_| {
            try next_labels.append(try self.newLabel("swnext"));
        }
        for (cases, 0..) |c, i| {
            const l_case = try std.fmt.allocPrint(self.gpa, "L_cpp_case_{d}_{d}", .{ case_base, i });
            if (c.value) |ve| {
                const ce = self.p.exprs.items[ve];
                if (ce.kind != .int_lit) {
                    return self.err(ce.off, "case labels must be integer constants in v0.1", .{});
                }
                const lit = try self.normIntLit(ce.kind.int_lit, ce.off);
                const t = try self.newTemp();
                try self.addTemp(t, false);
                try self.emit("{s} = eq {s}, {s}", .{ t, sw, lit });
                try self.emit("br {s} -> {s}, {s}", .{ t, l_case, next_labels.items[i] });
            } else {
                try self.emit("jmp {s}", .{l_case});
            }
            try self.emitLabel(next_labels.items[i]);
            if (i + 1 >= cases.len) {
                try self.emit("jmp {s}", .{l_end});
            }
        }
        try self.loops.append(.{ .cont_label = null, .break_label = l_end, .depth = self.depth });
        for (cases, 0..) |c, i| {
            const l_case = try std.fmt.allocPrint(self.gpa, "L_cpp_case_{d}_{d}", .{ case_base, i });
            try self.emitLabel(l_case);
            self.depth += 1;
            const mark = self.bindings.items.len;
            const tmark = self.temps.items.len;
            for (c.body) |s| {
                if (self.terminated) break;
                try self.genStmt(s);
            }
            self.terminated = false;
            try self.releaseAbove(mark);
            self.popTo(mark);
            while (self.temps.items.len > tmark) {
                _ = self.temps.pop();
            }
            self.depth -= 1;
        }
        _ = self.loops.pop();
        try self.emitLabel(l_end);
    }

    fn genReturn(self: *Codegen, _: usize, value: par.Eid, has_value: bool) CompileError!void {
        if (!has_value) {
            if (self.is_main) {
                try self.releaseAll(null);
                try self.emit("ret 0", .{});
                self.terminated = true;
                return;
            }
            if (self.ret_kind != .none) {
                return self.err(self.p.stmts.items[0].off, "return needs a value", .{});
            }
            try self.releaseAll(null);
            try self.emit("ret", .{});
            self.terminated = true;
            return;
        }
        const v = try self.genExpr(value);
        const cv = try self.conv(v, self.ret_kind, self.p.exprs.items[value].off);
        if (!cv.is_temp) {
            if (self.lookup(cv.txt)) |src| {
                if (self.ret_kind.isScalar()) {
                    // Copy scalars so releaseAll can free the original.
                    const rc = try self.newTemp();
                    try self.addTemp(rc, false);
                    if (self.ret_kind == .f64) {
                        try self.emit("{s} = fadd {s}, 0.0", .{ rc, cv.txt });
                    } else {
                        try self.emit("{s} = add {s}, 0", .{ rc, cv.txt });
                    }
                    try self.releaseAll(null);
                    try self.emit("ret {s}", .{rc});
                    self.terminated = true;
                    return;
                }
                // Move pointers/structs out: disown the source binding.
                src.owned = false;
                try self.releaseAll(null);
                try self.emit("ret {s}", .{cv.txt});
                self.terminated = true;
                return;
            }
            try self.releaseAll(null);
            try self.emit("ret {s}", .{cv.txt});
            self.terminated = true;
            return;
        }
        const keep: ?[]const u8 = if (cv.owned) cv.txt else null;
        try self.releaseAll(keep);
        try self.emit("ret {s}", .{cv.txt});
        self.terminated = true;
    }

    fn genBreak(self: *Codegen, off: usize) CompileError!void {
        if (self.loops.items.len == 0) {
            return self.err(off, "'break' outside a loop or switch", .{});
        }
        const ctx = self.loops.items[self.loops.items.len - 1];
        try self.releaseAbove(ctx.depth);
        try self.emit("jmp {s}", .{ctx.break_label});
        self.terminated = true;
    }

    fn genContinue(self: *Codegen, off: usize) CompileError!void {
        var i = self.loops.items.len;
        while (i > 0) {
            i -= 1;
            const ctx = self.loops.items[i];
            if (ctx.cont_label) |cl| {
                try self.releaseAbove(ctx.depth);
                try self.emit("jmp {s}", .{cl});
                self.terminated = true;
                return;
            }
        }
        return self.err(off, "'continue' outside a loop", .{});
    }

    // -- lvalues -------------------------------------------------------------------

    const LValue = union(enum) {
        local: usize, // binding index
        field: struct { base: []const u8, off: usize, kind: VKind },
        addr: struct { ptr: []const u8, kind: VKind }, // precomputed address temp
    };

    fn genLValue(self: *Codegen, e: par.Eid) CompileError!LValue {
        const ex = self.p.exprs.items[e];
        switch (ex.kind) {
            .ident => |n| {
                if (self.lookup(n)) |b| {
                    const idx = (@intFromPtr(b) - @intFromPtr(self.bindings.items.ptr)) / @sizeOf(Binding);
                    return .{ .local = idx };
                }
                // Implicit this-> for bare member names inside methods.
                if (self.cur_sid) |si| {
                    if (self.lookup("this") != null) {
                        const layout = self.layouts.items[si];
                        for (layout.fields, 0..) |fld, k| {
                            if (std.mem.eql(u8, fld.name, n)) {
                                return .{ .field = .{ .base = "this", .off = layout.offsets[k], .kind = fld.kind } };
                            }
                        }
                    }
                }
                return self.err(ex.off, "unknown variable '{s}'", .{n});
            },
            .field => |f| {
                const b = try self.baseBinding(f.base, ex.off);
                const layout = self.layouts.items[b.sid.?];
                for (layout.fields, 0..) |fld, k| {
                    if (std.mem.eql(u8, fld.name, f.name)) {
                        return .{ .field = .{ .base = b.name, .off = layout.offsets[k], .kind = fld.kind } };
                    }
                }
                return self.err(ex.off, "struct has no field '{s}'", .{f.name});
            },
            .index => |ix| {
                const addr = try self.genIndexAddr(ix.base, ix.idx, ex.off);
                const kind = try self.indexElemKind(ix.base, ex.off);
                return .{ .addr = .{ .ptr = addr, .kind = kind } };
            },
            .unary => |u| {
                if (u.op != .deref) {
                    return self.err(ex.off, "not assignable", .{});
                }
                const p = try self.genExpr(u.x);
                if (p.kind != .ptr) {
                    return self.err(ex.off, "cannot dereference a non-pointer", .{});
                }
                return .{ .addr = .{ .ptr = p.txt, .kind = .i32 } };
            },
            else => return self.err(ex.off, "not assignable", .{}),
        }
    }

    fn baseBinding(self: *Codegen, e: par.Eid, off: usize) CompileError!*Binding {
        const ex = self.p.exprs.items[e];
        if (ex.kind == .ident) {
            const b = self.lookup(ex.kind.ident) orelse {
                return self.err(ex.off, "unknown variable '{s}'", .{ex.kind.ident});
            };
            if (b.kind != .ptr or b.sid == null) {
                return self.err(ex.off, "member access needs a struct object", .{});
            }
            return b;
        }
        if (ex.kind == .this_) {
            const b = self.lookup("this") orelse {
                return self.err(ex.off, "'this' outside a method", .{});
            };
            return b;
        }
        return self.err(off, "member access needs a named object in v0.1", .{});
    }

    fn indexElemKind(self: *Codegen, base: par.Eid, off: usize) CompileError!VKind {
        const be = self.p.exprs.items[base];
        if (be.kind == .ident) {
            const b = self.lookup(be.kind.ident) orelse {
                return self.err(be.off, "unknown variable '{s}'", .{be.kind.ident});
            };
            if (b.arr_len != null) return b.elem_kind;
            if (b.kind == .ptr) return b.elem_kind;
            return self.err(off, "cannot index a non-array", .{});
        }
        // Transient pointer expression: assume i32 elements is wrong; only
        // named bases carry element types in v0.1.
        return self.err(off, "indexing needs a named array or pointer in v0.1", .{});
    }

    /// Lower `base[idx]` to an address temp holding base + idx*esz.
    fn genIndexAddr(self: *Codegen, base: par.Eid, idx: par.Eid, off: usize) CompileError![]const u8 {
        const be = self.p.exprs.items[base];
        var base_txt: []const u8 = undefined;
        var esz: usize = 4;
        if (be.kind == .ident) {
            const b = self.lookup(be.kind.ident) orelse {
                return self.err(be.off, "unknown variable '{s}'", .{be.kind.ident});
            };
            base_txt = b.name;
            if (b.arr_len != null) {
                esz = primSize(b.elem_kind);
            } else if (b.kind == .ptr) {
                esz = primSize(b.elem_kind);
            } else {
                return self.err(off, "cannot index a non-array", .{});
            }
        } else {
            return self.err(off, "indexing needs a named array or pointer in v0.1", .{});
        }
        const iv = try self.genExpr(idx);
        const ic = try self.conv(iv, .i32, self.p.exprs.items[idx].off);
        const t1 = try self.newTemp();
        try self.addTemp(t1, false);
        try self.emit("{s} = mul {s}, {d}", .{ t1, ic.txt, esz });
        try self.killVal(ic);
        const t2 = try self.newTemp();
        try self.addTemp(t2, false);
        try self.emit("{s} = add {s}, {s}", .{ t2, base_txt, t1 });
        return t2;
    }

    fn assignTo(self: *Codegen, lv: LValue, v: Val, off: usize) CompileError!void {
        switch (lv) {
            .local => |bi| {
                const b = &self.bindings.items[bi];
                const cv = try self.conv(v, b.kind, off);
                if (!cv.is_temp and std.mem.eql(u8, cv.txt, b.name)) return;
                // Always release the old value: locals own theirs, and
                // parameters are callee-owned on first write.
                try self.emit("!{s}", .{b.name});
                b.owned = true;
                try self.storeToName(b.name, cv, b.kind);
            },
            .field => |f| {
                const cv = try self.conv(v, f.kind, off);
                try self.emit("store {s} + {d}, {s} as {s}", .{ f.base, f.off, cv.txt, f.kind.saName() });
                try self.killVal(cv);
            },
            .addr => |a| {
                const cv = try self.conv(v, a.kind, off);
                try self.emit("store {s} + 0, {s} as {s}", .{ a.ptr, cv.txt, a.kind.saName() });
                try self.killVal(cv);
            },
        }
    }

    fn assignResult(self: *Codegen, lv: LValue) Val {
        switch (lv) {
            .local => |bi| {
                const b = self.bindings.items[bi];
                return .{ .txt = b.name, .kind = b.kind, .owned = false, .is_temp = false, .sid = b.sid };
            },
            else => return .{ .txt = "0", .kind = .i32, .owned = false, .is_temp = false },
        }
    }

    fn isAssignOpLocal(op: par.BinOp) bool {
        return switch (op) {
            .assign, .add_assign, .sub_assign, .mul_assign, .div_assign, .rem_assign, .shl_assign, .shr_assign, .band_assign, .bor_assign, .bxor_assign => true,
            else => false,
        };
    }

    fn genAssignOp(self: *Codegen, off: usize, target: par.Eid, op: par.BinOp, value: par.Eid) CompileError!Val {
        // `=` handled by assignTo; compound ops lower via load/op/store.
        if (op == .assign) {
            const lv = try self.genLValue(target);
            const v = try self.genExpr(value);
            try self.assignTo(lv, v, off);
            return self.assignResult(lv);
        }
        const lv = try self.genLValue(target);
        const v = try self.genExpr(value);
        const base_op: par.BinOp = switch (op) {
            .add_assign => .add,
            .sub_assign => .sub,
            .mul_assign => .mul,
            .div_assign => .div,
            .rem_assign => .rem,
            .shl_assign => .shl,
            .shr_assign => .shr,
            .band_assign => .bit_and,
            .bor_assign => .bit_or,
            .bxor_assign => .bit_xor,
            else => return self.err(off, "internal: bad assign op", .{}),
        };
        switch (lv) {
            .local => |bi| {
                const b = &self.bindings.items[bi];
                const rhs = try self.conv(v, b.kind, off);
                const t = try self.newTemp();
                try self.addTemp(t, false);
                try self.emitBin(t, base_op, b.name, b.kind, rhs.txt, rhs.kind, off);
                try self.killVal(rhs);
                if (b.owned) try self.emit("!{s}", .{b.name});
                b.owned = true;
                try self.emit("{s} = {s}", .{ b.name, t });
            },
            .field => |f| {
                const cur = try self.newTemp();
                try self.addTemp(cur, false);
                try self.emit("{s} = load {s} + {d} as {s}", .{ cur, f.base, f.off, f.kind.saName() });
                const rhs = try self.conv(v, f.kind, off);
                const t = try self.newTemp();
                try self.addTemp(t, false);
                try self.emitBin(t, base_op, cur, f.kind, rhs.txt, rhs.kind, off);
                try self.killVal(rhs);
                try self.emit("store {s} + {d}, {s} as {s}", .{ f.base, f.off, t, f.kind.saName() });
            },
            .addr => |a| {
                const cur = try self.newTemp();
                try self.addTemp(cur, false);
                try self.emit("{s} = load {s} + 0 as {s}", .{ cur, a.ptr, a.kind.saName() });
                const rhs = try self.conv(v, a.kind, off);
                const t = try self.newTemp();
                try self.addTemp(t, false);
                try self.emitBin(t, base_op, cur, a.kind, rhs.txt, rhs.kind, off);
                try self.killVal(rhs);
                try self.emit("store {s} + 0, {s} as {s}", .{ a.ptr, t, a.kind.saName() });
            },
        }
        return self.assignResult(lv);
    }

    fn emitBin(self: *Codegen, dst: []const u8, op: par.BinOp, ltxt: []const u8, lkind: VKind, rtxt: []const u8, rkind: VKind, _: usize) CompileError!void {
        if (lkind == .f64 or rkind == .f64) {
            const o: []const u8 = switch (op) {
                .add => "fadd",
                .sub => "fsub",
                .mul => "fmul",
                .div => "fdiv",
                .lt => "fcmp_lt",
                .le => "fcmp_le",
                .gt => "fcmp_gt",
                .ge => "fcmp_ge",
                .eq => "fcmp_eq",
                .ne => "fcmp_ne",
                else => "fadd",
            };
            if (op == .rem or op == .shl or op == .shr or op == .bit_and or op == .bit_or or op == .bit_xor) {
                try self.emit("{s} = {s} {s}, {s}", .{ dst, o, ltxt, rtxt });
            } else {
                try self.emit("{s} = {s} {s}, {s}", .{ dst, o, ltxt, rtxt });
            }
            return;
        }
        const o: []const u8 = switch (op) {
            .add => "add",
            .sub => "sub",
            .mul => "mul",
            .div => "sdiv",
            .rem => "srem",
            .shl => "shl",
            .shr => "ashr",
            .eq => "eq",
            .ne => "ne",
            .lt => "slt",
            .le => "sle",
            .gt => "sgt",
            .ge => "sge",
            .bit_and => "and",
            .bit_or => "or",
            .bit_xor => "xor",
            .log_and => "and",
            .log_or => "or",
            else => "add",
        };
        try self.emit("{s} = {s} {s}, {s}", .{ dst, o, ltxt, rtxt });
    }

    /// Convert a value to the target kind, emitting conversion instructions.
    fn conv(self: *Codegen, v: Val, want: VKind, off: usize) CompileError!Val {
        if (v.kind == want) return v;
        // Fat and thin pointers share the SA "ptr" representation.
        if ((v.kind == .slice or v.kind == .ptr) and (want == .slice or want == .ptr)) {
            return .{ .txt = v.txt, .kind = want, .owned = v.owned, .is_temp = v.is_temp, .sid = v.sid };
        }
        if (want == .boolean) {
            // Truthiness: ne with zero.
            const zero: []const u8 = if (v.kind == .f64) "0.0" else "0";
            const t = try self.newTemp();
            try self.addTemp(t, false);
            const op: []const u8 = if (v.kind == .f64) "fcmp_ne" else "ne";
            try self.emit("{s} = {s} {s}, {s}", .{ t, op, v.txt, zero });
            try self.killVal(v);
            return .{ .txt = t, .kind = .boolean, .owned = false, .is_temp = true };
        }
        if (v.kind == .boolean and want.isInt()) {
            return .{ .txt = v.txt, .kind = want, .owned = v.owned, .is_temp = v.is_temp, .sid = v.sid };
        }
        if (v.kind.isInt() and want.isInt()) {
            // i32<->i64/char/bool: sext/trunc. All int kinds share i32 repr
            // except i64, so only i64 crossings emit anything.
            if (v.kind == .i64 and want != .i64) {
                const t = try self.newTemp();
                try self.addTemp(t, false);
                try self.emit("{s} = trunc {s} as i32", .{ t, v.txt });
                try self.killVal(v);
                return .{ .txt = t, .kind = want, .owned = false, .is_temp = true };
            }
            if (v.kind != .i64 and want == .i64) {
                const t = try self.newTemp();
                try self.addTemp(t, false);
                try self.emit("{s} = sext {s} as i64", .{ t, v.txt });
                try self.killVal(v);
                return .{ .txt = t, .kind = .i64, .owned = false, .is_temp = true };
            }
            return .{ .txt = v.txt, .kind = want, .owned = v.owned, .is_temp = v.is_temp, .sid = v.sid };
        }
        if (v.kind.isInt() and want == .f64) {
            const t = try self.newTemp();
            try self.addTemp(t, false);
            try self.emit("{s} = sitofp {s} as f64", .{ t, v.txt });
            try self.killVal(v);
            return .{ .txt = t, .kind = .f64, .owned = false, .is_temp = true };
        }
        if (v.kind == .f64 and want.isInt()) {
            const t = try self.newTemp();
            try self.addTemp(t, false);
            const dst: []const u8 = if (want == .i64) "i64" else "i32";
            try self.emit("{s} = fptosi {s} as {s}", .{ t, v.txt, dst });
            try self.killVal(v);
            return .{ .txt = t, .kind = want, .owned = false, .is_temp = true };
        }
        return self.err(off, "cannot convert {s} to {s}", .{ @tagName(v.kind), @tagName(want) });
    }

    fn genIncDec(self: *Codegen, target: par.Eid, op: par.UnOp, off: usize, as_expr: bool) CompileError!Val {
        const is_pre = op == .pre_inc or op == .pre_dec;
        const is_inc = op == .pre_inc or op == .post_inc;
        const lv = try self.genLValue(target);
        const base_op: par.BinOp = if (is_inc) .add else .sub;
        switch (lv) {
            .local => |bi| {
                const b = &self.bindings.items[bi];
                const t = try self.newTemp();
                try self.addTemp(t, false);
                try self.emitBin(t, base_op, b.name, b.kind, "1", .i32, off);
                if (is_pre) {
                    if (b.owned) try self.emit("!{s}", .{b.name});
                    b.owned = true;
                    try self.emit("{s} = {s}", .{ b.name, t });
                    if (as_expr) return .{ .txt = t, .kind = b.kind, .owned = false, .is_temp = true };
                    return .{ .txt = "0", .kind = .i32, .owned = false, .is_temp = false };
                } else {
                    var old: Val = .{ .txt = "0", .kind = .i32, .owned = false, .is_temp = false };
                    if (as_expr) {
                        const oc = try self.newTemp();
                        try self.addTemp(oc, false);
                        try self.emit("{s} = add {s}, 0", .{ oc, b.name });
                        old = .{ .txt = oc, .kind = b.kind, .owned = false, .is_temp = true };
                    }
                    if (b.owned) try self.emit("!{s}", .{b.name});
                    b.owned = true;
                    try self.emit("{s} = {s}", .{ b.name, t });
                    return old;
                }
            },
            .field => |f| {
                const cur = try self.newTemp();
                try self.addTemp(cur, false);
                try self.emit("{s} = load {s} + {d} as {s}", .{ cur, f.base, f.off, f.kind.saName() });
                var old: Val = .{ .txt = "0", .kind = .i32, .owned = false, .is_temp = false };
                if (!is_pre and as_expr) {
                    const oc = try self.newTemp();
                    try self.addTemp(oc, false);
                    try self.emit("{s} = add {s}, 0", .{ oc, cur });
                    old = .{ .txt = oc, .kind = f.kind, .owned = false, .is_temp = true };
                }
                const t = try self.newTemp();
                try self.addTemp(t, false);
                try self.emitBin(t, base_op, cur, f.kind, "1", .i32, off);
                try self.emit("store {s} + {d}, {s} as {s}", .{ f.base, f.off, t, f.kind.saName() });
                if (is_pre and as_expr) return .{ .txt = t, .kind = f.kind, .owned = false, .is_temp = true };
                return old;
            },
            .addr => |a| {
                const cur = try self.newTemp();
                try self.addTemp(cur, false);
                try self.emit("{s} = load {s} + 0 as {s}", .{ cur, a.ptr, a.kind.saName() });
                var old: Val = .{ .txt = "0", .kind = .i32, .owned = false, .is_temp = false };
                if (!is_pre and as_expr) {
                    const oc = try self.newTemp();
                    try self.addTemp(oc, false);
                    try self.emit("{s} = add {s}, 0", .{ oc, cur });
                    old = .{ .txt = oc, .kind = a.kind, .owned = false, .is_temp = true };
                }
                const t = try self.newTemp();
                try self.addTemp(t, false);
                try self.emitBin(t, base_op, cur, a.kind, "1", .i32, off);
                try self.emit("store {s} + 0, {s} as {s}", .{ a.ptr, t, a.kind.saName() });
                if (is_pre and as_expr) return .{ .txt = t, .kind = a.kind, .owned = false, .is_temp = true };
                return old;
            },
        }
    }

    fn unifyKinds(_: *Codegen, a: VKind, b: VKind, _: usize) CompileError!VKind {
        if (a == b) return a;
        if ((a == .i32 and b == .i64) or (a == .i64 and b == .i32)) return .i64;
        if (a == .boolean and b.isInt()) return b;
        if (b == .boolean and a.isInt()) return a;
        if (a == .f64 and b.isInt()) return .f64;
        if (b == .f64 and a.isInt()) return .f64;
        if ((a == .ptr or a == .slice) and (b == .ptr or b == .slice)) return .ptr;
        return error.CodegenError;
    }

    fn normalizeCallName(self: *Codegen, raw: []const u8) CompileError![]const u8 {
        if (std.mem.indexOf(u8, raw, "::") == null) return raw;
        const buf = try self.gpa.dupe(u8, raw);
        for (buf) |*ch| {
            if (ch.* == ':') ch.* = '_';
        }
        var w: usize = 0;
        var i: usize = 0;
        while (i < buf.len) {
            if (buf[i] == '_' and i + 1 < buf.len and buf[i + 1] == '_') {
                buf[w] = '_';
                w += 1;
                i += 2;
            } else {
                buf[w] = buf[i];
                w += 1;
                i += 1;
            }
        }
        return buf[0..w];
    }

    fn typeofLValue(self: *Codegen, e: par.Eid) CompileError!VKind {
        const ex = self.p.exprs.items[e];
        switch (ex.kind) {
            .ident => |n| {
                if (self.lookup(n)) |b| return b.kind;
                if (self.cur_sid) |si| {
                    if (self.lookup("this") != null) {
                        const layout = self.layouts.items[si];
                        for (layout.fields) |fld| {
                            if (std.mem.eql(u8, fld.name, n)) return fld.kind;
                        }
                    }
                }
                return self.err(ex.off, "unknown variable '{s}'", .{n});
            },
            .field => |f| {
                const b = try self.baseBinding(f.base, ex.off);
                const layout = self.layouts.items[b.sid.?];
                for (layout.fields) |fld| {
                    if (std.mem.eql(u8, fld.name, f.name)) return fld.kind;
                }
                return self.err(ex.off, "struct has no field '{s}'", .{f.name});
            },
            .index => |ix| return self.indexElemKind(ix.base, ex.off),
            .unary => |u| {
                if (u.op != .deref) return self.err(ex.off, "not assignable", .{});
                return .i32;
            },
            else => return self.err(ex.off, "not assignable", .{}),
        }
    }

    /// Static result kind of an expression (no code emitted).
    fn typeofExpr(self: *Codegen, e: par.Eid) CompileError!VKind {
        const ex = self.p.exprs.items[e];
        switch (ex.kind) {
            .int_lit => return .i32,
            .float_lit => return .f64,
            .str_lit => return .slice,
            .char_lit => return .i32,
            .bool_lit => return .boolean,
            .null_lit => return .ptr,
            .ident => |n| {
                if (self.lookup(n)) |b| return b.kind;
                if (self.cur_sid) |si| {
                    if (self.lookup("this") != null) {
                        const layout = self.layouts.items[si];
                        for (layout.fields) |fld| {
                            if (std.mem.eql(u8, fld.name, n)) return fld.kind;
                        }
                    }
                }
                return self.err(ex.off, "unknown variable '{s}'", .{n});
            },
            .this_ => return .ptr,
            .unary => |u| switch (u.op) {
                .not => return .boolean,
                .addrof => return .ptr,
                .deref => return .i32,
                .pre_inc, .pre_dec, .post_inc, .post_dec => return self.typeofExpr(u.x),
                .neg => {
                    const k = try self.typeofExpr(u.x);
                    if (k == .f64 or k.isInt()) return k;
                    return self.err(ex.off, "cannot negate this value (need a number)", .{});
                },
                .bnot => {
                    const k = try self.typeofExpr(u.x);
                    if (k.isInt()) return k;
                    return self.err(ex.off, "cannot bits-flip this value (need an integer)", .{});
                },
            },
            .binary => |b| {
                if (b.op == .assign or isAssignOpLocal(b.op)) {
                    return self.typeofLValue(b.l);
                }
                const lk = try self.typeofExpr(b.l);
                const rk = try self.typeofExpr(b.r);
                if (b.op == .lt or b.op == .le or b.op == .gt or b.op == .ge or b.op == .eq or b.op == .ne or b.op == .log_and or b.op == .log_or) {
                    return .boolean;
                }
                if (lk == .f64 or rk == .f64) return .f64;
                if (lk == .i64 or rk == .i64) return .i64;
                return lk;
            },
            .ternary => |tr| {
                const tk = try self.typeofExpr(tr.t);
                const fk = try self.typeofExpr(tr.f);
                if (tk == .none and fk == .none) return .none;
                if (tk == .none or fk == .none) {
                    return self.err(ex.off, "ternary arms have mismatched types in v0.1", .{});
                }
                return self.unifyKinds(tk, fk, ex.off) catch {
                    return self.err(ex.off, "ternary arms have mismatched types in v0.1", .{});
                };
            },
            .call => |c| {
                const ce = self.p.exprs.items[c.callee];
                if (ce.kind != .ident) {
                    return self.err(ce.off, "indirect calls are not supported in v0.1", .{});
                }
                const nm = try self.normalizeCallName(ce.kind.ident);
                defer if (nm.ptr != ce.kind.ident.ptr) self.gpa.free(nm);
                const ref = self.findFunc(nm) orelse {
                    return self.err(ce.off, "unknown function '{s}'", .{ce.kind.ident});
                };
                if (ref.is_method and !ref.is_static) {
                    return self.err(ce.off, "method '{s}' needs an object (write obj.{s}(...))", .{ nm, ce.kind.ident });
                }
                return ref.ret_kind;
            },
            .method_call => |m| {
                const ref = try self.methodFuncRef(m.obj, m.name, ex.off);
                return ref.ret_kind;
            },
            .index => |ix| return self.indexElemKind(ix.base, ex.off),
            .field => |f| {
                const b = try self.baseBinding(f.base, ex.off);
                const layout = self.layouts.items[b.sid.?];
                for (layout.fields) |fld| {
                    if (std.mem.eql(u8, fld.name, f.name)) return fld.kind;
                }
                return self.err(ex.off, "struct has no field '{s}'", .{f.name});
            },
            .new_ => return .ptr,
            .delete_ => return .i32,
            .sizeof_ty => return .i32,
            .cast => |c| {
                const rt = try self.resolveType(c.ty, ex.off);
                if (rt.kind == .none) return .none;
                return rt.kind;
            },
            .cout_chain => return .i32,
            .endl => return self.err(ex.off, "'endl' outside a cout chain", .{}),
            .init_list => return self.err(ex.off, "brace lists only appear in declarations in v0.1", .{}),
        }
    }

    /// Resolve a method callee to its FuncRef (shared by genMethodCall/typeof).
    fn methodFuncRef(self: *Codegen, obj: par.Eid, name: []const u8, off: usize) CompileError!*FuncRef {
        const oe = self.p.exprs.items[obj];
        var sid: ?usize = null;
        if (oe.kind == .ident) {
            const b = self.lookup(oe.kind.ident) orelse {
                return self.err(oe.off, "unknown variable '{s}'", .{oe.kind.ident});
            };
            if (b.kind != .ptr or b.sid == null) {
                return self.err(oe.off, "method call needs a struct object", .{});
            }
            sid = b.sid;
        } else if (oe.kind == .this_) {
            _ = self.lookup("this") orelse {
                return self.err(oe.off, "'this' outside a method", .{});
            };
            sid = self.cur_sid;
        } else {
            return self.err(oe.off, "method call needs a named object in v0.1", .{});
        }
        const sdef = self.p.structs.items[sid.?];
        const full = try std.fmt.allocPrint(self.gpa, "{s}{s}_{s}", .{ sdef.qual, sdef.name, name });
        defer self.gpa.free(full);
        return self.findFunc(full) orelse {
            return self.err(off, "struct '{s}' has no method '{s}'", .{ sdef.name, name });
        };
    }

    fn genExpr(self: *Codegen, e: par.Eid) CompileError!Val {
        const ex = self.p.exprs.items[e];
        switch (ex.kind) {
            .int_lit => |raw| {
                const lit = try self.normIntLit(raw, ex.off);
                return .{ .txt = lit, .kind = .i32, .owned = false, .is_temp = false };
            },
            .float_lit => |raw| {
                return .{ .txt = raw, .kind = .f64, .owned = false, .is_temp = false };
            },
            .str_lit => |raw| {
                const inner = par.strInner(raw);
                const bytes = par.unescapeString(self.gpa, inner) catch {
                    return self.err(ex.off, "bad string escape", .{});
                };
                defer self.gpa.free(bytes);
                const id = try self.internString(bytes);
                const t = try self.newTemp();
                try self.addTemp(t, true);
                try self.emit("{s} = alloc 16", .{t});
                try self.emit("store {s} + 0, &str_{d} as ptr", .{ t, id });
                try self.emit("store {s} + 8, {d} as u64", .{ t, bytes.len });
                return .{ .txt = t, .kind = .slice, .owned = true, .is_temp = true };
            },
            .char_lit => |raw| {
                const inner = raw[1 .. raw.len - 1];
                const v = par.charValue(inner) catch {
                    return self.err(ex.off, "bad character literal", .{});
                };
                const lit = try std.fmt.allocPrint(self.gpa, "{d}", .{v});
                return .{ .txt = lit, .kind = .i32, .owned = false, .is_temp = false };
            },
            .bool_lit => |b| {
                return .{ .txt = if (b) "1" else "0", .kind = .boolean, .owned = false, .is_temp = false };
            },
            .null_lit => {
                return .{ .txt = "0", .kind = .ptr, .owned = false, .is_temp = false };
            },
            .ident => |n| {
                if (self.lookup(n)) |b| {
                    return .{ .txt = b.name, .kind = b.kind, .owned = false, .is_temp = false, .sid = b.sid };
                }
                // Implicit this-> for bare member names inside methods.
                if (self.cur_sid) |si| {
                    if (self.lookup("this") != null) {
                        const layout = self.layouts.items[si];
                        for (layout.fields, 0..) |fld, k| {
                            if (std.mem.eql(u8, fld.name, n)) {
                                const t = try self.newTemp();
                                try self.addTemp(t, false);
                                try self.emit("{s} = load this + {d} as {s}", .{ t, layout.offsets[k], fld.kind.saName() });
                                return .{ .txt = t, .kind = fld.kind, .owned = false, .is_temp = true };
                            }
                        }
                    }
                }
                return self.err(ex.off, "unknown variable '{s}'", .{n});
            },
            .this_ => {
                const b = self.lookup("this") orelse {
                    return self.err(ex.off, "'this' outside a method", .{});
                };
                return .{ .txt = "this", .kind = .ptr, .owned = false, .is_temp = false, .sid = b.sid };
            },
            .unary => |u| {
                if (u.op == .pre_inc or u.op == .pre_dec or u.op == .post_inc or u.op == .post_dec) {
                    return self.genIncDec(u.x, u.op, ex.off, true);
                }
                const x = try self.genExpr(u.x);
                switch (u.op) {
                    .neg => {
                        if (x.kind == .f64) {
                            const t = try self.newTemp();
                            try self.addTemp(t, false);
                            try self.emit("{s} = fsub 0.0, {s}", .{ t, x.txt });
                            try self.killVal(x);
                            return .{ .txt = t, .kind = .f64, .owned = false, .is_temp = true };
                        }
                        if (!x.kind.isInt()) {
                            return self.err(ex.off, "cannot negate this value (need a number)", .{});
                        }
                        const t = try self.newTemp();
                        try self.addTemp(t, false);
                        try self.emit("{s} = sub 0, {s}", .{ t, x.txt });
                        try self.killVal(x);
                        return .{ .txt = t, .kind = x.kind, .owned = false, .is_temp = true };
                    },
                    .not => {
                        const xc = try self.conv(x, .boolean, ex.off);
                        const t = try self.newTemp();
                        try self.addTemp(t, false);
                        try self.emit("{s} = eq {s}, 0", .{ t, xc.txt });
                        try self.killVal(xc);
                        return .{ .txt = t, .kind = .boolean, .owned = false, .is_temp = true };
                    },
                    .bnot => {
                        if (!x.kind.isInt()) {
                            return self.err(ex.off, "cannot bits-flip this value (need an integer)", .{});
                        }
                        const t = try self.newTemp();
                        try self.addTemp(t, false);
                        try self.emit("{s} = xor {s}, -1", .{ t, x.txt });
                        try self.killVal(x);
                        return .{ .txt = t, .kind = x.kind, .owned = false, .is_temp = true };
                    },
                    .deref => {
                        if (x.kind != .ptr) {
                            return self.err(ex.off, "cannot dereference a non-pointer", .{});
                        }
                        const t = try self.newTemp();
                        try self.addTemp(t, false);
                        try self.emit("{s} = load {s} + 0 as i32", .{ t, x.txt });
                        try self.killVal(x);
                        return .{ .txt = t, .kind = .i32, .owned = false, .is_temp = true };
                    },
                    .addrof => {
                        // &x on a local: SA names are addressable; pass through.
                        // (Only meaningful for call args like &lenp.)
                        return x;
                    },
                    else => return self.err(ex.off, "internal: bad unary", .{}),
                }
            },
            .binary => |b| {
                if (b.op == .assign or isAssignOpLocal(b.op)) {
                    return try self.genAssignOp(ex.off, b.l, b.op, b.r);
                }
                const l = try self.genExpr(b.l);
                const r = try self.genExpr(b.r);
                if (b.op == .log_and or b.op == .log_or) {
                    // Logical ops need 0/1 operands: convert truthiness first.
                    const lb = try self.conv(l, .boolean, self.p.exprs.items[b.l].off);
                    const rb = try self.conv(r, .boolean, self.p.exprs.items[b.r].off);
                    const t = try self.newTemp();
                    try self.addTemp(t, false);
                    try self.emitBin(t, b.op, lb.txt, .boolean, rb.txt, .boolean, ex.off);
                    try self.killVal(lb);
                    try self.killVal(rb);
                    return .{ .txt = t, .kind = .boolean, .owned = false, .is_temp = true };
                }
                // Usual arithmetic conversions: f64 wins, else i64 wins.
                var want = l.kind;
                if (r.kind == .f64 or l.kind == .f64) want = .f64 else if (r.kind == .i64 or l.kind == .i64) want = .i64;
                const is_cmp = b.op == .lt or b.op == .le or b.op == .gt or b.op == .ge or b.op == .eq or b.op == .ne;
                const lc = try self.conv(l, want, self.p.exprs.items[b.l].off);
                const rc = try self.conv(r, want, self.p.exprs.items[b.r].off);
                const t = try self.newTemp();
                try self.addTemp(t, false);
                try self.emitBin(t, b.op, lc.txt, want, rc.txt, want, ex.off);
                try self.killVal(lc);
                try self.killVal(rc);
                const rk: VKind = if (is_cmp) (if (want == .f64) .boolean else .boolean) else want;
                return .{ .txt = t, .kind = rk, .owned = false, .is_temp = true };
            },
            .ternary => |tr| {
                const tk = try self.typeofExpr(tr.t);
                const fk = try self.typeofExpr(tr.f);
                const chv = try self.condVal(tr.c);
                const l_then = try self.newLabel("tern");
                const l_else = try self.newLabel("tere");
                const l_merge = try self.newLabel("term");
                if (tk == .none and fk == .none) {
                    // Both arms void: evaluate each inside its branch.
                    try self.emit("br {s} -> {s}, {s}", .{ chv.txt, l_then, l_else });
                    try self.emitLabel(l_then);
                    const tv0 = try self.genExpr(tr.t);
                    try self.killVal(tv0);
                    try self.emit("jmp {s}", .{l_merge});
                    try self.emitLabel(l_else);
                    const fv0 = try self.genExpr(tr.f);
                    try self.killVal(fv0);
                    try self.emit("jmp {s}", .{l_merge});
                    try self.emitLabel(l_merge);
                    return .{ .txt = "0", .kind = .i32, .owned = false, .is_temp = false };
                }
                if (tk == .none or fk == .none) {
                    return self.err(ex.off, "ternary arms have mismatched types in v0.1", .{});
                }
                const want = self.unifyKinds(tk, fk, ex.off) catch {
                    return self.err(ex.off, "ternary arms have mismatched types in v0.1", .{});
                };
                if (want != .ptr and want != .slice and !want.isScalar()) {
                    return self.err(ex.off, "ternary supports scalars and pointers in v0.1", .{});
                }
                const res = try self.newHidden("tr");
                const zero: []const u8 = if (want == .f64) "0.0" else "0";
                try self.emit("{s} = {s}", .{ res, zero });
                _ = try self.addBinding(res, want, null, true);
                const res_idx = self.bindings.items.len - 1;
                try self.emit("br {s} -> {s}, {s}", .{ chv.txt, l_then, l_else });
                try self.emitLabel(l_then);
                {
                    const tv0 = try self.genExpr(tr.t);
                    const tv = try self.conv(tv0, want, self.p.exprs.items[tr.t].off);
                    try self.assignTo(.{ .local = res_idx }, tv, ex.off);
                }
                try self.emit("jmp {s}", .{l_merge});
                try self.emitLabel(l_else);
                {
                    const fv0 = try self.genExpr(tr.f);
                    const fv = try self.conv(fv0, want, self.p.exprs.items[tr.f].off);
                    try self.assignTo(.{ .local = res_idx }, fv, ex.off);
                }
                try self.emit("jmp {s}", .{l_merge});
                try self.emitLabel(l_merge);
                return .{ .txt = res, .kind = want, .owned = false, .is_temp = false };
            },
            .call => |c| {
                return self.genCall(c.callee, c.args, ex.off);
            },
            .method_call => |m| {
                return self.genMethodCall(m.obj, m.arrow, m.name, m.args, ex.off);
            },
            .index => |ix| {
                const addr = try self.genIndexAddr(ix.base, ix.idx, ex.off);
                const kind = try self.indexElemKind(ix.base, ex.off);
                const t = try self.newTemp();
                try self.addTemp(t, false);
                try self.emit("{s} = load {s} + 0 as {s}", .{ t, addr, kind.saName() });
                return .{ .txt = t, .kind = kind, .owned = false, .is_temp = true };
            },
            .field => |f| {
                const b = try self.baseBinding(f.base, ex.off);
                const layout = self.layouts.items[b.sid.?];
                for (layout.fields, 0..) |fld, k| {
                    if (std.mem.eql(u8, fld.name, f.name)) {
                        const t = try self.newTemp();
                        try self.addTemp(t, false);
                        try self.emit("{s} = load {s} + {d} as {s}", .{ t, b.name, layout.offsets[k], fld.kind.saName() });
                        return .{ .txt = t, .kind = fld.kind, .owned = false, .is_temp = true };
                    }
                }
                return self.err(ex.off, "struct has no field '{s}'", .{f.name});
            },
            .new_ => |n| {
                var rt = try self.resolveType(n.ty, ex.off);
                if (rt.kind == .none) {
                    return self.err(ex.off, "cannot allocate void", .{});
                }
                if (n.array_len != null) {
                    return self.err(ex.off, "new[] with runtime length is not supported in v0.1 (use fixed arrays T[N])", .{});
                }
                if (rt.kind == .ptr and rt.sid != null) {
                    const layout = self.layouts.items[rt.sid.?];
                    if (n.args.len != 0) {
                        return self.err(ex.off, "new with constructor arguments is not supported in v0.1", .{});
                    }
                    const t = try self.newTemp();
                    try self.addTemp(t, true);
                    try self.emit("{s} = alloc {d}", .{ t, layout.size });
                    const sdef = self.p.structs.items[rt.sid.?];
                    const ctor_name = std.fmt.allocPrint(self.gpa, "{s}{s}_ctor", .{ sdef.qual, sdef.name }) catch return error.CodegenError;
                    defer self.gpa.free(ctor_name);
                    if (self.findFunc(ctor_name)) |_| {
                        try self.emit("call @{s}({s})", .{ ctor_name, t });
                    } else {
                        try self.zeroFillStruct(t, layout);
                    }
                    return .{ .txt = t, .kind = .ptr, .owned = true, .is_temp = true, .sid = rt.sid };
                }
                if (!rt.kind.isScalar() and rt.kind != .ptr) {
                    return self.err(ex.off, "cannot allocate {s} with new in v0.1", .{@tagName(rt.kind)});
                }
                const esz = primSize(rt.kind);
                const t = try self.newTemp();
                try self.addTemp(t, true);
                try self.emit("{s} = alloc {d}", .{ t, esz });
                return .{ .txt = t, .kind = .ptr, .owned = true, .is_temp = true };
            },
            .delete_ => |x| {
                const v = try self.genExpr(x);
                try self.killVal(v);
                // Named bindings stay owned until scope end (use-after-delete
                // is not diagnosed in v0.1).
                return .{ .txt = "0", .kind = .i32, .owned = false, .is_temp = false };
            },
            .sizeof_ty => |ty| {
                const rt = try self.resolveType(ty, ex.off);
                const sz: usize = if (rt.kind == .ptr and rt.sid != null)
                    self.layouts.items[rt.sid.?].size
                else if (rt.kind == .none)
                    return self.err(ex.off, "sizeof(void)", .{})
                else
                    primSize(rt.kind);
                const lit = try std.fmt.allocPrint(self.gpa, "{d}", .{sz});
                return .{ .txt = lit, .kind = .i32, .owned = false, .is_temp = false };
            },
            .cast => |c| {
                const x = try self.genExpr(c.x);
                const rt = try self.resolveType(c.ty, ex.off);
                if (rt.kind == .none) {
                    try self.killVal(x);
                    return .{ .txt = "0", .kind = .i32, .owned = false, .is_temp = false };
                }
                // int<->ptr reinterpretation (explicit cast only).
                if ((x.kind.isScalar() or x.kind == .boolean) and rt.kind == .ptr) {
                    try self.killVal(x);
                    return .{ .txt = x.txt, .kind = .ptr, .owned = false, .is_temp = x.is_temp };
                }
                if (x.kind == .ptr and rt.kind.isScalar()) {
                    try self.killVal(x);
                    return .{ .txt = x.txt, .kind = rt.kind, .owned = false, .is_temp = x.is_temp };
                }
                return self.conv(x, rt.kind, ex.off);
            },
            .cout_chain => |ops| {
                try self.genCout(ops, ex.off);
                return .{ .txt = "0", .kind = .i32, .owned = false, .is_temp = false };
            },
            .endl => {
                return self.err(ex.off, "'endl' outside a cout chain", .{});
            },
            .init_list => {
                return self.err(ex.off, "brace lists only appear in declarations in v0.1", .{});
            },
        }
    }

    fn genCall(self: *Codegen, callee: par.Eid, args: []par.Eid, off: usize) CompileError!Val {
        const ce = self.p.exprs.items[callee];
        if (ce.kind != .ident) {
            return self.err(ce.off, "indirect calls are not supported in v0.1", .{});
        }
        // `A::f` → `A_f` ( SA names never contain `::` ).
        var cname = ce.kind.ident;
        var owned_name = false;
        if (std.mem.indexOf(u8, cname, "::") != null) {
            const buf = try self.gpa.dupe(u8, cname);
            for (buf) |*ch| {
                if (ch.* == ':') ch.* = '_';
            }
            // Collapse the doubled underscore from `::`.
            var w: usize = 0;
            var i: usize = 0;
            while (i < buf.len) {
                if (buf[i] == '_' and i + 1 < buf.len and buf[i + 1] == '_') {
                    buf[w] = '_';
                    w += 1;
                    i += 2;
                } else {
                    buf[w] = buf[i];
                    w += 1;
                    i += 1;
                }
            }
            cname = buf[0..w];
            owned_name = true;
        }
        defer if (owned_name) self.gpa.free(cname);
        const ref = self.findFunc(cname) orelse {
            return self.err(ce.off, "unknown function '{s}'", .{ce.kind.ident});
        };
        const want_this = (ref.is_method and !ref.is_static);
        if (want_this) {
            return self.err(ce.off, "method '{s}' needs an object (write obj.{s}(...))", .{ cname, ce.kind.ident });
        }
        if (args.len != ref.params.len) {
            return self.err(off, "function '{s}' takes {d} arguments, got {d}", .{ ref.full, ref.params.len, args.len });
        }
        var argtxt: std.array_list.Managed(u8) = .init(self.gpa);
        defer argtxt.deinit();
        {
            var aw: std.Io.Writer.Allocating = .init(self.gpa);
            defer aw.deinit();
            const w: *std.Io.Writer = &aw.writer;
            for (args, 0..) |a, k| {
                const ae = self.p.exprs.items[a];
                if (ae.kind == .cout_chain) {
                    return self.err(ae.off, "cout chain cannot be a call argument", .{});
                }
                const v = try self.genExpr(a);
                const cv = try self.conv(v, ref.params[k].kind, ae.off);
                if (k != 0) (w.writeAll(", ")) catch return error.CodegenError;
                (w.writeAll(cv.txt)) catch return error.CodegenError;
                // NOTE: no killVal here — the call is emitted below; owned
                // temps stay live until scope end (calls borrow operands).
            }
            try argtxt.appendSlice(aw.written());
        }
        if (ref.ret_kind == .none) {
            try self.emit("call @{s}({s})", .{ ref.full, argtxt.items });
            return .{ .txt = "0", .kind = .i32, .owned = false, .is_temp = false };
        }
        const t = try self.newTemp();
        try self.addTemp(t, true);
        try self.emit("{s} = call @{s}({s})", .{ t, ref.full, argtxt.items });
        return .{ .txt = t, .kind = ref.ret_kind, .owned = true, .is_temp = true, .sid = ref.ret_sid };
    }

    fn genMethodCall(self: *Codegen, obj: par.Eid, _: bool, name: []const u8, args: []par.Eid, off: usize) CompileError!Val {
        const oe = self.p.exprs.items[obj];
        var obj_txt: []const u8 = undefined;
        var sid: ?usize = null;
        if (oe.kind == .ident) {
            const b = self.lookup(oe.kind.ident) orelse {
                return self.err(oe.off, "unknown variable '{s}'", .{oe.kind.ident});
            };
            if (b.kind != .ptr or b.sid == null) {
                return self.err(oe.off, "method call needs a struct object", .{});
            }
            obj_txt = b.name;
            sid = b.sid;
        } else if (oe.kind == .this_) {
            _ = self.lookup("this") orelse {
                return self.err(oe.off, "'this' outside a method", .{});
            };
            obj_txt = "this";
            sid = self.cur_sid;
        } else {
            return self.err(oe.off, "method call needs a named object in v0.1", .{});
        }
        const sdef = self.p.structs.items[sid.?];
        const full = try std.fmt.allocPrint(self.gpa, "{s}{s}_{s}", .{ sdef.qual, sdef.name, name });
        defer self.gpa.free(full);
        const ref = self.findFunc(full) orelse {
            return self.err(off, "struct '{s}' has no method '{s}'", .{ sdef.name, name });
        };
        const this_count: usize = if (ref.is_method and !ref.is_static) 1 else 0;
        if (args.len + this_count != ref.params.len + this_count or args.len != ref.params.len) {
            return self.err(off, "method '{s}' takes {d} arguments, got {d}", .{ name, ref.params.len, args.len });
        }
        var argtxt: std.array_list.Managed(u8) = .init(self.gpa);
        defer argtxt.deinit();
        {
            var aw: std.Io.Writer.Allocating = .init(self.gpa);
            defer aw.deinit();
            const w: *std.Io.Writer = &aw.writer;
            if (this_count == 1) {
                (w.writeAll(obj_txt)) catch return error.CodegenError;
            }
            for (args, 0..) |a, k| {
                const ae = self.p.exprs.items[a];
                const v = try self.genExpr(a);
                const cv = try self.conv(v, ref.params[k].kind, ae.off);
                if (k != 0 or this_count == 1) (w.writeAll(", ")) catch return error.CodegenError;
                (w.writeAll(cv.txt)) catch return error.CodegenError;
                // NOTE: no killVal here — the call is emitted below; owned
                // temps stay live until scope end (calls borrow operands).
            }
            try argtxt.appendSlice(aw.written());
        }
        if (ref.ret_kind == .none) {
            try self.emit("call @{s}({s})", .{ ref.full, argtxt.items });
            return .{ .txt = "0", .kind = .i32, .owned = false, .is_temp = false };
        }
        const t = try self.newTemp();
        try self.addTemp(t, true);
        try self.emit("{s} = call @{s}({s})", .{ t, ref.full, argtxt.items });
        return .{ .txt = t, .kind = ref.ret_kind, .owned = true, .is_temp = true, .sid = ref.ret_sid };
    }

    /// Print a signed integer value (any int kind) via sa_std fmt+print.
    fn printInt(self: *Codegen, vtxt: []const u8, vkind: VKind) CompileError!void {
        self.need_print = true;
        self.need_fmt = true;
        const a = try self.newTemp();
        try self.addTemp(a, false);
        if (vkind == .i64) {
            try self.emit("{s} = add {s}, 0", .{ a, vtxt });
        } else {
            try self.emit("{s} = sext {s} as i64", .{ a, vtxt });
        }
        const buf = try self.newTemp();
        try self.addTemp(buf, true);
        try self.emit("{s} = alloc 64", .{buf});
        const lenp = try self.newTemp();
        try self.addTemp(lenp, true);
        try self.emit("{s} = alloc 8", .{lenp});
        const code = try self.newTemp();
        try self.addTemp(code, true);
        try self.emit("{s} = call @sa_fmt_i64_into({s}, 10, {s}, 64, &{s})", .{ code, a, buf, lenp });
        const n = try self.newTemp();
        try self.addTemp(n, false);
        try self.emit("{s} = load {s} + 0 as u64", .{ n, lenp });
        const sl = try self.newTemp();
        try self.addTemp(sl, true);
        try self.emit("{s} = alloc 16", .{sl});
        try self.emit("store {s} + 0, {s} as ptr", .{ sl, buf });
        try self.emit("store {s} + 8, {s} as u64", .{ sl, n });
        const gp = try self.newTemp();
        try self.addTemp(gp, false);
        try self.emit("{s} = load {s} + 0 as ptr", .{ gp, sl });
        const gl = try self.newTemp();
        try self.addTemp(gl, false);
        try self.emit("{s} = load {s} + 8 as u64", .{ gl, sl });
        try self.emit("call @sa_print_bytes(&{s}, {s})", .{ gp, gl });
    }

    /// Print the string slice behind pointer register `s`.
    fn printSlice(self: *Codegen, s: []const u8) CompileError!void {
        self.need_print = true;
        const gp = try self.newTemp();
        try self.addTemp(gp, false);
        try self.emit("{s} = load {s} + 0 as ptr", .{ gp, s });
        const gl = try self.newTemp();
        try self.addTemp(gl, false);
        try self.emit("{s} = load {s} + 8 as u64", .{ gl, s });
        try self.emit("call @sa_print_bytes(&{s}, {s})", .{ gp, gl });
    }

    fn printNewline(self: *Codegen) CompileError!void {
        const id = try self.internString("\n");
        const t = try self.newTemp();
        try self.addTemp(t, true);
        try self.emit("{s} = alloc 16", .{t});
        try self.emit("store {s} + 0, &str_{d} as ptr", .{ t, id });
        try self.emit("store {s} + 8, 1 as u64", .{t});
        try self.printSlice(t);
    }

    fn genCout(self: *Codegen, ops: []par.Eid, _: usize) CompileError!void {
        if (ops.len == 0) return;
        // ops[0] is the cout/cerr ident itself.
        if (ops[0] >= self.p.exprs.items.len) return;
        const first = self.p.exprs.items[ops[0]];
        if (first.kind == .ident) {
            if (self.lookup(first.kind.ident) != null) {
                _ = self.diag.fail(first.off, "variable named '{s}' collides with cout in v0.1", .{first.kind.ident});
                return error.CodegenError;
            }
        }
        for (ops[1..]) |o| {
            const oe = self.p.exprs.items[o];
            if (oe.kind == .endl) {
                try self.printNewline();
                continue;
            }
            const v = try self.genExpr(o);
            switch (v.kind) {
                .slice => {
                    try self.printSlice(v.txt);
                    try self.killVal(v);
                },
                .i32, .i64, .boolean => {
                    try self.printInt(v.txt, v.kind);
                    try self.killVal(v);
                },
                .f64 => {
                    return self.err(oe.off, "cout of floating-point values is not supported in v0.1", .{});
                },
                .ptr => {
                    return self.err(oe.off, "cout of raw pointers is not supported in v0.1", .{});
                },
                .none => {
                    try self.killVal(v);
                },
            }
        }
    }

    fn internString(self: *Codegen, bytes: []const u8) CompileError!usize {
        if (std.mem.indexOfScalar(u8, bytes, 0) != null) {
            return self.err(0, "NUL bytes in strings are not supported in v0.1", .{});
        }
        for (self.str_consts.items) |sc| {
            if (std.mem.eql(u8, sc.bytes, bytes)) return sc.id;
        }
        const id = self.str_consts.items.len;
        const owned = try self.gpa.dupe(u8, bytes);
        try self.str_consts.append(.{ .bytes = owned, .id = id });
        return id;
    }

    /// Normalize an int literal to decimal text.
    fn normIntLit(self: *Codegen, raw: []const u8, _: usize) CompileError![]const u8 {
        const v = par.parseIntLit(raw) catch {
            // Too big for i64 or exotic: pass through raw (best effort).
            return raw;
        };
        return std.fmt.allocPrint(self.gpa, "{d}", .{v}) catch return error.CodegenError;
    }
};