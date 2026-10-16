const std = @import("std");

/// Shared compile diagnostic: stages set `msg` (owned) and fail with a
/// `CompileError`. Callers print `msg` at `off` and free it.
pub const CompileError = error{
    LexError,
    ParseError,
    TypeError,
    CodegenError,
    IoError,
    OutOfMemory,
};

pub const Diag = struct {
    gpa: std.mem.Allocator,
    msg: []u8 = &.{},
    off: usize = 0,

    pub fn init(gpa: std.mem.Allocator) Diag {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Diag) void {
        if (self.msg.len != 0) self.gpa.free(self.msg);
        self.msg = &.{};
    }

    pub fn fail(self: *Diag, off: usize, comptime fmt: []const u8, args: anytype) void {
        if (self.msg.len != 0) self.gpa.free(self.msg);
        self.msg = std.fmt.allocPrint(self.gpa, fmt, args) catch &.{};
        self.off = off;
    }

    /// Line number (1-based) for a byte offset.
    pub fn lineOf(source: []const u8, off: usize) usize {
        var line: usize = 1;
        const end: usize = @min(off, source.len);
        for (source[0..end]) |c| {
            if (c == '\n') line += 1;
        }
        return line;
    }
};

pub const Tag = enum {
    eof,
    ident,
    int_lit,
    float_lit,
    str_lit,
    char_lit,
    directive, // a full #... physical line (includes + defines skipped by parser)
    l_paren, // (
    r_paren, // )
    l_brace, // {
    r_brace, // }
    l_bracket, // [
    r_bracket, // ]
    semi, // ;
    comma, // ,
    dot, // .
    colon, // :
    colon_colon, // ::
    question, // ?
    tilde, // ~
    bang, // !
    bang_eq, // !=
    plus, // +
    plus_plus, // ++
    plus_eq, // +=
    minus, // -
    minus_minus, // --
    minus_eq, // -=
    arrow, // ->
    star, // *
    star_eq, // *=
    slash, // /
    slash_eq, // /=
    percent, // %
    percent_eq, // %=
    lt, // <
    lt_eq, // <=
    lt_lt, // <<
    lt_lt_eq, // <<=
    gt, // >
    gt_eq, // >=
    gt_gt, // >>
    gt_gt_eq, // >>=
    eq, // =
    eq_eq, // ==
    amp, // &
    amp_amp, // &&
    amp_eq, // &=
    pipe, // |
    pipe_pipe, // ||
    pipe_eq, // |=
    caret, // ^
    caret_eq, // ^=
    ellipsis, // ...
};

pub const Token = struct {
    tag: Tag,
    start: usize,
    end: usize,

    pub fn text(self: Token, source: []const u8) []const u8 {
        return source[self.start..self.end];
    }
};

/// C++ keywords of the v0.1 subset. Anything else lexes as `ident`.
pub fn isKeyword(word: []const u8) bool {
    const kws = [_][]const u8{
        "alignas", "alignof", "auto",  "bool",      "break",
        "case",    "catch",   "char",  "class",     "const",
        "concept", "consteval", "constexpr", "continue", "decltype",
        "default", "delete",  "do",    "double",    "else",
        "enum",    "explicit", "export", "extern",   "false",
        "float",   "for",     "friend", "goto",     "if",
        "inline",  "int",     "long",  "mutable",   "namespace",
        "new",     "noexcept", "nullptr", "operator", "private",
        "protected", "public", "register", "return", "short",
        "signed",  "sizeof",  "static", "static_assert", "struct",
        "switch",  "template", "this",  "thread_local", "throw",
        "true",    "try",     "typedef", "typename", "union",
        "unsigned", "using",   "virtual", "void",    "volatile",
        "while",
    };
    for (kws) |k| {
        if (std.mem.eql(u8, word, k)) return true;
    }
    return false;
}

pub const Lexer = struct {
    source: []const u8,
    pos: usize = 0,

    pub fn init(source: []const u8) Lexer {
        return .{ .source = source };
    }

    pub fn tokenize(self: *Lexer, gpa: std.mem.Allocator, diag: *Diag) CompileError![]Token {
        var list: std.array_list.Managed(Token) = .init(gpa);
        errdefer list.deinit();
        const s = self.source;
        var i: usize = 0;
        while (i < s.len) {
            const c = s[i];
            if (c == ' ' or c == '\t' or c == '\r' or c == '\n' or c == '\x0b' or c == '\x0c') {
                i += 1;
                continue;
            }
            if (c == '/' and i + 1 < s.len and s[i + 1] == '/') {
                while (i < s.len and s[i] != '\n') : (i += 1) {}
                continue;
            }
            if (c == '/' and i + 1 < s.len and s[i + 1] == '*') {
                i += 2;
                var closed = false;
                while (i + 1 < s.len) {
                    if (s[i] == '*' and s[i + 1] == '/') {
                        i += 2;
                        closed = true;
                        break;
                    }
                    i += 1;
                }
                if (!closed) {
                    diag.fail(i, "unterminated block comment", .{});
                    return error.LexError;
                }
                continue;
            }
            if (c == '#') {
                // Preprocessor physical line, honouring backslash continuations.
                const start = i;
                while (i < s.len) {
                    if (s[i] == '\\' and i + 1 < s.len and s[i + 1] == '\n') {
                        i += 2;
                        continue;
                    }
                    if (s[i] == '\n') break;
                    i += 1;
                }
                try list.append(.{ .tag = .directive, .start = start, .end = i });
                continue;
            }
            if (c == '"') {
                const start = i;
                i += 1;
                var ok = false;
                while (i < s.len) {
                    if (s[i] == '\\') {
                        i += 2;
                        continue;
                    }
                    if (s[i] == '"') {
                        i += 1;
                        ok = true;
                        break;
                    }
                    if (s[i] == '\n') break;
                    i += 1;
                }
                if (!ok) {
                    _ = diag.fail(start, "unterminated string literal", .{});
                    return error.LexError;
                }
                try list.append(.{ .tag = .str_lit, .start = start, .end = i });
                continue;
            }
            if (c == 'R' and i + 1 < s.len and s[i + 1] == '"' and i + 2 < s.len and s[i + 2] == '(') {
                // Minimal raw string R"(...)" (empty delimiter only).
                const start = i;
                i += 3;
                var ok = false;
                while (i + 1 < s.len) {
                    if (s[i] == ')' and s[i + 1] == '"') {
                        i += 2;
                        ok = true;
                        break;
                    }
                    i += 1;
                }
                if (!ok) {
                    _ = diag.fail(start, "unterminated raw string (only R\"(...)\" is supported)", .{});
                    return error.LexError;
                }
                try list.append(.{ .tag = .str_lit, .start = start, .end = i });
                continue;
            }
            if (c == '\'') {
                const start = i;
                i += 1;
                if (i < s.len and s[i] == '\\') i += 1;
                i += 1; // the character itself
                if (i >= s.len or s[i] != '\'') {
                    _ = diag.fail(start, "unterminated character literal", .{});
                    return error.LexError;
                }
                i += 1;
                try list.append(.{ .tag = .char_lit, .start = start, .end = i });
                continue;
            }
            if (isDigit(c) or (c == '.' and i + 1 < s.len and isDigit(s[i + 1]))) {
                const start = i;
                const is_float = lexNumber(s, &i);
                try list.append(.{ .tag = if (is_float) .float_lit else .int_lit, .start = start, .end = i });
                continue;
            }
            if (isAlpha(c) or c == '_' or c == '$') {
                const start = i;
                while (i < s.len and (isAlphaNum(s[i]) or s[i] == '_' or s[i] == '$')) : (i += 1) {}
                try list.append(.{ .tag = .ident, .start = start, .end = i });
                continue;
            }
            const start = i;
            const two: u16 = if (i + 1 < s.len) (@as(u16, c) << 8 | s[i + 1]) else (@as(u16, c) << 8);
            const three_eq = i + 2 < s.len and s[i + 2] == '=';
            const tag: ?Tag = switch (two) {
                str2(':', ':') => .colon_colon,
                str2('=', '=') => .eq_eq,
                str2('!', '=') => .bang_eq,
                str2('<', '=') => .lt_eq,
                str2('>', '=') => .gt_eq,
                str2('&', '&') => .amp_amp,
                str2('|', '|') => .pipe_pipe,
                str2('+', '+') => .plus_plus,
                str2('-', '-') => if (s[i + 1] == '>') Tag.arrow else .minus_minus,
                str2('+', '=') => .plus_eq,
                str2('-', '=') => .minus_eq,
                str2('*', '=') => .star_eq,
                str2('/', '=') => .slash_eq,
                str2('%', '=') => .percent_eq,
                str2('&', '=') => .amp_eq,
                str2('|', '=') => .pipe_eq,
                str2('^', '=') => .caret_eq,
                str2('<', '<') => if (three_eq) blk: {
                    i += 3;
                    break :blk Tag.lt_lt_eq;
                } else .lt_lt,
                str2('>', '>') => if (three_eq) blk: {
                    i += 3;
                    break :blk Tag.gt_gt_eq;
                } else .gt_gt,
                else => null,
            };
            if (tag) |t| {
                if (t != .lt_lt_eq and t != .gt_gt_eq) i += 2;
                try list.append(.{ .tag = t, .start = start, .end = i });
                continue;
            }
            if (c == '.' and i + 2 < s.len and s[i + 1] == '.' and s[i + 2] == '.') {
                i += 3;
                try list.append(.{ .tag = .ellipsis, .start = start, .end = i });
                continue;
            }
            const single: ?Tag = switch (c) {
                '(' => .l_paren,
                ')' => .r_paren,
                '{' => .l_brace,
                '}' => .r_brace,
                '[' => .l_bracket,
                ']' => .r_bracket,
                ';' => .semi,
                ',' => .comma,
                '.' => .dot,
                ':' => .colon,
                '?' => .question,
                '~' => .tilde,
                '!' => .bang,
                '+' => .plus,
                '-' => .minus,
                '*' => .star,
                '/' => .slash,
                '%' => .percent,
                '<' => .lt,
                '>' => .gt,
                '=' => .eq,
                '&' => .amp,
                '|' => .pipe,
                '^' => .caret,
                else => null,
            };
            if (single) |t| {
                i += 1;
                try list.append(.{ .tag = t, .start = start, .end = i });
                continue;
            }
            _ = diag.fail(start, "unexpected character '{c}'", .{c});
            return error.LexError;
        }
        try list.append(.{ .tag = .eof, .start = s.len, .end = s.len });
        return try list.toOwnedSlice();
    }
};

fn str2(a: u8, b: u8) u16 {
    return @as(u16, a) << 8 | b;
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}

fn isAlphaNum(c: u8) bool {
    return isAlpha(c) or isDigit(c);
}

/// Lex a numeric literal starting at s[*i]; advances *i past it (and any
/// integer/float suffix). Returns true for float.
fn lexNumber(s: []const u8, i: *usize) bool {
    var is_float = false;
    if (s[i.*] == '0' and i.* + 1 < s.len and (s[i.* + 1] == 'x' or s[i.* + 1] == 'X')) {
        i.* += 2;
        while (i.* < s.len and (isAlphaNum(s[i.*]) or s[i.*] == '\'')) : (i.* += 1) {}
        return false;
    }
    if (s[i.*] == '0' and i.* + 1 < s.len and (s[i.* + 1] == 'b' or s[i.* + 1] == 'B')) {
        i.* += 2;
        while (i.* < s.len and (s[i.*] == '0' or s[i.*] == '1' or s[i.*] == '\'')) : (i.* += 1) {}
        return false;
    }
    while (i.* < s.len and (isDigit(s[i.*]) or s[i.*] == '\'')) : (i.* += 1) {}
    if (i.* < s.len and s[i.*] == '.' and !(i.* + 1 < s.len and s[i.* + 1] == '.')) {
        is_float = true;
        i.* += 1;
        while (i.* < s.len and (isDigit(s[i.*]) or s[i.*] == '\'')) : (i.* += 1) {}
    }
    if (i.* < s.len and (s[i.*] == 'e' or s[i.*] == 'E')) {
        is_float = true;
        i.* += 1;
        if (i.* < s.len and (s[i.*] == '+' or s[i.*] == '-')) i.* += 1;
        while (i.* < s.len and (isDigit(s[i.*]) or s[i.*] == '\'')) : (i.* += 1) {}
    }
    // Suffixes: uUlLfF (and z/Z for size_t-ish spellings).
    while (i.* < s.len and (s[i.*] == 'u' or s[i.*] == 'U' or s[i.*] == 'l' or s[i.*] == 'L' or s[i.*] == 'f' or s[i.*] == 'F' or s[i.*] == 'z' or s[i.*] == 'Z')) : (i.* += 1) {
        if (s[i.*] == 'f' or s[i.*] == 'F') is_float = true;
    }
    return is_float;
}

test "lexer tokenizes a small function" {
    const gpa = std.testing.allocator;
    const src = "int add(int a, int b) { return a + b; }\n";
    var lex = Lexer.init(src);
    var diag = Diag.init(gpa);
    defer diag.deinit();
    const toks = try lex.tokenize(gpa, &diag);
    defer gpa.free(toks);
    // int add ( int a , int b ) { return a + b ; } + eof = 17
    try std.testing.expectEqual(@as(usize, 17), toks.len);
    try std.testing.expect(toks[0].tag == .ident);
    try std.testing.expectEqualStrings("int", toks[0].text(src));
    try std.testing.expectEqualStrings("add", toks[1].text(src));
}

test "lexer handles cout shifts and directives" {
    const gpa = std.testing.allocator;
    const src = "#include <iostream>\nstd::cout << 42 << x;\n";
    var lex = Lexer.init(src);
    var diag = Diag.init(gpa);
    defer diag.deinit();
    const toks = try lex.tokenize(gpa, &diag);
    defer gpa.free(toks);
    try std.testing.expect(toks[0].tag == .directive);
    try std.testing.expect(toks[1].tag == .ident); // std
    try std.testing.expect(toks[2].tag == .colon_colon);
    try std.testing.expect(toks[4].tag == .lt_lt);
}
