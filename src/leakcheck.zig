const std = @import("std");
const lex = @import("lexer.zig");
const par = @import("parser.zig");

pub const CompileError = lex.CompileError;
pub const Diag = lex.Diag;

/// Compile-time memory-leak checking for the C++ subset.
///
/// Theory: leak checking is CFG reachability + alloc/free pairing. Every
/// `new` creates an obligation; the obligation dies with `delete`, moves
/// with the pointer (alias sets), transfers out with `return`, and must be
/// dead on every path that reaches a function exit. Anything else is a
/// definite leak and fails compilation (no SA is emitted).
///
/// Scope (v0.1, intraprocedural):
/// - tracks named locals/params, `this->field` and `obj.field` cells;
/// - alias sets: `q = p` unions the two cells, `delete` frees the set;
/// - branches/forks are walked per path and merged (live-on-any-path);
/// - loops run two passes (loop-carried state converges for our patterns);
/// - `new[]`/`delete[]` pairing is enforced; temps from `new` that are
///   never bound are leaks; `return p` transfers ownership out.
/// Out of scope: exceptions (rejected by the parser), interprocedural
/// callee behavior (unknown calls borrow), correlated branch conditions
/// (may report a leak where none exists — documented limitation).
const CellKind = enum { empty, live, freed };

const Cell = struct {
    name: []const u8,
    state: CellKind = .empty,
    site: usize = 0, // source offset of the allocating `new`
    is_array: bool = false,
    set: u32 = 0, // alias-set id; 0 = none
    depth: usize = 0,
    is_param: bool = false, // caller-owned; callee may free, need not free
    null_init: bool = false, // last assigned from nullptr (delete = no-op)
};

pub const LeakCheck = struct {
    gpa: std.mem.Allocator,
    p: *par.Parser,
    diag: *Diag,
    cells: std.array_list.Managed(Cell),
    next_set: u32 = 1,
    cur_func: []const u8 = "",
    scope_depth: usize = 0,
    loop_depth: usize = 0,

    pub fn init(gpa: std.mem.Allocator, parser: *par.Parser, diag: *Diag) LeakCheck {
        return .{
            .gpa = gpa,
            .p = parser,
            .diag = diag,
            .cells = .init(gpa),
        };
    }

    pub fn deinit(self: *LeakCheck) void {
        self.cells.deinit();
    }

    fn fail(self: *LeakCheck, off: usize, comptime fmt: []const u8, args: anytype) CompileError {
        self.diag.fail(off, fmt, args);
        return error.LeakError;
    }

    pub fn checkUnit(self: *LeakCheck) CompileError!void {
        for (self.p.funcs.items) |*f| {
            if (f.is_dtor) continue;
            try self.checkFunc(f);
        }
    }

    fn checkFunc(self: *LeakCheck, f: *par.Func) CompileError!void {
        self.cells.clearRetainingCapacity();
        self.next_set = 1;
        self.scope_depth = 1;
        self.cur_func = std.fmt.allocPrint(self.gpa, "{s}{s}", .{ f.qual, f.name }) catch f.name;
        // Parameters start untracked (caller-owned): the callee may free
        // them but is never obliged to.
        for (f.params) |pm| {
            try self.cells.append(.{ .name = pm.name, .depth = 1, .is_param = true });
        }
        if (f.is_method and !f.is_static) {
            try self.cells.append(.{ .name = "this", .depth = 1, .is_param = true });
        }
        var terminal = false;
        var i: usize = 0;
        while (i < f.body.len) : (i += 1) {
            if (try self.walkStmt(f.body[i])) {
                terminal = true;
                break;
            }
        }
        // Fall-off the end: every live cell is a leak. (A terminal tail
        // was already checked at its own exit point.)
        if (!terminal) try self.checkLiveAtExit(f.off);
    }

    fn findCell(self: *LeakCheck, name: []const u8) ?*Cell {
        var i = self.cells.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.cells.items[i].name, name)) return &self.cells.items[i];
        }
        return null;
    }

    fn ensureCell(self: *LeakCheck, name: []const u8) CompileError!*Cell {
        if (self.findCell(name)) |c| {
            if (c.depth == self.scope_depth) return c;
            // Shadowed across depths: fresh cell, innermost wins lookups.
        }
        try self.cells.append(.{ .name = name, .depth = self.scope_depth });
        return &self.cells.items[self.cells.items.len - 1];
    }

    fn isAssignOp(op: par.BinOp) bool {
        return switch (op) {
            .assign, .add_assign, .sub_assign, .mul_assign, .div_assign, .rem_assign, .shl_assign, .shr_assign, .band_assign, .bor_assign, .bxor_assign => true,
            else => false,
        };
    }

    fn allocCell(self: *LeakCheck, name: []const u8, site: usize, is_array: bool) CompileError!void {
        const c = try self.ensureCell(name);
        if (c.state == .live) {
            return self.fail(site, "leak: '{s}' already owns an allocation (line {d}); overwritten without delete (function '{s}')", .{ name, Diag.lineOf(self.p.source, c.site), self.cur_func });
        }
        c.state = .live;
        c.site = site;
        c.is_array = is_array;
        c.set = self.next_set;
        self.next_set += 1;
        c.null_init = false;
    }

    fn freeCell(self: *LeakCheck, name: []const u8, is_array: bool, off: usize) CompileError!void {
        const c = self.findCell(name) orelse {
            return self.fail(off, "delete of untracked pointer '{s}' (function '{s}')", .{ name, self.cur_func });
        };
        if (c.state == .empty) {
            // Unknown origin (factory result, param, nullptr): nothing
            // tracked, so nothing to prove wrong. Mark freed to catch a
            // later second delete against this same cell.
            c.state = .freed;
            return;
        }
        if (c.state == .freed) {
            return self.fail(off, "double delete of '{s}' (allocated line {d}, function '{s}')", .{ name, Diag.lineOf(self.p.source, c.site), self.cur_func });
        }
        if (c.is_array != is_array) {
            const want = if (c.is_array) "delete[]" else "delete";
            const got = if (is_array) "delete[]" else "delete";
            return self.fail(off, "mismatched deallocation of '{s}': allocated with {s}, freed with {s} (function '{s}')", .{ name, want, got, self.cur_func });
        }
        // Free the whole alias set.
        const set = c.set;
        for (self.cells.items) |*m| {
            if (m.state == .live and m.set == set) {
                m.state = .freed;
            }
        }
    }

    fn checkLiveAtExit(self: *LeakCheck, off: usize) CompileError!void {
        for (self.cells.items) |*c| {
            if (c.state == .live) {
                return self.fail(off, "leak: allocation of '{s}' at line {d} not freed on all paths (function '{s}')", .{ c.name, Diag.lineOf(self.p.source, c.site), self.cur_func });
            }
        }
    }

    /// Canonical tracked name for an lvalue, or null when untracked.
    fn lvalueName(self: *LeakCheck, e: par.Eid) CompileError!?[]const u8 {
        const ex = self.p.exprs.items[e];
        switch (ex.kind) {
            .ident => |n| return n,
            .field => |f| {
                const be = self.p.exprs.items[f.base];
                if (be.kind == .ident) {
                    return try std.fmt.allocPrint(self.gpa, "{s}.{s}", .{ be.kind.ident, f.name });
                }
                if (be.kind == .this_) {
                    return try std.fmt.allocPrint(self.gpa, "this.{s}", .{f.name});
                }
                return null;
            },
            .unary => |u| {
                if (u.op != .deref) return null;
                const ie = self.p.exprs.items[u.x];
                if (ie.kind == .ident) {
                    return try std.fmt.allocPrint(self.gpa, "*{s}", .{ie.kind.ident});
                }
                return null;
            },
            else => return null,
        }
    }

    /// If evaluating `e` allocates (a `new` rvalue), return its site/flags.
    /// Applies `delete` side effects found in expression position.
    fn walkExprAlloc(self: *LeakCheck, e: par.Eid) CompileError!?struct { site: usize, is_array: bool } {
        const ex = self.p.exprs.items[e];
        switch (ex.kind) {
            .new_ => |n| {
                // Walk args first (nested new/delete inside).
                for (n.args) |a| {
                    _ = try self.walkExprAlloc(a);
                }
                if (n.array_len) |alen| {
                    _ = try self.walkExprAlloc(alen);
                }
                return .{ .site = ex.off, .is_array = n.array_len != null };
            },
            .delete_ => |d| {
                const nm = try self.lvalueName(d.x);
                if (nm) |n| {
                    try self.freeCell(n, d.is_array, ex.off);
                } else {
                    // Deleting a computed address: walk operand, assume freed.
                    _ = try self.walkExprAlloc(d.x);
                }
                return null;
            },
            .binary => |b| {
                if (b.op == .assign or isAssignOp(b.op)) {
                    _ = try self.walkExprAlloc(b.r);
                    _ = try self.walkExprAlloc(b.l);
                    return null;
                }
                _ = try self.walkExprAlloc(b.l);
                _ = try self.walkExprAlloc(b.r);
                return null;
            },
            .unary => |u| {
                _ = try self.walkExprAlloc(u.x);
                return null;
            },
            .ternary => |tr| {
                _ = try self.walkExprAlloc(tr.c);
                const a = try self.walkExprAlloc(tr.t);
                const c = try self.walkExprAlloc(tr.f);
                // Either arm may run: report an allocation on either side.
                if (a != null) return a;
                return c;
            },
            .call => |c| {
                for (c.args) |a| {
                    // A `new` passed straight to a call is unbound: without
                    // interprocedural proof the callee frees it, it leaks.
                    const sub = self.p.exprs.items[a];
                    if (sub.kind == .new_) {
                        return self.fail(sub.off, "leak: `new` at line {d} passed to a call without binding (function '{s}')", .{ Diag.lineOf(self.p.source, sub.off), self.cur_func });
                    }
                    _ = try self.walkExprAlloc(a);
                }
                return null;
            },
            .method_call => |m| {
                _ = try self.walkExprAlloc(m.obj);
                for (m.args) |a| {
                    const sub = self.p.exprs.items[a];
                    if (sub.kind == .new_) {
                        return self.fail(sub.off, "leak: `new` at line {d} passed to a call without binding (function '{s}')", .{ Diag.lineOf(self.p.source, sub.off), self.cur_func });
                    }
                    _ = try self.walkExprAlloc(a);
                }
                return null;
            },
            .cout_chain => |ops| {
                for (ops) |o| {
                    _ = try self.walkExprAlloc(o);
                }
                return null;
            },
            .index => |ix| {
                _ = try self.walkExprAlloc(ix.base);
                _ = try self.walkExprAlloc(ix.idx);
                return null;
            },
            .field => {
                return null;
            },
            .cast => |c| {
                _ = try self.walkExprAlloc(c.x);
                return null;
            },
            .sizeof_ty => return null,
            .init_list => |items| {
                for (items) |it| {
                    _ = try self.walkExprAlloc(it);
                }
                return null;
            },
            .int_lit, .float_lit, .str_lit, .char_lit, .bool_lit, .null_lit, .ident, .this_, .endl => return null,
        }
    }

    fn mergeCells(self: *LeakCheck, then_cells: []Cell) CompileError!void {
        // Index current (else-path) cells by name.
        for (then_cells) |tc| {
            var found = false;
            for (self.cells.items) |*ec| {
                if (!std.mem.eql(u8, ec.name, tc.name)) continue;
                found = true;
                if (tc.state == .live or ec.state == .live) {
                    // Live on either path: keep a live representative.
                    if (tc.state == .live and ec.state != .live) ec.* = tc;
                } else if (tc.state == .freed or ec.state == .freed) {
                    ec.state = .freed;
                } else {
                    if (tc.null_init) ec.null_init = true;
                }
                break;
            }
            if (!found) {
                // Created on the then-path only: carries over.
                try self.cells.append(tc);
            }
        }
        // Cells created on the else-path only are already present.
    }

    /// Walk one statement. Returns true when control cannot continue
    /// past it on this path (return / infinite loop without break).
    fn walkStmt(self: *LeakCheck, id: par.Sid) CompileError!bool {
        const st = self.p.stmts.items[id];
        switch (st.kind) {
            .decl => |d| {
                if (d.array_len != null) {
                    // Fixed arrays hold no heap cells in v0.1, but their
                    // initializers may still hide a `new`.
                    if (d.has_init) {
                        const ie = self.p.exprs.items[d.init];
                        if (ie.kind == .init_list) {
                            for (ie.kind.init_list) |it| {
                                _ = try self.walkExprAlloc(it);
                            }
                        }
                    }
                    return false;
                }
                if (!d.has_init) {
                    _ = try self.ensureCell(d.name);
                    return false;
                }
                const site = try self.walkExprAlloc(d.init);
                const c = try self.ensureCell(d.name);
                if (c.state == .live) {
                    return self.fail(st.off, "leak: '{s}' already owns an allocation (line {d}); redeclared without delete (function '{s}')", .{ d.name, Diag.lineOf(self.p.source, c.site), self.cur_func });
                }
                if (site) |sn| {
                    c.state = .live;
                    c.site = sn.site;
                    c.is_array = sn.is_array;
                    c.set = self.next_set;
                    self.next_set += 1;
                    c.null_init = false;
                } else {
                    // Initialized from something else: alias when it names a
                    // tracked live pointer, else empty.
                    const ie = self.p.exprs.items[d.init];
                    if (ie.kind == .ident) {
                        const s = self.findCell(ie.kind.ident);
                        if (s != null and s.?.state == .live) {
                            c.state = .live;
                            c.site = s.?.site;
                            c.is_array = s.?.is_array;
                            c.set = s.?.set;
                            c.null_init = false;
                            return false;
                        }
                    }
                    c.state = .empty;
                    c.null_init = ie.kind == .null_lit;
                    c.set = 0;
                }
                return false;
            },
            .expr_stmt => |e| {
                const ek = self.p.exprs.items[e].kind;
                if (ek == .binary) {
                    const b = self.p.exprs.items[e].kind.binary;
                    if (b.op == .assign or isAssignOp(b.op)) {
                        try self.walkAssign(b.op, b.l, b.r, st.off);
                        return false;
                    }
                }
                _ = try self.walkExprAlloc(e);
                return false;
            },
            .if_ => |ifs| {
                _ = try self.walkExprAlloc(ifs.cond);
                const fork = try self.gpa.dupe(Cell, self.cells.items);
                // Then-path.
                for (ifs.then_body) |s| {
                    if (try self.walkStmt(s)) break;
                }
                const then_cells = try self.gpa.dupe(Cell, self.cells.items);
                // Restore fork, walk else-path.
                self.cells.clearRetainingCapacity();
                try self.cells.appendSlice(fork);
                if (ifs.has_else) {
                    for (ifs.else_body) |s| {
                        if (try self.walkStmt(s)) break;
                    }
                }
                // Merge: live on either path stays live (conservative for
                // leaks; correlated conditions may over-report, documented).
                try self.mergeCells(then_cells);
                return false;
            },
            .while_ => |w| {
                try self.walkLoop(w.cond, w.body);
                return false;
            },
            .do_while => |d| {
                try self.walkLoop(d.cond, d.body);
                return false;
            },
            .for_ => |f| {
                for (f.init) |s| {
                    if (try self.walkStmt(s)) break;
                }
                if (f.has_cond) _ = try self.walkExprAlloc(f.cond);
                // Body twice for loop-carried state; step between passes.
                self.loop_depth += 1;
                _ = try self.walkBody(f.body);
                if (f.has_step) _ = try self.walkExprAlloc(f.step);
                _ = try self.walkBody(f.body);
                if (f.has_step) _ = try self.walkExprAlloc(f.step);
                self.loop_depth -= 1;
                return false;
            },
            .range_for => |r| {
                _ = try self.walkExprAlloc(r.iterable);
                _ = try self.ensureCell(r.var_name);
                self.loop_depth += 1;
                _ = try self.walkBody(r.body);
                _ = try self.walkBody(r.body);
                self.loop_depth -= 1;
                return false;
            },
            .switch_ => |s| {
                _ = try self.walkExprAlloc(s.scrutinee);
                // Fallthrough is sequential: walk cases in order, threading
                // one state; `break` jumps to the end (state carries).
                const outer_loops = self.loop_depth;
                var broken = false;
                for (s.cases) |c| {
                    if (c.value) |v| _ = try self.walkExprAlloc(v);
                    for (c.body) |b| {
                        const k = self.p.stmts.items[b].kind;
                        // A `break` for an enclosing loop is not ours.
                        if (k == .break_ and self.loop_depth == outer_loops) break;
                        if (try self.walkStmt(b)) {
                            broken = true;
                            break;
                        }
                    }
                    if (broken) break;
                }
                return false;
            },
            .return_ => |r| {
                if (r.has_value) {
                    const ve = self.p.exprs.items[r.value];
                    // `return p` transfers ownership out: exempt that cell.
                    var exempt: ?[]const u8 = null;
                    if (ve.kind == .ident) exempt = ve.kind.ident;
                    _ = try self.walkExprAlloc(r.value);
                    for (self.cells.items) |*c| {
                        if (c.state != .live) continue;
                        if (exempt != null and std.mem.eql(u8, c.name, exempt.?)) continue;
                        // Cells in the returned alias set also transfer out.
                        if (exempt) |en| {
                            const e = self.findCell(en);
                            if (e != null and c.set != 0 and c.set == e.?.set) continue;
                        }
                        return self.fail(st.off, "leak: '{s}' allocated at line {d} still live at return (function '{s}')", .{ c.name, Diag.lineOf(self.p.source, c.site), self.cur_func });
                    }
                    return true;
                }
                try self.checkLiveAtExit(st.off);
                return true;
            },
            .break_ => return true,
            .continue_ => return true,
            .block => |b| {
                const mark = self.cells.items.len;
                const saved_depth = self.scope_depth;
                self.scope_depth += 1;
                var terminal = false;
                for (b) |s| {
                    if (try self.walkStmt(s)) {
                        terminal = true;
                        break;
                    }
                }
                // Block-locals going out of scope live = leak.
                for (self.cells.items[mark..]) |*c| {
                    if (c.state == .live) {
                        return self.fail(st.off, "leak: '{s}' allocated at line {d} leaves scope without delete (function '{s}')", .{ c.name, Diag.lineOf(self.p.source, c.site), self.cur_func });
                    }
                }
                self.cells.shrinkRetainingCapacity(mark);
                self.scope_depth = saved_depth;
                return terminal;
            },
        }
    }

    fn walkBody(self: *LeakCheck, body: []par.Sid) CompileError!void {
        if (body.len == 0) return;
        const mark = self.cells.items.len;
        const saved_depth = self.scope_depth;
        self.scope_depth += 1;
        for (body) |s| {
            if (try self.walkStmt(s)) break;
        }
        for (self.cells.items[mark..]) |*c| {
            if (c.state == .live) {
                return self.fail(self.p.stmts.items[body[body.len - 1]].off, "leak: '{s}' leaves a loop body without delete (function '{s}')", .{ c.name, self.cur_func });
            }
        }
        self.cells.shrinkRetainingCapacity(mark);
        self.scope_depth = saved_depth;
    }

    fn walkLoop(self: *LeakCheck, cond: par.Eid, body: []par.Sid) CompileError!void {
        _ = try self.walkExprAlloc(cond);
        self.loop_depth += 1;
        _ = try self.walkBody(body);
        _ = try self.walkExprAlloc(cond);
        _ = try self.walkBody(body);
        self.loop_depth -= 1;
    }

    fn walkAssign(self: *LeakCheck, op: par.BinOp, target: par.Eid, value: par.Eid, off: usize) CompileError!void {
        const site = try self.walkExprAlloc(value);
        // Compound assignment keeps the target's allocation (e.g. `p += 1`
        // only bumps the pointer); only plain `=` replaces ownership.
        if (op != .assign) return;
        const nm = try self.lvalueName(target);
        if (nm == null) return;
        const name = nm.?;
        const ve = self.p.exprs.items[value];
        if (ve.kind == .ident and std.mem.eql(u8, ve.kind.ident, name)) return; // self-assign
        if (ve.kind == .ident) {
            // Pointer copy: union alias sets (after overwrite check).
            const d = try self.ensureCell(name);
            if (d.state == .live) {
                return self.fail(off, "leak: '{s}' already owns an allocation (line {d}); overwritten without delete (function '{s}')", .{ name, Diag.lineOf(self.p.source, d.site), self.cur_func });
            }
            const s = self.findCell(ve.kind.ident);
            if (s != null and s.?.state == .live) {
                d.state = .live;
                d.site = s.?.site;
                d.is_array = s.?.is_array;
                d.set = s.?.set;
                d.null_init = false;
            } else {
                d.state = .empty;
                d.null_init = s != null and s.?.null_init;
                d.set = 0;
            }
            return;
        }
        if (ve.kind == .null_lit) {
            const d = try self.ensureCell(name);
            if (d.state == .live) {
                return self.fail(off, "leak: '{s}' already owns an allocation (line {d}); overwritten without delete (function '{s}')", .{ name, Diag.lineOf(self.p.source, d.site), self.cur_func });
            }
            d.state = .empty;
            d.null_init = true;
            d.set = 0;
            return;
        }
        if (site) |sn| {
            try self.allocCell(name, sn.site, sn.is_array);
            return;
        }
        // Any other value: kills a live cell (overwrite) unless the value
        // came from the same cell family... conservative: assigning a
        // non-pointer value over a live pointer leaks it.
        const d = try self.ensureCell(name);
        if (d.state == .live) {
            // Scalar store into a live pointer slot: the old allocation is
            // unreachable afterwards.
            return self.fail(off, "leak: '{s}' already owns an allocation (line {d}); overwritten without delete (function '{s}')", .{ name, Diag.lineOf(self.p.source, d.site), self.cur_func });
        }
        d.state = .empty;
        d.null_init = false;
        d.set = 0;
    }
};

test "leakcheck accepts clean new/delete" {
    const gpa = std.testing.allocator;
    const src = "int main() { int* p = new int; *p = 1; delete p; return 0; }\n";
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const agpa = arena.allocator();
    var diag = Diag.init(agpa);
    var lx = lex.Lexer.init(src);
    const toks = try lx.tokenize(agpa, &diag);
    var parser = par.Parser.create(agpa, src, toks, &diag);
    defer parser.deinit();
    try parser.parseUnit();
    var lc = LeakCheck.init(agpa, &parser, &diag);
    defer lc.deinit();
    try lc.checkUnit();
}

test "leakcheck rejects missing delete" {
    const gpa = std.testing.allocator;
    const src = "int main() { int* p = new int; *p = 1; return 0; }\n";
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const agpa = arena.allocator();
    var diag = Diag.init(agpa);
    var lx = lex.Lexer.init(src);
    const toks = try lx.tokenize(agpa, &diag);
    var parser = par.Parser.create(agpa, src, toks, &diag);
    defer parser.deinit();
    try parser.parseUnit();
    var lc = LeakCheck.init(agpa, &parser, &diag);
    defer lc.deinit();
    const r = lc.checkUnit();
    try std.testing.expectError(error.LeakError, r);
}

test "leakcheck rejects early return with live allocation" {
    const gpa = std.testing.allocator;
    const src = "int f(int c) { int* p = new int; if (c) { return 1; } delete p; return 0; }\n";
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const agpa = arena.allocator();
    var diag = Diag.init(agpa);
    var lx = lex.Lexer.init(src);
    const toks = try lx.tokenize(agpa, &diag);
    var parser = par.Parser.create(agpa, src, toks, &diag);
    defer parser.deinit();
    try parser.parseUnit();
    var lc = LeakCheck.init(agpa, &parser, &diag);
    defer lc.deinit();
    const r = lc.checkUnit();
    try std.testing.expectError(error.LeakError, r);
}

test "leakcheck rejects overwrite of live pointer" {
    const gpa = std.testing.allocator;
    const src = "int main() { int* p = new int; p = new int; delete p; return 0; }\n";
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const agpa = arena.allocator();
    var diag = Diag.init(agpa);
    var lx = lex.Lexer.init(src);
    const toks = try lx.tokenize(agpa, &diag);
    var parser = par.Parser.create(agpa, src, toks, &diag);
    defer parser.deinit();
    try parser.parseUnit();
    var lc = LeakCheck.init(agpa, &parser, &diag);
    defer lc.deinit();
    const r = lc.checkUnit();
    try std.testing.expectError(error.LeakError, r);
}

test "leakcheck rejects double delete" {
    const gpa = std.testing.allocator;
    const src = "int main() { int* p = new int; delete p; delete p; return 0; }\n";
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const agpa = arena.allocator();
    var diag = Diag.init(agpa);
    var lx = lex.Lexer.init(src);
    const toks = try lx.tokenize(agpa, &diag);
    var parser = par.Parser.create(agpa, src, toks, &diag);
    defer parser.deinit();
    try parser.parseUnit();
    var lc = LeakCheck.init(agpa, &parser, &diag);
    defer lc.deinit();
    const r = lc.checkUnit();
    try std.testing.expectError(error.LeakError, r);
}

test "leakcheck rejects new-delete array mismatch" {
    const gpa = std.testing.allocator;
    const src = "int main() { int* p = new int[4]; delete p; return 0; }\n";
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const agpa = arena.allocator();
    var diag = Diag.init(agpa);
    var lx = lex.Lexer.init(src);
    const toks = try lx.tokenize(agpa, &diag);
    var parser = par.Parser.create(agpa, src, toks, &diag);
    defer parser.deinit();
    try parser.parseUnit();
    var lc = LeakCheck.init(agpa, &parser, &diag);
    defer lc.deinit();
    const r = lc.checkUnit();
    try std.testing.expectError(error.LeakError, r);
}

test "leakcheck accepts alias freed through the copy" {
    const gpa = std.testing.allocator;
    const src = "int main() { int* p = new int; int* q = p; delete q; return 0; }\n";
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const agpa = arena.allocator();
    var diag = Diag.init(agpa);
    var lx = lex.Lexer.init(src);
    const toks = try lx.tokenize(agpa, &diag);
    var parser = par.Parser.create(agpa, src, toks, &diag);
    defer parser.deinit();
    try parser.parseUnit();
    var lc = LeakCheck.init(agpa, &parser, &diag);
    defer lc.deinit();
    try lc.checkUnit();
}

test "leakcheck rejects unfreed alias set" {
    const gpa = std.testing.allocator;
    const src = "int main() { int* p = new int; int* q = p; return 0; }\n";
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const agpa = arena.allocator();
    var diag = Diag.init(agpa);
    var lx = lex.Lexer.init(src);
    const toks = try lx.tokenize(agpa, &diag);
    var parser = par.Parser.create(agpa, src, toks, &diag);
    defer parser.deinit();
    try parser.parseUnit();
    var lc = LeakCheck.init(agpa, &parser, &diag);
    defer lc.deinit();
    const r = lc.checkUnit();
    try std.testing.expectError(error.LeakError, r);
}

test "leakcheck rejects loop-carried allocation" {
    const gpa = std.testing.allocator;
    const src = "int main() { int* p = nullptr; int i = 0; while (i < 3) { p = new int; i++; } delete p; return 0; }\n";
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const agpa = arena.allocator();
    var diag = Diag.init(agpa);
    var lx = lex.Lexer.init(src);
    const toks = try lx.tokenize(agpa, &diag);
    var parser = par.Parser.create(agpa, src, toks, &diag);
    defer parser.deinit();
    try parser.parseUnit();
    var lc = LeakCheck.init(agpa, &parser, &diag);
    defer lc.deinit();
    const r = lc.checkUnit();
    try std.testing.expectError(error.LeakError, r);
}

test "leakcheck accepts factory return" {
    const gpa = std.testing.allocator;
    const src = "int* make() { int* p = new int; return p; }\nint main() { int* q = make(); delete q; return 0; }\n";
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const agpa = arena.allocator();
    var diag = Diag.init(agpa);
    var lx = lex.Lexer.init(src);
    const toks = try lx.tokenize(agpa, &diag);
    var parser = par.Parser.create(agpa, src, toks, &diag);
    defer parser.deinit();
    try parser.parseUnit();
    var lc = LeakCheck.init(agpa, &parser, &diag);
    defer lc.deinit();
    try lc.checkUnit();
}

test "leakcheck rejects delete of null-overwritten pointer" {
    const gpa = std.testing.allocator;
    const src = "int main() { int* p = new int; p = nullptr; delete p; return 0; }\n";
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const agpa = arena.allocator();
    var diag = Diag.init(agpa);
    var lx = lex.Lexer.init(src);
    const toks = try lx.tokenize(agpa, &diag);
    var parser = par.Parser.create(agpa, src, toks, &diag);
    defer parser.deinit();
    try parser.parseUnit();
    var lc = LeakCheck.init(agpa, &parser, &diag);
    defer lc.deinit();
    const r = lc.checkUnit();
    try std.testing.expectError(error.LeakError, r);
}
