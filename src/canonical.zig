const std = @import("std");
const types = @import("types.zig");

const Writer = std.Io.Writer;

pub const CanonicalError = error{
    InvalidFloat,
    UnsupportedType,
    UnsupportedPointer,
    UnsupportedUnion,
};

fn escapeString(w: *Writer, s: []const u8) Writer.Error!void {
    try w.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try w.print("\\\"", .{}),
            '\\' => try w.print("\\\\", .{}),
            '\n' => try w.print("\\n", .{}),
            '\r' => try w.print("\\r", .{}),
            '\t' => try w.print("\\t", .{}),
            else => if (c < 0x20) {
                try w.print("\\u{d:0>4}", .{c});
            } else {
                try w.writeByte(c);
            },
        }
    }
    try w.writeByte('"');
}

fn writeHash(w: *Writer, hash: types.Hash) Writer.Error!void {
    const hex = types.hashToPrefixed(hash);
    try w.writeByte('"');
    try w.writeAll(&hex);
    try w.writeByte('"');
}

fn sortedFields(comptime T: type) [std.meta.fields(T).len]std.builtin.Type.StructField {
    const fields = std.meta.fields(T);
    var sorted: [fields.len]std.builtin.Type.StructField = undefined;
    inline for (fields, 0..) |field, i| {
        sorted[i] = field;
    }
    comptime {
        var i: usize = 0;
        while (i + 1 < sorted.len) : (i += 1) {
            var j: usize = 0;
            while (j + 1 < sorted.len - i) : (j += 1) {
                if (std.mem.lessThan(u8, sorted[j + 1].name, sorted[j].name)) {
                    const tmp = sorted[j];
                    sorted[j] = sorted[j + 1];
                    sorted[j + 1] = tmp;
                }
            }
        }
    }
    return sorted;
}

fn writeJsonValue(allocator: std.mem.Allocator, w: *Writer, value: anytype) !void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .void => try w.print("null", .{}),
        .bool => |b| try w.print("{?}", .{b}),
        .int => try w.print("{d}", .{value}),
        .comptime_int => try w.print("{d}", .{value}),
        .float => {
            const f = @as(f64, @floatCast(value));
            if (std.math.isNan(f) or std.math.isInf(f)) return error.InvalidFloat;
            try w.print("{d}", .{f});
        },
        .pointer => |ptr| {
            const child = ptr.child;
            if (child == u8 and ptr.size == .slice) {
                try escapeString(w, value);
            } else if (ptr.is_const and ptr.size == .one) {
                try writeJsonValue(allocator, w, value.*);
            } else {
                return error.UnsupportedPointer;
            }
        },
        .optional => {
            if (value) |v| {
                try writeJsonValue(allocator, w, v);
            } else {
                try w.print("null", .{});
            }
        },
        .array => |arr| {
            if (arr.child == u8 and arr.len == 32) {
                try writeHash(w, value);
            } else {
                try w.writeByte('[');
                for (value, 0..) |item, i| {
                    if (i != 0) try w.writeByte(',');
                    try writeJsonValue(allocator, w, item);
                }
                try w.writeByte(']');
            }
        },
        .@"struct" => {
            try w.writeByte('{');
            const fields = comptime sortedFields(T);
            var first = true;
            inline for (fields) |field| {
                const field_name = field.name;
                const is_allocator = field.type == std.mem.Allocator;
                const is_arena = field.type == std.heap.ArenaAllocator;
                const skip_name = std.mem.eql(u8, field_name, "arena") or
                    std.mem.eql(u8, field_name, "ctx") or
                    std.mem.eql(u8, field_name, "unmanaged") or
                    std.mem.eql(u8, field_name, "owns_merkle_path");
                if (!is_allocator and !is_arena and !skip_name) {
                    if (!first) try w.writeByte(',');
                    first = false;
                    try escapeString(w, field_name);
                    try w.writeByte(':');
                    try writeJsonValue(allocator, w, @field(value, field_name));
                }
            }
            try w.writeByte('}');
        },
        .@"union" => {
            if (T == std.json.Value) {
                switch (value) {
                    .null => try w.print("null", .{}),
                    .bool => |b| try w.writeAll(if (b) "true" else "false"),
                    .integer => |i| try w.print("{d}", .{i}),
                    .float => |f| {
                        if (std.math.isNan(f) or std.math.isInf(f)) return error.InvalidFloat;
                        try w.print("{d}", .{f});
                    },
                    .number_string => |ns| try w.writeAll(ns),
                    .string => |s| try escapeString(w, s),
                    .array => |arr| {
                        try w.writeByte('[');
                        for (arr.items, 0..) |item, i| {
                            if (i != 0) try w.writeByte(',');
                            try writeJsonValue(allocator, w, item);
                        }
                        try w.writeByte(']');
                    },
                    .object => |obj| {
                        try w.writeByte('{');
                        var keys = std.ArrayList([]const u8).empty;
                        defer keys.deinit(allocator);
                        var it = obj.iterator();
                        while (it.next()) |entry| {
                            try keys.append(allocator, entry.key_ptr.*);
                        }
                        std.mem.sort([]const u8, keys.items, {}, struct {
                            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                                return std.mem.lessThan(u8, a, b);
                            }
                        }.lessThan);
                        for (keys.items, 0..) |key, i| {
                            if (i != 0) try w.writeByte(',');
                            try escapeString(w, key);
                            try w.writeByte(':');
                            const val = obj.get(key).?;
                            try writeJsonValue(allocator, w, val);
                        }
                        try w.writeByte('}');
                    },
                }
            } else if (std.meta.hasTag(T, @typeInfo(T).@"union".tag_type.?)) {
                const tag = std.mem.span(@tagName(value));
                try escapeString(w, tag);
            } else {
                return error.UnsupportedUnion;
            }
        },
        .@"enum" => {
            const tag = std.mem.span(@tagName(value));
            try escapeString(w, tag);
        },
        else => return error.UnsupportedType,
    }
}

pub fn canonicalJson(value: anytype, allocator: std.mem.Allocator) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeJsonValue(allocator, &out.writer, value);
    return try out.toOwnedSlice();
}
