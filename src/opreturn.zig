const std = @import("std");
const types = @import("types.zig");

pub fn buildOpReturnPayload(allocator: std.mem.Allocator, root: types.Hash, epoch_id: []const u8, count: usize) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    const w = &out.writer;
    try w.writeAll("ARIA:");
    try w.print("{s}", .{epoch_id});
    try w.writeByte('|');
    for (root) |b| {
        try w.print("{x:0>2}", .{b});
    }
    try w.writeByte('|');
    try w.print("{d}", .{count});
    try w.writeByte('|');
    try w.writeByte('1');
    return try out.toOwnedSlice();
}

pub fn parseOpReturnPayload(payload: []const u8) !struct { epoch_id: []const u8, root: types.Hash, count: usize } {
    if (!std.mem.startsWith(u8, payload, "ARIA:")) return types.OpReturnError.InvalidPushData;
    const without_prefix = payload["ARIA:".len..];
    var parts = std.mem.splitScalar(u8, without_prefix, '|');
    const epoch_id = parts.next() orelse return types.OpReturnError.InvalidPushData;
    const hash_hex = parts.next() orelse return types.OpReturnError.InvalidPushData;
    const count_str = parts.next() orelse return types.OpReturnError.InvalidPushData;

    var hash: [32]u8 = undefined;
    if (hash_hex.len != 64) return types.OpReturnError.InvalidEncoding;
    _ = try std.fmt.hexToBytes(&hash, hash_hex);

    const count = try std.fmt.parseInt(usize, count_str, 10);
    return .{ .epoch_id = epoch_id, .root = hash, .count = count };
}
