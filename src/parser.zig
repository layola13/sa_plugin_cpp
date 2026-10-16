const std = @import("std");
const lex = @import("lexer.zig");

pub const CompileError = lex.CompileError;
pub const Diag = lex.Diag;
pub const Token = lex.Token;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

pub const TypePrim = enum {
    i32,
    i64,
    f64,
    boolean,
    char8,
    void_,
    named, // struct/class/enum/typedef name in `name`
    auto_,
};

pub const CType = struct {
    prim: TypePrim = .i32,
    ptr: u8 = 0,
    name: []const u8 = "",

    pub fn isVoid(self: CType) bool {
        return self.prim == .void_ and self.ptr == 0;
    }

    pub fn isFloat(self: CType) bool {
        return self.prim == .f64 and self.ptr == 0;
    }

    pub fn isScalar(self: CType) bool {
        return self.ptr == 0 and (self.prim == .i32 or self.prim == .i64 or self.prim == .f64 or self.prim == .boolean or self.prim == .char8);
    }

    pub fn eql(a: CType, b: CType) bool {
        if (a.prim != b.prim or a.ptr != b.ptr) return false;
        if (a.prim == .named and !std.mem.eql(u8, a.name, b.name)) return false;
        return true;
    }
};

// ---------------------------------------------------------------------------
// AST
// ---------------------------------------------------------------------------

pub const Eid = u32;
pub const Sid = u32;
pub const NoId: u32 = std.math.maxInt(u32);

pub const UnOp = enum { neg, not, bnot, deref, addrof, pre_inc, pre_dec, post_inc, post_dec };
pub const BinOp = enum {
    add, sub, mul, div, rem,
    shl, shr,
    lt, le, gt, ge, eq, ne,
    bit_and, bit_or, bit_xor,
    log_and, log_or,
    assign, add_assign, sub_assign, mul_assign, div_assign, rem_assign,
    shl_assign, shr_assign, band_assign, bor_assign, bxor_assign,
};

pub const ExprKind = union(enum) {
    int_lit: []const u8,
    float_lit: []const u8,
    str_lit: []const u8, // raw literal text including quotes
    char_lit: []const u8, // raw literal text including quotes
    bool_lit: bool,
    null_lit,
    ident: []const u8,
    this_,
    unary: struct { op: UnOp, x: Eid },
    binary: struct { op: BinOp, l: Eid, r: Eid },
    ternary: struct { c: Eid, t: Eid, f: Eid },
    call: struct { callee: Eid, args: []Eid },
    method_call: struct { obj: Eid, arrow: bool, name: []const u8, args: []Eid },
    index: struct { base: Eid, idx: Eid },
    field: struct { base: Eid, arrow: bool, name: []const u8 },
    new_: struct { ty: CType, args: []Eid, array_len: ?Eid },
    delete_: struct { x: Eid, is_array: bool },
    sizeof_ty: CType,
    cast: struct { ty: CType, x: Eid },
    cout_chain: []Eid,
    endl,
    init_list: []Eid,
};

pub const Expr = struct {
    kind: ExprKind,
    off: usize,
};

pub const SwitchCase = struct {
    value: ?Eid, // null = default
    body: []Sid,
};

pub const StmtKind = union(enum) {
    decl: struct { ty: CType, name: []const u8, init: Eid, has_init: bool, array_len: ?Eid },
    expr_stmt: Eid,
    if_: struct { cond: Eid, then_body: []Sid, else_body: []Sid, has_else: bool },
    while_: struct { cond: Eid, body: []Sid },
    do_while: struct { body: []Sid, cond: Eid },
    for_: struct { init: []Sid, cond: Eid, has_cond: bool, step: Eid, has_step: bool, body: []Sid },
    range_for: struct { ty: CType, var_name: []const u8, iterable: Eid, body: []Sid },
    switch_: struct { scrutinee: Eid, cases: []SwitchCase },
    return_: struct { value: Eid, has_value: bool },
    break_,
    continue_,
    block: []Sid,
};

pub const Stmt = struct {
    kind: StmtKind,
    off: usize,
};

pub const Param = struct {
    ty: CType,
    name: []const u8,
};

pub const Func = struct {
    ret: CType,
    name: []const u8, // unqualified
    qual: []const u8, // enclosing class/namespace + "_" or ""
    params: []Param,
    body: []Sid,
    is_method: bool,
    is_static: bool,
    is_ctor: bool,
    is_dtor: bool,
    off: usize,
};

pub const Field = struct {
    ty: CType,
    name: []const u8,
};

pub const StructDef = struct {
    name: []const u8,
    qual: []const u8,
    fields: []Field,
    off: usize,
};

pub const Alias = struct {
    name: []const u8,
    ty: CType,
};

pub const EnumConst = struct {
    name: []const u8,
    qual: []const u8,
    value: i64,
};

pub const EnumDef = struct {
    name: []const u8,
    qual: []const u8,
};

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

pub const Parser = struct {
    gpa: std.mem.Allocator,
    source: []const u8,
    toks: []Token,
    pos: usize = 0,
    diag: *Diag,
    exprs: std.array_list.Managed(Expr),
    stmts: std.array_list.Managed(Stmt),
    funcs: std.array_list.Managed(Func),
    structs: std.array_list.Managed(StructDef),
    aliases: std.array_list.Managed(Alias),
    enums: std.array_list.Managed(EnumDef),
    enum_consts: std.array_list.Managed(EnumConst),
    ns_stack: std.array_list.Managed([]const u8),

    pub fn create(gpa: std.mem.Allocator, source: []const u8, toks: []Token, diag: *Diag) Parser {
        return .{
            .gpa = gpa,
            .source = source,
            .toks = toks,
            .diag = diag,
            .exprs = .init(gpa),
            .stmts = .init(gpa),
            .funcs = .init(gpa),
            .structs = .init(gpa),
            .aliases = .init(gpa),
            .enums = .init(gpa),
            .enum_consts = .init(gpa),
            .ns_stack = .init(gpa),
        };
    }

    pub fn deinit(self: *Parser) void {
        self.exprs.deinit();
        self.stmts.deinit();
        self.funcs.deinit();
        self.structs.deinit();
        self.aliases.deinit();
        self.enums.deinit();
        self.enum_consts.deinit();
        self.ns_stack.deinit();
    }

    fn err(self: *Parser, off: usize, comptime fmt: []const u8, args: anytype) CompileError {
        self.diag.fail(off, fmt, args);
        return error.ParseError;
    }

    fn peek(self: *Parser) Token {
        return self.toks[self.pos];
    }

    fn peekAt(self: *Parser, n: usize) Token {
        const i = @min(self.pos + n, self.toks.len - 1);
        return self.toks[i];
    }

    fn next(self: *Parser) Token {
        const t = self.toks[self.pos];
        if (self.pos + 1 < self.toks.len) self.pos += 1;
        return t;
    }

    fn eat(self: *Parser, tag: lex.Tag) ?Token {
        if (self.peek().tag == tag) return self.next();
        return null;
    }

    fn expect(self: *Parser, tag: lex.Tag, what: []const u8) CompileError!Token {
        if (self.eat(tag)) |t| return t;
        return self.err(self.peek().start, "expected {s}", .{what});
    }

    fn atIdent(self: *Parser, word: []const u8) bool {
        const t = self.peek();
        return t.tag == .ident and std.mem.eql(u8, t.text(self.source), word);
    }

    fn eatIdent(self: *Parser, word: []const u8) bool {
        if (self.atIdent(word)) {
            _ = self.next();
            return true;
        }
        return false;
    }

    fn nsPrefix(self: *Parser) CompileError![]const u8 {
        if (self.ns_stack.items.len == 0) return "";
        var total: usize = 0;
        for (self.ns_stack.items) |n| total += n.len + 1;
        const buf = try self.gpa.alloc(u8, total);
        var o: usize = 0;
        for (self.ns_stack.items) |n| {
            @memcpy(buf[o .. o + n.len], n);
            o += n.len;
            buf[o] = '_';
            o += 1;
        }
        return buf[0..o];
    }

    pub fn parseUnit(self: *Parser) CompileError!void {
        while (self.peek().tag != .eof) {
            if (self.peek().tag == .directive) {
                _ = self.next();
                continue;
            }
            if (self.eatIdent("static_assert")) {
                try self.parseStaticAssert();
                continue;
            }
            if (self.eatIdent("typedef")) {
                try self.parseTypedef();
                continue;
            }
            if (self.eatIdent("using")) {
                try self.parseUsing();
                continue;
            }
            if (self.atIdent("namespace")) {
                _ = self.next();
                try self.parseNamespaceBody("");
                continue;
            }
            if (self.atIdent("template")) {
                return self.err(self.peek().start, "templates are not supported in v0.1", .{});
            }
            if (self.atIdent("enum")) {
                try self.parseEnum("");
                _ = self.eat(.semi);
                continue;
            }
            if (self.atIdent("struct") or self.atIdent("class")) {
                try self.parseStruct("");
                continue;
            }
            _ = self.eatIdent("extern");
            _ = self.eatIdent("inline");
            _ = self.eatIdent("constexpr");
            _ = self.eatIdent("consteval");
            const is_static = self.eatIdent("static");
            if (self.peek().tag == .ident or self.peek().tag == .colon_colon) {
                const saved = self.pos;
                _ = self.parseType() catch {
                    self.pos = saved;
                    return self.err(self.peek().start, "expected a top-level declaration", .{});
                };
                if (self.peek().tag == .ident or self.atIdent("operator")) {
                    self.pos = saved;
                    const cur = try self.nsPrefix();
                    try self.parseTopDecl(cur, is_static);
                    continue;
                }
                self.pos = saved;
                return self.err(self.peek().start, "expected a top-level declaration", .{});
            }
            return self.err(self.peek().start, "expected a top-level declaration", .{});
        }
    }

    fn parseStaticAssert(self: *Parser) CompileError!void {
        _ = try self.expect(.l_paren, "'('");
        var depth: usize = 1;
        while (depth > 0) {
            const t = self.next();
            if (t.tag == .eof) return self.err(t.start, "unterminated static_assert", .{});
            if (t.tag == .l_paren) depth += 1;
            if (t.tag == .r_paren) depth -= 1;
        }
        _ = try self.expect(.semi, "';'");
    }

    fn parseTypedef(self: *Parser) CompileError!void {
        const ty = try self.parseType();
        const name_tok = try self.expect(.ident, "typedef name");
        const name = name_tok.text(self.source);
        if (self.eat(.l_bracket) != null) {
            _ = try self.expect(.r_bracket, "']'");
            return self.err(name_tok.start, "array typedefs are not supported in v0.1", .{});
        }
        _ = try self.expect(.semi, "';'");
        try self.aliases.append(.{ .name = name, .ty = ty });
    }

    fn parseUsing(self: *Parser) CompileError!void {
        if (self.eatIdent("namespace")) {
            while (self.peek().tag != .semi and self.peek().tag != .eof) _ = self.next();
            _ = try self.expect(.semi, "';'");
            return;
        }
        const name_tok = try self.expect(.ident, "using-alias name");
        const name = name_tok.text(self.source);
        if (self.eat(.eq) == null) {
            while (self.peek().tag != .semi and self.peek().tag != .eof) _ = self.next();
            _ = try self.expect(.semi, "';'");
            return;
        }
        const ty = try self.parseType();
        _ = try self.expect(.semi, "';'");
        try self.aliases.append(.{ .name = name, .ty = ty });
    }

    fn parseNamespaceBody(self: *Parser, outer_prefix: []const u8) CompileError!void {
        var name: []const u8 = "";
        if (self.peek().tag == .ident) name = self.next().text(self.source);
        if (self.eat(.eq) != null) {
            while (self.peek().tag != .semi and self.peek().tag != .eof) _ = self.next();
            _ = try self.expect(.semi, "';'");
            return;
        }
        _ = try self.expect(.l_brace, "'{{'");
        // Stack holds BARE names; nsPrefix() joins them with '_' separators.
        const anonymous = name.len == 0;
        if (!anonymous) {
            const bare = try std.fmt.allocPrint(self.gpa, "{s}{s}", .{ outer_prefix, name });
            try self.ns_stack.append(bare);
        }
        while (self.peek().tag != .r_brace and self.peek().tag != .eof) {
            if (self.peek().tag == .directive) {
                _ = self.next();
                continue;
            }
            if (self.atIdent("namespace")) {
                _ = self.next();
                const cur = try self.nsPrefix();
                try self.parseNamespaceBody(cur);
                continue;
            }
            if (self.atIdent("struct") or self.atIdent("class")) {
                const cur = try self.nsPrefix();
                try self.parseStruct(cur);
                continue;
            }
            if (self.atIdent("enum")) {
                const cur = try self.nsPrefix();
                try self.parseEnum(cur);
                _ = self.eat(.semi);
                continue;
            }
            if (self.atIdent("template")) {
                return self.err(self.peek().start, "templates are not supported in v0.1", .{});
            }
            const saved = self.pos;
            _ = self.eatIdent("extern");
            _ = self.eatIdent("inline");
            _ = self.eatIdent("constexpr");
            _ = self.eatIdent("static");
            if (self.peek().tag == .ident or self.peek().tag == .colon_colon) {
                const cur = try self.nsPrefix();
                self.pos = saved;
                _ = self.eatIdent("extern");
                _ = self.eatIdent("inline");
                _ = self.eatIdent("constexpr");
                _ = self.eatIdent("static");
                try self.parseTopDecl(cur, false);
                continue;
            }
            self.pos = saved;
            return self.err(self.peek().start, "expected a namespace member", .{});
        }
        _ = try self.expect(.r_brace, "'}'");
        if (!anonymous) _ = self.ns_stack.pop();
    }

    fn parseEnum(self: *Parser, qual: []const u8) CompileError!void {
        _ = self.next(); // enum
        _ = self.eatIdent("class");
        _ = self.eatIdent("struct");
        if (self.peek().tag == .ident and self.peekAt(1).tag != .colon_colon) {
            const ename = self.next().text(self.source);
            try self.enums.append(.{ .name = ename, .qual = qual });
        }
        if (self.eat(.colon) != null) {
            _ = try self.parseType();
        }
        _ = try self.expect(.l_brace, "'{{'");
        var next_val: i64 = 0;
        while (self.peek().tag != .r_brace) {
            const item = try self.expect(.ident, "enumerator");
            var val = next_val;
            if (self.eat(.eq) != null) {
                val = try self.parseConstInt();
            }
            try self.enum_consts.append(.{ .name = item.text(self.source), .qual = qual, .value = val });
            next_val = val + 1;
            if (self.eat(.comma) == null) break;
        }
        _ = try self.expect(.r_brace, "'}'");
    }

    fn parseConstInt(self: *Parser) CompileError!i64 {
        var neg = false;
        if (self.eat(.minus) != null) neg = true;
        const t = self.peek();
        if (t.tag != .int_lit) return self.err(t.start, "expected an integer constant", .{});
        _ = self.next();
        const v = parseIntLit(t.text(self.source)) catch {
            return self.err(t.start, "bad integer constant", .{});
        };
        return if (neg) -v else v;
    }

    fn parseStruct(self: *Parser, qual: []const u8) CompileError!void {
        const kw = self.next(); // struct/class/union
        if (std.mem.eql(u8, kw.text(self.source), "union")) {
            return self.err(kw.start, "unions are not supported in v0.1", .{});
        }
        var name: []const u8 = "";
        if (self.peek().tag == .ident) name = self.next().text(self.source);
        if (self.peek().tag == .colon) {
            return self.err(self.peek().start, "inheritance is not supported in v0.1", .{});
        }
        if (self.peek().tag != .l_brace) {
            _ = try self.expect(.semi, "';'");
            return;
        }
        _ = self.next(); // {
        var fields: std.array_list.Managed(Field) = .init(self.gpa);
        defer fields.deinit();
        const class_qual = try std.fmt.allocPrint(self.gpa, "{s}{s}_", .{ qual, name });
        while (self.peek().tag != .r_brace and self.peek().tag != .eof) {
            if (self.peek().tag == .directive) {
                _ = self.next();
                continue;
            }
            if (self.atIdent("public") or self.atIdent("private") or self.atIdent("protected")) {
                _ = self.next();
                _ = try self.expect(.colon, "':'");
                continue;
            }
            if (self.atIdent("template")) {
                return self.err(self.peek().start, "templates are not supported in v0.1", .{});
            }
            if (self.atIdent("static_assert")) {
                _ = self.next();
                try self.parseStaticAssert();
                continue;
            }
            if (self.atIdent("using")) {
                _ = self.next();
                try self.parseUsing();
                continue;
            }
            if (self.atIdent("typedef")) {
                _ = self.next();
                try self.parseTypedef();
                continue;
            }
            if (self.atIdent("enum")) {
                try self.parseEnum(class_qual);
                _ = self.eat(.semi);
                continue;
            }
            if (self.atIdent("struct") or self.atIdent("class")) {
                try self.parseStruct(class_qual);
                continue;
            }
            if (self.atIdent("friend")) {
                return self.err(self.peek().start, "friend declarations are not supported in v0.1", .{});
            }
            if (self.atIdent("virtual")) {
                return self.err(self.peek().start, "virtual functions are not supported in v0.1", .{});
            }
            const mem_off = self.peek().start;
            if (self.peek().tag == .tilde) {
                _ = self.next();
                _ = try self.expect(.ident, "destructor name");
                _ = try self.expect(.l_paren, "'('");
                _ = try self.expect(.r_paren, "')'");
                const body = try self.parseBlock();
                const mname = try std.fmt.allocPrint(self.gpa, "{s}_dtor", .{name});
                try self.funcs.append(.{
                    .ret = .{ .prim = .void_ },
                    .name = mname,
                    .qual = qual,
                    .params = &.{},
                    .body = body,
                    .is_method = true,
                    .is_static = false,
                    .is_ctor = false,
                    .is_dtor = true,
                    .off = mem_off,
                });
                continue;
            }
            _ = self.eatIdent("inline");
            _ = self.eatIdent("constexpr");
            _ = self.eatIdent("explicit");
            _ = self.eatIdent("mutable");
            const is_static = self.eatIdent("static");
            if (self.peek().tag == .ident and std.mem.eql(u8, self.peek().text(self.source), name) and self.peekAt(1).tag == .l_paren) {
                _ = self.next();
                const params = try self.parseParamList();
                if (self.eat(.colon) != null) {
                    return self.err(self.peek().start, "constructor initializer lists are not supported in v0.1", .{});
                }
                const body = try self.parseBlock();
                if (params.len != 0) {
                    return self.err(mem_off, "constructors with parameters are not supported in v0.1 (use aggregate init Type{{...}})", .{});
                }
                const mname = try std.fmt.allocPrint(self.gpa, "{s}_ctor", .{name});
                try self.funcs.append(.{
                    .ret = .{ .prim = .void_ },
                    .name = mname,
                    .qual = qual,
                    .params = params,
                    .body = body,
                    .is_method = true,
                    .is_static = false,
                    .is_ctor = true,
                    .is_dtor = false,
                    .off = mem_off,
                });
                continue;
            }
            const mty = try self.parseType();
            if (self.atIdent("operator")) {
                return self.err(self.peek().start, "operator overloading is not supported in v0.1", .{});
            }
            const mname_tok = try self.expect(.ident, "member name");
            const mname = mname_tok.text(self.source);
            if (self.peek().tag == .l_paren) {
                const params = try self.parseParamList();
                _ = self.eatIdent("const");
                _ = self.eatIdent("noexcept");
                if (self.eat(.semi) != null) {
                    return self.err(mname_tok.start, "method '{s}' needs a body in v0.1 (no separate declaration/definition)", .{mname});
                }
                const body = try self.parseBlock();
                try self.funcs.append(.{
                    .ret = mty,
                    .name = mname,
                    .qual = class_qual,
                    .params = params,
                    .body = body,
                    .is_method = true,
                    .is_static = is_static,
                    .is_ctor = false,
                    .is_dtor = false,
                    .off = mem_off,
                });
                continue;
            }
            if (self.eat(.l_bracket) != null) {
                return self.err(mname_tok.start, "member arrays are not supported in v0.1", .{});
            }
            if (self.eat(.l_brace) != null or self.eat(.l_paren) != null) {
                return self.err(mname_tok.start, "member initializers are not supported in v0.1", .{});
            }
            if (self.eat(.eq) != null) {
                return self.err(mname_tok.start, "member initializers are not supported in v0.1 (use a default constructor)", .{});
            }
            if (self.eat(.colon) != null) {
                return self.err(mname_tok.start, "bit-fields are not supported in v0.1", .{});
            }
            _ = try self.expect(.semi, "';'");
            try fields.append(.{ .ty = mty, .name = mname });
        }
        _ = try self.expect(.r_brace, "'}'");
        _ = try self.expect(.semi, "';'");
        try self.structs.append(.{
            .name = name,
            .qual = qual,
            .fields = try fields.toOwnedSlice(),
            .off = kw.start,
        });
    }

    /// Top-level function definition or (rejected) global variable.
    fn parseTopDecl(self: *Parser, qual: []const u8, is_static: bool) CompileError!void {
        const off = self.peek().start;
        const ret = try self.parseType();
        if (self.atIdent("operator")) {
            return self.err(self.peek().start, "operator overloading is not supported in v0.1", .{});
        }
        const name_tok = try self.expect(.ident, "declaration name");
        const name = name_tok.text(self.source);
        if (self.peek().tag == .l_paren) {
            const params = try self.parseParamList();
            if (self.eat(.semi) != null) {
                return self.err(name_tok.start, "function '{s}' needs a body in v0.1 (no prototypes)", .{name});
            }
            const body = try self.parseBlock();
            try self.funcs.append(.{
                .ret = ret,
                .name = name,
                .qual = qual,
                .params = params,
                .body = body,
                .is_method = false,
                .is_static = is_static,
                .is_ctor = false,
                .is_dtor = false,
                .off = off,
            });
            return;
        }
        return self.err(name_tok.start, "global variables are not supported in v0.1 (move '{s}' into a function)", .{name});
    }

    fn parseParamList(self: *Parser) CompileError![]Param {
        _ = try self.expect(.l_paren, "'('");
        var params: std.array_list.Managed(Param) = .init(self.gpa);
        defer params.deinit();
        if (self.eat(.r_paren) != null) return try params.toOwnedSlice();
        if (self.peek().tag == .ident and std.mem.eql(u8, self.peek().text(self.source), "void") and self.peekAt(1).tag == .r_paren) {
            _ = self.next();
            _ = try self.expect(.r_paren, "')'");
            return try params.toOwnedSlice();
        }
        while (true) {
            if (self.eat(.ellipsis) != null) {
                return self.err(self.peek().start, "varargs are not supported in v0.1", .{});
            }
            const pty = try self.parseType();
            var pname: []const u8 = "_";
            if (self.peek().tag == .ident) pname = self.next().text(self.source);
            if (self.eat(.l_bracket) != null) {
                _ = try self.expect(.r_bracket, "']'");
                var t = pty;
                t.ptr += 1;
                try params.append(.{ .ty = t, .name = pname });
            } else {
                if (self.eat(.eq) != null) {
                    return self.err(self.peek().start, "default arguments are not supported in v0.1", .{});
                }
                try params.append(.{ .ty = pty, .name = pname });
            }
            if (self.eat(.comma) != null) continue;
            break;
        }
        _ = try self.expect(.r_paren, "')'");
        return try params.toOwnedSlice();
    }

    /// Parse a (possibly qualified, const/unsigned-decorated) type.
    fn parseType(self: *Parser) CompileError!CType {
        _ = self.eat(.colon_colon);
        var is_unsigned = false;
        var long_count: u8 = 0;
        while (true) {
            if (self.eatIdent("const") or self.eatIdent("constexpr") or self.eatIdent("volatile")) {
                continue;
            }
            if (self.eatIdent("unsigned")) {
                is_unsigned = true;
                continue;
            }
            if (self.eatIdent("signed")) {
                continue;
            }
            if (self.eatIdent("long")) {
                long_count += 1;
                continue;
            }
            if (self.eatIdent("short")) {
                const t = self.peek();
                if (t.tag == .ident and std.mem.eql(u8, t.text(self.source), "int")) _ = self.next();
                const ty = CType{ .prim = .i32 };
                return self.finishType(ty);
            }
            if (self.eatIdent("struct") or self.eatIdent("class") or self.eatIdent("enum") or self.eatIdent("typename")) {
                continue;
            }
            break;
        }
        // Bare `long` / `unsigned` / `signed` (etc.) mean `int` when no
        // explicit base type follows.
        if ((long_count > 0 or is_unsigned) and self.peek().tag == .ident) {
            const nw = self.peek().text(self.source);
            const is_base = std.mem.eql(u8, nw, "void") or std.mem.eql(u8, nw, "bool") or std.mem.eql(u8, nw, "char") or std.mem.eql(u8, nw, "short") or std.mem.eql(u8, nw, "int") or std.mem.eql(u8, nw, "float") or std.mem.eql(u8, nw, "double") or std.mem.eql(u8, nw, "auto") or std.mem.eql(u8, nw, "struct") or std.mem.eql(u8, nw, "class") or std.mem.eql(u8, nw, "enum") or std.mem.eql(u8, nw, "typename");
            var known = is_base;
            if (!known) {
                for (self.structs.items) |st| {
                    if (std.mem.eql(u8, st.name, nw)) {
                        known = true;
                        break;
                    }
                }
            }
            if (!known) {
                for (self.aliases.items) |al| {
                    if (std.mem.eql(u8, al.name, nw)) {
                        known = true;
                        break;
                    }
                }
            }
            if (!known) {
                var base_ty = CType{ .prim = .i32 };
                if (long_count > 0) base_ty.prim = .i64;
                return self.finishType(base_ty);
            }
        }
        const t = self.peek();
        if (t.tag != .ident) return self.err(t.start, "expected a type", .{});
        const word = t.text(self.source);
        var full: []const u8 = word;
        if (self.peekAt(1).tag == .colon_colon) {
            var parts: std.array_list.Managed([]const u8) = .init(self.gpa);
            defer parts.deinit();
            try parts.append(word);
            _ = self.next();
            while (self.eat(.colon_colon) != null) {
                const p = try self.expect(.ident, "type name");
                try parts.append(p.text(self.source));
            }
            full = parts.items[parts.items.len - 1];
            if (parts.items.len >= 2) {
                const scope_name = parts.items[parts.items.len - 2];
                if (std.mem.eql(u8, scope_name, "std") and std.mem.eql(u8, full, "string")) {
                    return self.err(t.start, "std::string is not supported in v0.1 (use const char* literals)", .{});
                }
                if (std.mem.eql(u8, scope_name, "std") and std.mem.eql(u8, full, "vector")) {
                    return self.err(t.start, "std::vector is not supported in v0.1 (use fixed arrays T[N])", .{});
                }
            }
        } else {
            _ = self.next();
            if (std.mem.eql(u8, full, "string")) {
                return self.err(t.start, "std::string is not supported in v0.1 (use const char* literals)", .{});
            }
        }
        var prim: TypePrim = undefined;
        var named: []const u8 = "";
        if (std.mem.eql(u8, full, "void")) {
            prim = .void_;
        } else if (std.mem.eql(u8, full, "bool")) {
            prim = .boolean;
        } else if (std.mem.eql(u8, full, "char")) {
            prim = .char8;
        } else if (std.mem.eql(u8, full, "float")) {
            prim = .f64;
        } else if (std.mem.eql(u8, full, "double")) {
            prim = .f64;
        } else if (std.mem.eql(u8, full, "int")) {
            prim = .i32;
        } else if (std.mem.eql(u8, full, "auto")) {
            prim = .auto_;
        } else {
            var resolved = false;
            for (self.aliases.items) |a| {
                if (std.mem.eql(u8, a.name, full)) {
                    prim = a.ty.prim;
                    named = a.ty.name;
                    resolved = true;
                    break;
                }
            }
            if (!resolved) {
                prim = .named;
                named = full;
            }
        }
        if (long_count > 0 and prim == .i32) prim = .i64;
        if (is_unsigned and prim == .char8) prim = .i32;
        return self.finishType(.{ .prim = prim, .name = named });
    }

    fn finishType(self: *Parser, base: CType) CompileError!CType {
        var ty = base;
        // A `<` right after a type name means template arguments, e.g.
        // `folly::Function<void()>` (folly HazptrDomain.h:49). v0.1 has no
        // templates, so refuse explicitly instead of falling through to a
        // cryptic `expected ')'` in the surrounding parameter list.
        if (self.peek().tag == .lt) {
            return self.err(self.peek().start, "templates are not supported in v0.1", .{});
        }
        while (true) {
            if (self.eat(.star) != null) {
                ty.ptr += 1;
                _ = self.eatIdent("const");
                continue;
            }
            if (self.eat(.amp) != null) {
                ty.ptr += 1;
                continue;
            }
            if (self.eat(.amp_amp) != null) {
                return self.err(self.peek().start, "rvalue references are not supported in v0.1", .{});
            }
            break;
        }
        _ = self.eatIdent("const");
        return ty;
    }

    // -- statements ----------------------------------------------------------

    fn addStmt(self: *Parser, kind: StmtKind, off: usize) CompileError!Sid {
        const id: Sid = @intCast(self.stmts.items.len);
        try self.stmts.append(.{ .kind = kind, .off = off });
        return id;
    }

    fn addExpr(self: *Parser, kind: ExprKind, off: usize) CompileError!Eid {
        const id: Eid = @intCast(self.exprs.items.len);
        try self.exprs.append(.{ .kind = kind, .off = off });
        return id;
    }

    pub fn parseBlock(self: *Parser) CompileError![]Sid {
        _ = try self.expect(.l_brace, "'{{'");
        var list: std.array_list.Managed(Sid) = .init(self.gpa);
        defer list.deinit();
        while (self.peek().tag != .r_brace) {
            if (self.peek().tag == .eof) return self.err(self.peek().start, "unterminated block", .{});
            const s = try self.parseStmt();
            try list.append(s);
        }
        _ = try self.expect(.r_brace, "'}'");
        return try list.toOwnedSlice();
    }

    fn parseStmt(self: *Parser) CompileError!Sid {
        const t = self.peek();
        if (t.tag == .directive) {
            _ = self.next();
            return self.parseStmt();
        }
        if (t.tag == .l_brace) {
            const body = try self.parseBlock();
            return self.addStmt(.{ .block = body }, t.start);
        }
        if (t.tag == .semi) {
            _ = self.next();
            const e = try self.addExpr(.{ .int_lit = "0" }, t.start);
            return self.addStmt(.{ .expr_stmt = e }, t.start);
        }
        if (t.tag != .ident) {
            const e = try self.parseExpr(0);
            _ = try self.expect(.semi, "';'");
            return self.addStmt(.{ .expr_stmt = e }, t.start);
        }
        const word = t.text(self.source);
        if (std.mem.eql(u8, word, "if")) return self.parseIf();
        if (std.mem.eql(u8, word, "while")) return self.parseWhile();
        if (std.mem.eql(u8, word, "do")) return self.parseDoWhile();
        if (std.mem.eql(u8, word, "for")) return self.parseFor();
        if (std.mem.eql(u8, word, "switch")) return self.parseSwitch();
        if (std.mem.eql(u8, word, "return")) return self.parseReturn();
        if (std.mem.eql(u8, word, "break")) {
            _ = self.next();
            _ = try self.expect(.semi, "';'");
            return self.addStmt(.break_, t.start);
        }
        if (std.mem.eql(u8, word, "continue")) {
            _ = self.next();
            _ = try self.expect(.semi, "';'");
            return self.addStmt(.continue_, t.start);
        }
        if (std.mem.eql(u8, word, "goto")) {
            return self.err(t.start, "goto is not supported in v0.1", .{});
        }
        if (std.mem.eql(u8, word, "try") or std.mem.eql(u8, word, "throw") or std.mem.eql(u8, word, "catch")) {
            return self.err(t.start, "exceptions are not supported in v0.1", .{});
        }
        if (std.mem.eql(u8, word, "typedef")) {
            _ = self.next();
            try self.parseTypedef();
            const e = try self.addExpr(.{ .int_lit = "0" }, t.start);
            return self.addStmt(.{ .expr_stmt = e }, t.start);
        }
        if (std.mem.eql(u8, word, "using")) {
            _ = self.next();
            try self.parseUsing();
            const e = try self.addExpr(.{ .int_lit = "0" }, t.start);
            return self.addStmt(.{ .expr_stmt = e }, t.start);
        }
        if (std.mem.eql(u8, word, "static_assert")) {
            _ = self.next();
            try self.parseStaticAssert();
            const e = try self.addExpr(.{ .int_lit = "0" }, t.start);
            return self.addStmt(.{ .expr_stmt = e }, t.start);
        }
        if (std.mem.eql(u8, word, "case") or std.mem.eql(u8, word, "default")) {
            return self.err(t.start, "'{s}' outside switch", .{word});
        }
        if (self.maybeStartsType()) {
            const saved_pos = self.pos;
            const saved_exprs = self.exprs.items.len;
            const saved_stmts = self.stmts.items.len;
            const decl = self.parseDeclStmt();
            if (decl) |s| return s else |_| {
                self.pos = saved_pos;
                self.exprs.shrinkRetainingCapacity(saved_exprs);
                self.stmts.shrinkRetainingCapacity(saved_stmts);
            }
        }
        const e = try self.parseExpr(0);
        _ = try self.expect(.semi, "';'");
        return self.addStmt(.{ .expr_stmt = e }, t.start);
    }

    fn maybeStartsType(self: *Parser) bool {
        const t = self.peek();
        if (t.tag == .colon_colon) return true;
        if (t.tag != .ident) return false;
        const w = t.text(self.source);
        const prims = [_][]const u8{ "void", "bool", "char", "short", "int", "long", "float", "double", "auto", "unsigned", "signed", "const", "constexpr", "volatile", "struct", "class", "enum", "typename", "static", "extern", "register", "mutable", "inline", "thread_local" };
        for (prims) |p| {
            if (std.mem.eql(u8, w, p)) return true;
        }
        // Statement/expression keywords never start a declaration.
        const non_types = [_][]const u8{ "new", "delete", "sizeof", "this", "true", "false", "nullptr", "throw", "operator", "alignof", "noexcept", "decltype", "cout", "cerr", "endl", "return", "if", "while", "do", "for", "switch", "break", "continue", "goto", "try", "catch", "typedef", "using", "static_assert", "case", "default", "public", "private", "protected", "template", "virtual", "friend", "explicit", "static_cast", "const_cast", "reinterpret_cast", "dynamic_cast" };
        for (non_types) |k| {
            if (std.mem.eql(u8, w, k)) return false;
        }
        for (self.structs.items) |s| {
            if (std.mem.eql(u8, s.name, w)) return true;
        }
        for (self.aliases.items) |a| {
            if (std.mem.eql(u8, a.name, w)) return true;
        }
        if (std.mem.eql(u8, w, "std")) return false;
        return true;
    }

    /// `Type name [= e] [, ...] ;` | `Type name[N] ... ;` | `Type name(a)` |
    /// `Type name{a}`. Fails (for backtracking) when this is not a decl.
    fn parseDeclStmt(self: *Parser) CompileError!Sid {
        const off = self.peek().start;
        _ = self.eatIdent("static");
        _ = self.eatIdent("extern");
        _ = self.eatIdent("register");
        _ = self.eatIdent("mutable");
        _ = self.eatIdent("thread_local");
        _ = self.eatIdent("inline");
        _ = self.eatIdent("constexpr");
        const ty = try self.parseType();
        if (self.peek().tag == .l_paren or self.peek().tag == .semi) {
            return error.ParseError;
        }
        const name_tok = try self.expect(.ident, "variable name");
        const first_name = name_tok.text(self.source);
        if (self.eat(.l_bracket) != null) {
            if (self.peek().tag == .r_bracket) {
                return self.err(self.peek().start, "unsized arrays are not supported in v0.1", .{});
            }
            const n = try self.parseConstInt();
            _ = try self.expect(.r_bracket, "']'");
            if (n <= 0) return self.err(name_tok.start, "array size must be positive", .{});
            return self.finishArrayDecl(off, ty, first_name, n);
        }
        if (self.eat(.l_paren) != null) {
            var args: std.array_list.Managed(Eid) = .init(self.gpa);
            defer args.deinit();
            if (self.eat(.r_paren) == null) {
                while (true) {
                    try args.append(try self.parseExpr(0));
                    if (self.eat(.comma) != null) continue;
                    break;
                }
                _ = try self.expect(.r_paren, "')'");
            }
            _ = try self.expect(.semi, "';'");
            if (args.items.len == 0) {
                return self.addStmt(.{ .decl = .{ .ty = ty, .name = first_name, .init = 0, .has_init = false, .array_len = null } }, off);
            }
            if (args.items.len == 1 and ty.prim != .named) {
                return self.addStmt(.{ .decl = .{ .ty = ty, .name = first_name, .init = args.items[0], .has_init = true, .array_len = null } }, off);
            }
            return self.err(off, "constructor-style init is not supported in v0.1 (use Type{{...}} for aggregates)", .{});
        }
        if (self.eat(.l_brace) != null) {
            var items: std.array_list.Managed(Eid) = .init(self.gpa);
            defer items.deinit();
            if (self.eat(.r_brace) == null) {
                while (true) {
                    try items.append(try self.parseExpr(0));
                    if (self.eat(.comma) != null) {
                        if (self.peek().tag == .r_brace) break;
                        continue;
                    }
                    break;
                }
                _ = try self.expect(.r_brace, "'}'");
            }
            _ = try self.expect(.semi, "';'");
            const list = try self.addExpr(.{ .init_list = try items.toOwnedSlice() }, off);
            return self.addStmt(.{ .decl = .{ .ty = ty, .name = first_name, .init = list, .has_init = true, .array_len = null } }, off);
        }
        var init: Eid = 0;
        var has_init = false;
        if (self.eat(.eq) != null) {
            if (self.peek().tag == .l_brace) {
                _ = self.next();
                var items: std.array_list.Managed(Eid) = .init(self.gpa);
                defer items.deinit();
                if (self.eat(.r_brace) == null) {
                    while (true) {
                        try items.append(try self.parseExpr(0));
                        if (self.eat(.comma) != null) {
                            if (self.peek().tag == .r_brace) break;
                            continue;
                        }
                        break;
                    }
                    _ = try self.expect(.r_brace, "'}'");
                }
                init = try self.addExpr(.{ .init_list = try items.toOwnedSlice() }, off);
            } else {
                init = try self.parseExpr(0);
            }
            has_init = true;
        }
        const first_id = try self.addStmt(.{ .decl = .{ .ty = ty, .name = first_name, .init = init, .has_init = has_init, .array_len = null } }, off);
        var last = first_id;
        while (self.eat(.comma) != null) {
            const nt = try self.expect(.ident, "variable name");
            var ni: Eid = 0;
            var nhi = false;
            if (self.eat(.eq) != null) {
                ni = try self.parseExpr(0);
                nhi = true;
            }
            last = try self.addStmt(.{ .decl = .{ .ty = ty, .name = nt.text(self.source), .init = ni, .has_init = nhi, .array_len = null } }, nt.start);
        }
        _ = try self.expect(.semi, "';'");
        return last;
    }

    fn finishArrayDecl(self: *Parser, off: usize, ty: CType, name: []const u8, n: i64) CompileError!Sid {
        // Array decls carry their length text in array_len (an int_lit
        // expression holding the decimal length); an optional `= {...}`
        // brace list goes in init/has_init.
        const len_text = try std.fmt.allocPrint(self.gpa, "{d}", .{n});
        const len_e = try self.addExpr(.{ .int_lit = len_text }, off);
        var init: Eid = 0;
        var has_init = false;
        if (self.eat(.eq) != null) {
            _ = try self.expect(.l_brace, "'{{'");
            var items: std.array_list.Managed(Eid) = .init(self.gpa);
            defer items.deinit();
            if (self.eat(.r_brace) == null) {
                while (true) {
                    try items.append(try self.parseExpr(0));
                    if (self.eat(.comma) != null) {
                        if (self.peek().tag == .r_brace) break;
                        continue;
                    }
                    break;
                }
                _ = try self.expect(.r_brace, "'}'");
            }
            init = try self.addExpr(.{ .init_list = try items.toOwnedSlice() }, off);
            has_init = true;
        }
        const first = try self.addStmt(.{ .decl = .{ .ty = ty, .name = name, .init = init, .has_init = has_init, .array_len = len_e } }, off);
        var last = first;
        while (self.eat(.comma) != null) {
            const nt = try self.expect(.ident, "variable name");
            _ = try self.expect(.l_bracket, "'['");
            const m = try self.parseConstInt();
            _ = try self.expect(.r_bracket, "']'");
            if (m <= 0) return self.err(nt.start, "array size must be positive", .{});
            const mt = try std.fmt.allocPrint(self.gpa, "{d}", .{m});
            const me = try self.addExpr(.{ .int_lit = mt }, nt.start);
            var mi: Eid = 0;
            var mhi = false;
            if (self.eat(.eq) != null) {
                _ = try self.expect(.l_brace, "'{{'");
                var mitems: std.array_list.Managed(Eid) = .init(self.gpa);
                defer mitems.deinit();
                if (self.eat(.r_brace) == null) {
                    while (true) {
                        try mitems.append(try self.parseExpr(0));
                        if (self.eat(.comma) != null) {
                            if (self.peek().tag == .r_brace) break;
                            continue;
                        }
                        break;
                    }
                    _ = try self.expect(.r_brace, "'}'");
                }
                mi = try self.addExpr(.{ .init_list = try mitems.toOwnedSlice() }, nt.start);
                mhi = true;
            }
            last = try self.addStmt(.{ .decl = .{ .ty = ty, .name = nt.text(self.source), .init = mi, .has_init = mhi, .array_len = me } }, nt.start);
        }
        _ = try self.expect(.semi, "';'");
        return last;
    }

    fn parseIf(self: *Parser) CompileError!Sid {
        const off = self.peek().start;
        _ = self.next();
        if (self.eatIdent("constexpr")) {}
        _ = try self.expect(.l_paren, "'('");
        // C++17 if-with-initializer `if (init; cond)` is unsupported.
        {
            var k = self.pos;
            var depth: usize = 1;
            while (k < self.toks.len and depth > 0) {
                const tg = self.toks[k].tag;
                if (tg == .l_paren) depth += 1;
                if (tg == .r_paren) {
                    depth -= 1;
                    if (depth == 0) break;
                }
                if (tg == .semi and depth == 1) {
                    return self.err(self.peek().start, "if-with-initializer is not supported in v0.1", .{});
                }
                k += 1;
            }
        }
        const cond = try self.parseExpr(0);
        _ = try self.expect(.r_paren, "')'");
        const then_body = try self.parseBranch();
        var else_body: []Sid = &.{};
        var has_else = false;
        if (self.eatIdent("else")) {
            has_else = true;
            else_body = try self.parseBranch();
        }
        return self.addStmt(.{ .if_ = .{ .cond = cond, .then_body = then_body, .else_body = else_body, .has_else = has_else } }, off);
    }

    fn parseBranch(self: *Parser) CompileError![]Sid {
        if (self.peek().tag == .l_brace) return self.parseBlock();
        var list: std.array_list.Managed(Sid) = .init(self.gpa);
        defer list.deinit();
        try list.append(try self.parseStmt());
        return try list.toOwnedSlice();
    }

    fn parseWhile(self: *Parser) CompileError!Sid {
        const off = self.peek().start;
        _ = self.next();
        _ = try self.expect(.l_paren, "'('");
        const cond = try self.parseExpr(0);
        _ = try self.expect(.r_paren, "')'");
        const body = try self.parseBranch();
        return self.addStmt(.{ .while_ = .{ .cond = cond, .body = body } }, off);
    }

    fn parseDoWhile(self: *Parser) CompileError!Sid {
        const off = self.peek().start;
        _ = self.next();
        const body = try self.parseBranch();
        if (!self.eatIdent("while")) return self.err(self.peek().start, "expected 'while' after do-body", .{});
        _ = try self.expect(.l_paren, "'('");
        const cond = try self.parseExpr(0);
        _ = try self.expect(.r_paren, "')'");
        _ = try self.expect(.semi, "';'");
        return self.addStmt(.{ .do_while = .{ .body = body, .cond = cond } }, off);
    }

    fn parseFor(self: *Parser) CompileError!Sid {
        const off = self.peek().start;
        _ = self.next();
        _ = try self.expect(.l_paren, "'('");
        {
            var k = self.pos;
            var depth: usize = 0;
            var is_range = false;
            while (k < self.toks.len) {
                const tg = self.toks[k].tag;
                if (tg == .l_paren) depth += 1;
                if (tg == .r_paren and depth == 0) break;
                if (tg == .r_paren) depth -= 1;
                if (tg == .semi and depth == 0) break;
                if (tg == .colon and depth == 0) {
                    is_range = true;
                    break;
                }
                k += 1;
            }
            if (is_range) return self.parseRangeFor(off);
        }
        var init: std.array_list.Managed(Sid) = .init(self.gpa);
        defer init.deinit();
        if (self.eat(.semi) == null) {
            if (self.maybeStartsType()) {
                const saved_pos = self.pos;
                const saved_e = self.exprs.items.len;
                const saved_s = self.stmts.items.len;
                const d = self.parseDeclStmt();
                if (d) |s| {
                    try init.append(s);
                } else |_| {
                    self.pos = saved_pos;
                    self.exprs.shrinkRetainingCapacity(saved_e);
                    self.stmts.shrinkRetainingCapacity(saved_s);
                    const e = try self.parseExpr(0);
                    const es = try self.addStmt(.{ .expr_stmt = e }, off);
                    try init.append(es);
                    _ = try self.expect(.semi, "';'");
                }
            } else {
                const e = try self.parseExpr(0);
                const es = try self.addStmt(.{ .expr_stmt = e }, off);
                try init.append(es);
                _ = try self.expect(.semi, "';'");
            }
        }
        var cond: Eid = 0;
        var has_cond = false;
        if (self.peek().tag != .semi) {
            cond = try self.parseExpr(0);
            has_cond = true;
        }
        _ = try self.expect(.semi, "';'");
        var step: Eid = 0;
        var has_step = false;
        if (self.peek().tag != .r_paren) {
            step = try self.parseExpr(0);
            has_step = true;
        }
        _ = try self.expect(.r_paren, "')'");
        const body = try self.parseBranch();
        return self.addStmt(.{ .for_ = .{
            .init = try init.toOwnedSlice(),
            .cond = cond,
            .has_cond = has_cond,
            .step = step,
            .has_step = has_step,
            .body = body,
        } }, off);
    }

    fn parseRangeFor(self: *Parser, off: usize) CompileError!Sid {
        _ = self.eatIdent("const");
        const ty = try self.parseType();
        if (self.eat(.amp) != null) {}
        const v = try self.expect(.ident, "loop variable");
        _ = try self.expect(.colon, "':'");
        const iter = try self.parseExpr(0);
        _ = try self.expect(.r_paren, "')'");
        const body = try self.parseBranch();
        return self.addStmt(.{ .range_for = .{ .ty = ty, .var_name = v.text(self.source), .iterable = iter, .body = body } }, off);
    }

    fn parseSwitch(self: *Parser) CompileError!Sid {
        const off = self.peek().start;
        _ = self.next();
        _ = try self.expect(.l_paren, "'('");
        const scrut = try self.parseExpr(0);
        _ = try self.expect(.r_paren, "')'");
        _ = try self.expect(.l_brace, "'{{'");
        var cases: std.array_list.Managed(SwitchCase) = .init(self.gpa);
        defer cases.deinit();
        var cur_val: ?Eid = null;
        var cur_body: std.array_list.Managed(Sid) = .init(self.gpa);
        defer cur_body.deinit();
        var seen_case = false;
        while (self.peek().tag != .r_brace) {
            if (self.peek().tag == .eof) return self.err(self.peek().start, "unterminated switch", .{});
            if (self.peek().tag == .directive) {
                _ = self.next();
                continue;
            }
            if (self.eatIdent("case")) {
                if (seen_case) {
                    try cases.append(.{ .value = cur_val, .body = try cur_body.toOwnedSlice() });
                    cur_body.clearRetainingCapacity();
                }
                const ce = try self.parseExpr(0);
                _ = try self.expect(.colon, "':'");
                cur_val = ce;
                seen_case = true;
                continue;
            }
            if (self.eatIdent("default")) {
                if (seen_case) {
                    try cases.append(.{ .value = cur_val, .body = try cur_body.toOwnedSlice() });
                    cur_body.clearRetainingCapacity();
                }
                _ = try self.expect(.colon, "':'");
                cur_val = null;
                seen_case = true;
                continue;
            }
            if (!seen_case) {
                return self.err(self.peek().start, "statements before the first case are not supported in v0.1", .{});
            }
            try cur_body.append(try self.parseStmt());
        }
        if (seen_case) {
            try cases.append(.{ .value = cur_val, .body = try cur_body.toOwnedSlice() });
        }
        _ = try self.expect(.r_brace, "'}'");
        return self.addStmt(.{ .switch_ = .{ .scrutinee = scrut, .cases = try cases.toOwnedSlice() } }, off);
    }

    fn parseReturn(self: *Parser) CompileError!Sid {
        const off = self.peek().start;
        _ = self.next();
        if (self.eat(.semi) != null) {
            return self.addStmt(.{ .return_ = .{ .value = 0, .has_value = false } }, off);
        }
        const v = try self.parseExpr(0);
        _ = try self.expect(.semi, "';'");
        return self.addStmt(.{ .return_ = .{ .value = v, .has_value = true } }, off);
    }

    // -- expressions (precedence climbing) ------------------------------------

    fn parseExpr(self: *Parser, min_prec: u8) CompileError!Eid {
        var lhs = try self.parseUnary();
        while (true) {
            const t = self.peek();
            if (t.tag == .lt_lt and self.isCoutExpr(lhs)) {
                lhs = try self.parseCoutChain(lhs, t.start);
                continue;
            }
            const info = binInfo(t.tag) orelse break;
            if (info.prec < min_prec) break;
            if (t.tag == .question) {
                _ = self.next();
                const tv = try self.parseExpr(0);
                _ = try self.expect(.colon, "':'");
                const fv = try self.parseExpr(info.prec);
                lhs = try self.addExpr(.{ .ternary = .{ .c = lhs, .t = tv, .f = fv } }, t.start);
                continue;
            }
            _ = self.next();
            if (info.op == .assign or isAssignOp(info.op)) {
                const rhs = try self.parseExpr(info.prec);
                lhs = try self.addExpr(.{ .binary = .{ .op = info.op, .l = lhs, .r = rhs } }, t.start);
                continue;
            }
            const rhs = try self.parseExpr(info.prec + 1);
            lhs = try self.addExpr(.{ .binary = .{ .op = info.op, .l = lhs, .r = rhs } }, t.start);
        }
        return lhs;
    }

    fn isCoutExpr(self: *Parser, id: Eid) bool {
        const e = self.exprs.items[id];
        if (e.kind != .ident) return false;
        const n = e.kind.ident;
        return std.mem.eql(u8, n, "cout") or std.mem.eql(u8, n, "cerr") or
            std.mem.eql(u8, n, "std::cout") or std.mem.eql(u8, n, "std::cerr");
    }

    fn parseCoutChain(self: *Parser, first: Eid, off: usize) CompileError!Eid {
        var ops: std.array_list.Managed(Eid) = .init(self.gpa);
        defer ops.deinit();
        try ops.append(first);
        while (self.eat(.lt_lt) != null) {
            const op = try self.parseExpr(11);
            const e = self.exprs.items[op];
            if (e.kind == .ident and (std.mem.eql(u8, e.kind.ident, "endl") or std.mem.eql(u8, e.kind.ident, "std::endl"))) {
                try ops.append(try self.addExpr(.endl, e.off));
            } else {
                try ops.append(op);
            }
        }
        return self.addExpr(.{ .cout_chain = try ops.toOwnedSlice() }, off);
    }

    const BinInfo = struct { op: BinOp, prec: u8 };

    fn binInfo(tag: lex.Tag) ?BinInfo {
        return switch (tag) {
            .eq => .{ .op = .assign, .prec = 1 },
            .plus_eq => .{ .op = .add_assign, .prec = 1 },
            .minus_eq => .{ .op = .sub_assign, .prec = 1 },
            .star_eq => .{ .op = .mul_assign, .prec = 1 },
            .slash_eq => .{ .op = .div_assign, .prec = 1 },
            .percent_eq => .{ .op = .rem_assign, .prec = 1 },
            .lt_lt_eq => .{ .op = .shl_assign, .prec = 1 },
            .gt_gt_eq => .{ .op = .shr_assign, .prec = 1 },
            .amp_eq => .{ .op = .band_assign, .prec = 1 },
            .pipe_eq => .{ .op = .bor_assign, .prec = 1 },
            .caret_eq => .{ .op = .bxor_assign, .prec = 1 },
            .question => .{ .op = .assign, .prec = 2 },
            .pipe_pipe => .{ .op = .log_or, .prec = 3 },
            .amp_amp => .{ .op = .log_and, .prec = 4 },
            .pipe => .{ .op = .bit_or, .prec = 5 },
            .caret => .{ .op = .bit_xor, .prec = 6 },
            .amp => .{ .op = .bit_and, .prec = 7 },
            .eq_eq => .{ .op = .eq, .prec = 8 },
            .bang_eq => .{ .op = .ne, .prec = 8 },
            .lt => .{ .op = .lt, .prec = 9 },
            .lt_eq => .{ .op = .le, .prec = 9 },
            .gt => .{ .op = .gt, .prec = 9 },
            .gt_eq => .{ .op = .ge, .prec = 9 },
            .lt_lt => .{ .op = .shl, .prec = 10 },
            .gt_gt => .{ .op = .shr, .prec = 10 },
            .plus => .{ .op = .add, .prec = 11 },
            .minus => .{ .op = .sub, .prec = 11 },
            .star => .{ .op = .mul, .prec = 12 },
            .slash => .{ .op = .div, .prec = 12 },
            .percent => .{ .op = .rem, .prec = 12 },
            else => null,
        };
    }

    fn isAssignOp(op: BinOp) bool {
        return switch (op) {
            .add_assign, .sub_assign, .mul_assign, .div_assign, .rem_assign, .shl_assign, .shr_assign, .band_assign, .bor_assign, .bxor_assign => true,
            else => false,
        };
    }

    fn parseUnary(self: *Parser) CompileError!Eid {
        const t = self.peek();
        switch (t.tag) {
            .bang => {
                _ = self.next();
                const x = try self.parseUnary();
                return self.addExpr(.{ .unary = .{ .op = .not, .x = x } }, t.start);
            },
            .tilde => {
                _ = self.next();
                const x = try self.parseUnary();
                return self.addExpr(.{ .unary = .{ .op = .bnot, .x = x } }, t.start);
            },
            .minus => {
                _ = self.next();
                const x = try self.parseUnary();
                return self.addExpr(.{ .unary = .{ .op = .neg, .x = x } }, t.start);
            },
            .plus => {
                _ = self.next();
                return self.parseUnary();
            },
            .star => {
                _ = self.next();
                const x = try self.parseUnary();
                return self.addExpr(.{ .unary = .{ .op = .deref, .x = x } }, t.start);
            },
            .amp => {
                _ = self.next();
                const x = try self.parseUnary();
                return self.addExpr(.{ .unary = .{ .op = .addrof, .x = x } }, t.start);
            },
            .plus_plus => {
                _ = self.next();
                const x = try self.parseUnary();
                return self.addExpr(.{ .unary = .{ .op = .pre_inc, .x = x } }, t.start);
            },
            .minus_minus => {
                _ = self.next();
                const x = try self.parseUnary();
                return self.addExpr(.{ .unary = .{ .op = .pre_dec, .x = x } }, t.start);
            },
            else => return self.parsePostfix(),
        }
    }

    fn parsePostfix(self: *Parser) CompileError!Eid {
        var base = try self.parsePrimary();
        while (true) {
            const t = self.peek();
            switch (t.tag) {
                .l_paren => {
                    const args = try self.parseCallArgs();
                    base = try self.addExpr(.{ .call = .{ .callee = base, .args = args } }, t.start);
                },
                .l_bracket => {
                    _ = self.next();
                    const idx = try self.parseExpr(0);
                    _ = try self.expect(.r_bracket, "']'");
                    base = try self.addExpr(.{ .index = .{ .base = base, .idx = idx } }, t.start);
                },
                .dot, .arrow => {
                    const arrow = t.tag == .arrow;
                    _ = self.next();
                    const name_tok = try self.expect(.ident, "member name");
                    const mname = name_tok.text(self.source);
                    if (self.peek().tag == .l_paren) {
                        const args = try self.parseCallArgs();
                        base = try self.addExpr(.{ .method_call = .{ .obj = base, .arrow = arrow, .name = mname, .args = args } }, t.start);
                    } else {
                        base = try self.addExpr(.{ .field = .{ .base = base, .arrow = arrow, .name = mname } }, t.start);
                    }
                },
                .colon_colon => {
                    // `a::b` — fold into a qualified ident (namespace/type scope).
                    _ = self.next();
                    const rhs = try self.expect(.ident, "name after '::'");
                    const lhs_text = try self.exprText(base);
                    const joined = try std.fmt.allocPrint(self.gpa, "{s}::{s}", .{ lhs_text, rhs.text(self.source) });
                    base = try self.addExpr(.{ .ident = joined }, t.start);
                },
                .plus_plus => {
                    _ = self.next();
                    base = try self.addExpr(.{ .unary = .{ .op = .post_inc, .x = base } }, t.start);
                },
                .minus_minus => {
                    _ = self.next();
                    base = try self.addExpr(.{ .unary = .{ .op = .post_dec, .x = base } }, t.start);
                },
                else => return base,
            }
        }
    }

    fn exprText(self: *Parser, id: Eid) CompileError![]const u8 {
        const e = self.exprs.items[id];
        switch (e.kind) {
            .ident => |n| return n,
            else => return self.err(e.off, "expected a name here", .{}),
        }
    }

    fn parseCallArgs(self: *Parser) CompileError![]Eid {
        _ = try self.expect(.l_paren, "'('");
        var args: std.array_list.Managed(Eid) = .init(self.gpa);
        defer args.deinit();
        if (self.eat(.r_paren) == null) {
            while (true) {
                try args.append(try self.parseExpr(0));
                if (self.eat(.comma) != null) continue;
                break;
            }
            _ = try self.expect(.r_paren, "')'");
        }
        return try args.toOwnedSlice();
    }

    fn parsePrimary(self: *Parser) CompileError!Eid {
        const t = self.peek();
        switch (t.tag) {
            .int_lit => {
                _ = self.next();
                return self.addExpr(.{ .int_lit = t.text(self.source) }, t.start);
            },
            .float_lit => {
                _ = self.next();
                return self.addExpr(.{ .float_lit = t.text(self.source) }, t.start);
            },
            .str_lit => {
                _ = self.next();
                return self.addExpr(.{ .str_lit = t.text(self.source) }, t.start);
            },
            .char_lit => {
                _ = self.next();
                return self.addExpr(.{ .char_lit = t.text(self.source) }, t.start);
            },
            .l_paren => {
                // C-style cast `(T)x` or parenthesized expr.
                const saved = self.pos;
                const saved_e = self.exprs.items.len;
                _ = self.next();
                if (self.peek().tag == .ident or self.peek().tag == .colon_colon) {
                    const ty = self.parseType() catch {
                        self.pos = saved;
                        self.exprs.shrinkRetainingCapacity(saved_e);
                        return self.parseParenExpr();
                    };
                    if (self.eat(.r_paren) != null) {
                        // Cast — but `(x)` where x is a type name used as expr?
                        // `(T)` alone is invalid; require an operand.
                        if (self.peek().tag == .l_brace) {
                            // Compound literal `(T){...}`: treat as init list.
                            _ = self.next();
                            var items: std.array_list.Managed(Eid) = .init(self.gpa);
                            defer items.deinit();
                            if (self.eat(.r_brace) == null) {
                                while (true) {
                                    try items.append(try self.parseExpr(0));
                                    if (self.eat(.comma) != null) continue;
                                    break;
                                }
                                _ = try self.expect(.r_brace, "'}'");
                            }
                            return self.addExpr(.{ .init_list = try items.toOwnedSlice() }, t.start);
                        }
                        const x = try self.parseUnary();
                        return self.addExpr(.{ .cast = .{ .ty = ty, .x = x } }, t.start);
                    }
                    self.pos = saved;
                    self.exprs.shrinkRetainingCapacity(saved_e);
                    return self.parseParenExpr();
                }
                self.pos = saved;
                return self.parseParenExpr();
            },
            .ident => {
                const word = t.text(self.source);
                if (std.mem.eql(u8, word, "true")) {
                    _ = self.next();
                    return self.addExpr(.{ .bool_lit = true }, t.start);
                }
                if (std.mem.eql(u8, word, "false")) {
                    _ = self.next();
                    return self.addExpr(.{ .bool_lit = false }, t.start);
                }
                if (std.mem.eql(u8, word, "nullptr")) {
                    _ = self.next();
                    return self.addExpr(.null_lit, t.start);
                }
                if (std.mem.eql(u8, word, "this")) {
                    _ = self.next();
                    return self.addExpr(.this_, t.start);
                }
                if (std.mem.eql(u8, word, "new")) {
                    return self.parseNew();
                }
                if (std.mem.eql(u8, word, "delete")) {
                    _ = self.next();
                    var is_array = false;
                    if (self.eat(.l_bracket) != null) {
                        _ = try self.expect(.r_bracket, "']'");
                        is_array = true;
                    }
                    const x = try self.parseUnary();
                    return self.addExpr(.{ .delete_ = .{ .x = x, .is_array = is_array } }, t.start);
                }
                if (std.mem.eql(u8, word, "sizeof")) {
                    return self.parseSizeof();
                }
                if (std.mem.eql(u8, word, "static_cast") or std.mem.eql(u8, word, "const_cast") or std.mem.eql(u8, word, "reinterpret_cast") or std.mem.eql(u8, word, "dynamic_cast")) {
                    _ = self.next();
                    if (self.eat(.lt) == null) return self.err(t.start, "expected '<' after cast operator", .{});
                    const ty = try self.parseType();
                    _ = try self.expect(.gt, "'>'");
                    _ = try self.expect(.l_paren, "'('");
                    const x = try self.parseExpr(0);
                    _ = try self.expect(.r_paren, "')'");
                    return self.addExpr(.{ .cast = .{ .ty = ty, .x = x } }, t.start);
                }
                if (std.mem.eql(u8, word, "throw")) {
                    return self.err(t.start, "exceptions are not supported in v0.1", .{});
                }
                if (std.mem.eql(u8, word, "operator")) {
                    return self.err(t.start, "operator overloading is not supported in v0.1", .{});
                }
                if (std.mem.eql(u8, word, "alignof") or std.mem.eql(u8, word, "noexcept") or std.mem.eql(u8, word, "decltype")) {
                    return self.err(t.start, "'{s}' is not supported in v0.1", .{word});
                }
                _ = self.next();
                // Enum constant?
                for (self.enum_consts.items) |ec| {
                    if (std.mem.eql(u8, ec.name, word)) {
                        const txt = try std.fmt.allocPrint(self.gpa, "{d}", .{ec.value});
                        return self.addExpr(.{ .int_lit = txt }, t.start);
                    }
                }
                return self.addExpr(.{ .ident = word }, t.start);
            },
            else => return self.err(t.start, "expected an expression", .{}),
        }
    }

    fn parseParenExpr(self: *Parser) CompileError!Eid {
        _ = try self.expect(.l_paren, "'('");
        const e = try self.parseExpr(0);
        _ = try self.expect(.r_paren, "')'");
        return e;
    }

    fn parseNew(self: *Parser) CompileError!Eid {
        const off = self.peek().start;
        _ = self.next(); // new
        // Placement new `new (p) T` — unsupported.
        if (self.peek().tag == .l_paren) {
            return self.err(self.peek().start, "placement new is not supported in v0.1", .{});
        }
        const ty = try self.parseType();
        var array_len: ?Eid = null;
        if (self.eat(.l_bracket) != null) {
            array_len = try self.parseExpr(0);
            _ = try self.expect(.r_bracket, "']'");
        }
        var args: []Eid = &.{};
        if (self.eat(.l_paren) != null) {
            var list: std.array_list.Managed(Eid) = .init(self.gpa);
            defer list.deinit();
            if (self.eat(.r_paren) == null) {
                while (true) {
                    try list.append(try self.parseExpr(0));
                    if (self.eat(.comma) != null) continue;
                    break;
                }
                _ = try self.expect(.r_paren, "')'");
            }
            args = try list.toOwnedSlice();
        } else if (self.eat(.l_brace) != null) {
            var list: std.array_list.Managed(Eid) = .init(self.gpa);
            defer list.deinit();
            if (self.eat(.r_brace) == null) {
                while (true) {
                    try list.append(try self.parseExpr(0));
                    if (self.eat(.comma) != null) continue;
                    break;
                }
                _ = try self.expect(.r_brace, "'}'");
            }
            args = try list.toOwnedSlice();
        }
        return self.addExpr(.{ .new_ = .{ .ty = ty, .args = args, .array_len = array_len } }, off);
    }

    fn parseSizeof(self: *Parser) CompileError!Eid {
        const off = self.peek().start;
        _ = self.next();
        _ = try self.expect(.l_paren, "'('");
        if (self.peek().tag == .ident or self.peek().tag == .colon_colon) {
            const saved = self.pos;
            const saved_e = self.exprs.items.len;
            const ty = self.parseType() catch {
                self.pos = saved;
                self.exprs.shrinkRetainingCapacity(saved_e);
                _ = try self.parseExpr(0);
                _ = try self.expect(.r_paren, "')'");
                return self.err(off, "sizeof(expr) is not supported in v0.1 (use sizeof(Type))", .{});
            };
            _ = try self.expect(.r_paren, "')'");
            return self.addExpr(.{ .sizeof_ty = ty }, off);
        }
        _ = try self.parseExpr(0);
        _ = try self.expect(.r_paren, "')'");
        return self.err(off, "sizeof(expr) is not supported in v0.1 (use sizeof(Type))", .{});
    }
};

// ---------------------------------------------------------------------------
// Literal helpers
// ---------------------------------------------------------------------------

pub fn parseIntLit(raw: []const u8) !i64 {
    // Strip digit separators and suffixes.
    var buf: [64]u8 = undefined;
    var n: usize = 0;
    var i: usize = 0;
    var base: u8 = 10;
    if (raw.len >= 2 and raw[0] == '0' and (raw[1] == 'x' or raw[1] == 'X')) {
        base = 16;
        i = 2;
    } else if (raw.len >= 2 and raw[0] == '0' and (raw[1] == 'b' or raw[1] == 'B')) {
        base = 2;
        i = 2;
    } else if (raw.len > 1 and raw[0] == '0' and raw[1] >= '0' and raw[1] <= '7') {
        base = 8;
        i = 1;
    }
    while (i < raw.len) : (i += 1) {
        const c = raw[i];
        if (c == '\'') continue;
        if (base == 10 and (c == 'u' or c == 'U' or c == 'l' or c == 'L' or c == 'z' or c == 'Z')) break;
        if (base == 16 and !(c >= '0' and c <= '9') and !(c >= 'a' and c <= 'f') and !(c >= 'A' and c <= 'F')) break;
        if (base == 8 and !(c >= '0' and c <= '7')) break;
        if (base == 2 and !(c == '0' or c == '1')) break;
        if (n >= buf.len) return error.Overflow;
        buf[n] = c;
        n += 1;
    }
    return try std.fmt.parseInt(i64, buf[0..n], base);
}

/// Decode a char literal body (no quotes) to its code value.
pub fn charValue(raw_inner: []const u8) !u32 {
    if (raw_inner.len == 0) return error.BadChar;
    if (raw_inner[0] != '\\') {
        // UTF-8 first codepoint.
        const len = try std.unicode.utf8ByteSequenceLength(raw_inner[0]);
        if (len > raw_inner.len) return error.BadChar;
        return try std.unicode.utf8Decode(raw_inner[0..len]);
    }
    if (raw_inner.len < 2) return error.BadChar;
    switch (raw_inner[1]) {
        'n' => return '\n',
        't' => return '\t',
        'r' => return '\r',
        '0' => return 0,
        '\\' => return '\\',
        '\'' => return '\'',
        '"' => return '"',
        'x' => {
            const digits = raw_inner[2..];
            if (digits.len == 0) return error.BadChar;
            return try std.fmt.parseInt(u32, digits, 16);
        },
        else => return error.BadChar,
    }
}

/// Unescape a string literal body (no quotes) for SA utf8:"..." emission.
/// Returns owned bytes; caller frees.
pub fn unescapeString(gpa: std.mem.Allocator, inner: []const u8) ![]u8 {
    var out: std.array_list.Managed(u8) = .init(gpa);
    errdefer out.deinit();
    var i: usize = 0;
    while (i < inner.len) {
        const c = inner[i];
        if (c != '\\') {
            try out.append(c);
            i += 1;
            continue;
        }
        i += 1;
        if (i >= inner.len) return error.BadEscape;
        switch (inner[i]) {
            'n' => try out.append('\n'),
            't' => try out.append('\t'),
            'r' => try out.append('\r'),
            '0' => try out.append(0),
            '\\' => try out.append('\\'),
            '"' => try out.append('"'),
            '\'' => try out.append('\''),
            'x' => {
                if (i + 2 >= inner.len) return error.BadEscape;
                const v = try std.fmt.parseInt(u8, inner[i + 1 .. i + 3], 16);
                try out.append(v);
                i += 2;
            },
            else => return error.BadEscape,
        }
        i += 1;
    }
    return try out.toOwnedSlice();
}

/// Strip quotes from a str_lit token; handles R"(...)" raw form.
pub fn strInner(raw: []const u8) []const u8 {
    if (raw.len >= 4 and raw[0] == 'R' and raw[1] == '"' and raw[2] == '(') {
        return raw[3 .. raw.len - 2];
    }
    return raw[1 .. raw.len - 1];
}

test "parser handles a small program" {
    const gpa = std.testing.allocator;
    const src =
        \\#include <iostream>
        \\int add(int a, int b) { return a + b; }
        \\int main() { int x = add(1, 2); return x; }
    ;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const agpa = arena.allocator();
    var lex1 = lex.Lexer.init(src);
    var diag = Diag.init(agpa);
    const toks = try lex1.tokenize(agpa, &diag);
    var p = Parser.create(agpa, src, toks, &diag);
    defer p.deinit();
    try p.parseUnit();
    try std.testing.expectEqual(@as(usize, 2), p.funcs.items.len);
    try std.testing.expectEqualStrings("add", p.funcs.items[0].name);
    try std.testing.expectEqualStrings("main", p.funcs.items[1].name);
}

test "parser handles class with method and cout" {
    const gpa = std.testing.allocator;
    const src =
        \\struct Point { int x; int y; int sum() { return x + y; } };
        \\int main() { Point p{1, 2}; std::cout << p.sum() << std::endl; return 0; }
    ;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const agpa = arena.allocator();
    var lex1 = lex.Lexer.init(src);
    var diag = Diag.init(agpa);
    const toks = try lex1.tokenize(agpa, &diag);
    var p = Parser.create(agpa, src, toks, &diag);
    defer p.deinit();
    try p.parseUnit();
    try std.testing.expectEqual(@as(usize, 1), p.structs.items.len);
    try std.testing.expectEqual(@as(usize, 2), p.funcs.items.len);
}

test "parser refuses template-id in param type with explicit message" {
    // Regression: folly HazptrDomain.h:49
    // `void hazptr_inline_executor_add(folly::Function<void()> func);`
    // used to fail with cryptic `expected ')'`; it must name templates.
    const gpa = std.testing.allocator;
    const src = "void f(folly::Function<void()> cb) { return; }\n";
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const agpa = arena.allocator();
    var lex1 = lex.Lexer.init(src);
    var diag = Diag.init(agpa);
    const toks = try lex1.tokenize(agpa, &diag);
    var p = Parser.create(agpa, src, toks, &diag);
    defer p.deinit();
    const r = p.parseUnit();
    try std.testing.expectError(error.ParseError, r);
    try std.testing.expect(std.mem.indexOf(u8, diag.msg, "templates are not supported") != null);
}
