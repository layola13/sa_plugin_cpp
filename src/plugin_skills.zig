const std = @import("std");
const plugin_api = @import("plugin_api");

pub const skills: []const plugin_api.SkillSection = &.{
    .{
        .name = "cpp",
        .summary = "Compile C++17-subset sources to SA text (check/build/build-exe/test).",
        .items = &.{
            "cpp init [path]: scaffold a minimal C++ project (cpp.mod + src/main.cpp).",
            "cpp check [file]: lex/parse/typecheck a .cpp file, no output.",
            "cpp build [file] [--out file.sa]: emit SA text.",
            "cpp build-exe [file] [-o exe]: emit SA then delegate to host `sa build-exe`.",
            "cpp test [file]: emit SA then delegate to host `sa test`.",
            "Subset: free functions, if/while/do/for/switch, return/break/continue, struct/class POD + methods, fixed arrays, cout<< for ints/strings, namespaces; no templates/inheritance/exceptions/lambdas/vector/string yet.",
        },
    },
};

pub fn writeSkillsText(out: *std.Io.Writer) !void {
    for (skills) |section| {
        try out.print("## {s}\n{s}\n", .{ section.name, section.summary });
        for (section.items) |item| {
            try out.print("- {s}\n", .{item});
        }
    }
    try out.flush();
}

pub fn writeSkillsJson(out: *std.Io.Writer) !void {
    try out.writeAll("{\"skills\":[");
    for (skills, 0..) |section, si| {
        if (si != 0) try out.writeAll(",");
        try out.print("{{\"name\":\"{s}\",\"summary\":\"", .{section.name});
        try writeJsonEscaped(out, section.summary);
        try out.writeAll("\",\"items\":[");
        for (section.items, 0..) |item, ii| {
            if (ii != 0) try out.writeAll(",");
            try out.writeAll("\"");
            try writeJsonEscaped(out, item);
            try out.writeAll("\"");
        }
        try out.writeAll("]}");
    }
    try out.writeAll("]}\n");
    try out.flush();
}

fn writeJsonEscaped(out: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try out.writeAll("\\\""),
            '\\' => try out.writeAll("\\\\"),
            '\n' => try out.writeAll("\\n"),
            '\r' => try out.writeAll("\\r"),
            '\t' => try out.writeAll("\\t"),
            else => try out.writeAll(&.{c}),
        }
    }
}
