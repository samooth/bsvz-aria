const std = @import("std");
const types = @import("types.zig");

const Writer = std.Io.Writer;

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
    try w.writeAll(&hex);
}

fn insertionSort(comptime T: type, items: []T, comptime lessThan: fn (lhs: T, rhs: T) bool) void {
    var i: usize = 1;
    while (i < items.len) : (i += 1) {
        const key = items[i];
        var j = i;
        while (j > 0 and lessThan(key, items[j - 1])) {
            items[j] = items[j - 1];
            j -= 1;
        }
        items[j] = key;
    }
}

fn sortedFieldNames(comptime T: type) [std.meta.fields(T).len][]const u8 {
    const fields = std.meta.fields(T);
    var names: [fields.len][]const u8 = undefined;
    inline for (fields, 0..) |field, i| {
        names[i] = field.name;
    }
    comptime {
        var i: usize = 0;
        while (i < names.len - 1) : (i += 1) {
            var j: usize = 0;
            while (j < names.len - i - 1) : (j += 1) {
                if (std.mem.lessThan(u8, names[j + 1], names[j])) {
                    const tmp = names[j];
                    names[j] = names[j + 1];
                    names[j + 1] = tmp;
                }
            }
        }
    }
    return names;
}

fn writeJsonValue(w: *Writer, value: anytype) Writer.Error!void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .void => try w.print("null", .{}),
        .bool => |b| try w.print("{?}", .{b}),
        .int => |info| {
            if (info.signedness == .signed) {
                try w.print("{d}", .{value});
            } else {
                try w.print("{d}", .{value});
            }
        },
        .comptime_int => {
            try w.print("{d}", .{value});
        },
        .float => {
            try w.print("{}", .{@as(f64, @floatCast(value))});
        },
        .pointer => |ptr| {
            const child = ptr.child;
            if (child == u8 and ptr.size == .slice) {
                try escapeString(w, value);
            } else if (ptr.is_const and ptr.size == .One) {
                try writeJsonValue(w, value.*);
            } else {
                @compileError("Unsupported pointer type for canonical JSON");
            }
        },
        .optional => {
            if (value) |v| {
                try writeJsonValue(w, v);
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
                    try writeJsonValue(w, item);
                }
                try w.writeByte(']');
            }
        },
        .@"struct" => {
            try w.writeByte('{');
            var first = true;
            inline for (std.meta.fields(T)) |field| {
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
                    try writeJsonValue(w, @field(value, field_name));
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
                    .float => |f| try w.print("{d}", .{f}),
                    .number_string => |ns| try escapeString(w, ns),
                    .string => |s| try escapeString(w, s),
                    .array => |arr| {
                        try w.writeByte('[');
                        for (arr.items, 0..) |item, i| {
                            if (i != 0) try w.writeByte(',');
                            try writeJsonValue(w, item);
                        }
                        try w.writeByte(']');
                    },
                    .object => |obj| {
                        try w.writeByte('{');
                        var keys_buf: [64][]const u8 = undefined;
                        var keys_count: usize = 0;
                        var it = obj.iterator();
                        while (it.next()) |entry| {
                            keys_buf[keys_count] = entry.key_ptr.*;
                            keys_count += 1;
                        }
                        insertionSort([]const u8, keys_buf[0..keys_count], struct {
                            fn lessThan(a: []const u8, b: []const u8) bool {
                                return std.mem.lessThan(u8, a, b);
                            }
                        }.lessThan);
                        for (keys_buf[0..keys_count], 0..) |key, i| {
                            if (i != 0) try w.writeByte(',');
                            try escapeString(w, key);
                            try w.writeByte(':');
                            const val = obj.get(key).?;
                            try writeJsonValue(w, val);
                        }
                        try w.writeByte('}');
                    },
                }
            } else if (std.meta.hasTag(T, @typeInfo(T).@"union".tag_type.?)) {
                const tag = std.mem.span(@tagName(value));
                try escapeString(w, tag);
            } else {
                @compileError("Unsupported union type for canonical JSON");
            }
        },
        .@"enum" => {
            const tag = std.mem.span(@tagName(value));
            try escapeString(w, tag);
        },
        else => @compileError("Unsupported type for canonical JSON: " ++ @typeName(T)),
    }
}

pub fn canonicalJson(value: anytype, allocator: std.mem.Allocator) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeJsonValue(&out.writer, value);
    return try out.toOwnedSlice();
}
