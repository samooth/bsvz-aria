const std = @import("std");
const types = @import("types.zig");
const canonical = @import("canonical.zig");

pub const ARIA_MAGIC = [4]u8{ 0x41, 0x52, 0x49, 0x41 };

const CloseJson = struct {
    aria_version: []const u8,
    type: []const u8,
    epoch_id: []const u8,
    prev_txid: []const u8,
    records_merkle_root: []const u8,
    records_count: u32,
    duration_ms: u64,
};

fn writeVarint(w: *std.Io.Writer, len: usize) !void {
    if (len < 0xfd) {
        try w.writeByte(@intCast(len));
    } else if (len <= 0xffff) {
        try w.writeByte(0xfd);
        try w.writeByte(@intCast(len & 0xff));
        try w.writeByte(@intCast((len >> 8) & 0xff));
    } else if (len <= 0xffffffff) {
        try w.writeByte(0xfe);
        try w.writeByte(@intCast(len & 0xff));
        try w.writeByte(@intCast((len >> 8) & 0xff));
        try w.writeByte(@intCast((len >> 16) & 0xff));
        try w.writeByte(@intCast((len >> 24) & 0xff));
    } else {
        return types.OpReturnError.InvalidPushData;
    }
}

fn readVarint(data: []const u8) !struct { len: usize, consumed: usize } {
    if (data.len == 0) return types.OpReturnError.InvalidPushData;
    switch (data[0]) {
        0xfd => {
            if (data.len < 3) return types.OpReturnError.InvalidPushData;
            const len = @as(usize, data[1]) | (@as(usize, data[2]) << 8);
            return .{ .len = len, .consumed = 3 };
        },
        0xfe => {
            if (data.len < 5) return types.OpReturnError.InvalidPushData;
            const len = @as(usize, data[1]) |
                (@as(usize, data[2]) << 8) |
                (@as(usize, data[3]) << 16) |
                (@as(usize, data[4]) << 24);
            return .{ .len = len, .consumed = 5 };
        },
        0xff => {
            if (data.len < 9) return types.OpReturnError.InvalidPushData;
            var len: usize = 0;
            for (data[1..9], 0..) |b, i| {
                len |= @as(usize, b) << @intCast(i * 8);
            }
            return .{ .len = len, .consumed = 9 };
        },
        else => {
            const n = data[0];
            return .{ .len = n, .consumed = 1 };
        },
    }
}

pub fn buildOpReturnPayload(allocator: std.mem.Allocator, close: *const types.EPOCH_CLOSE) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    const w = &out.writer;
    try w.writeAll(&ARIA_MAGIC);
    const json = try canonical.canonicalJson(close, allocator);
    defer allocator.free(json);
    try writeVarint(w, json.len);
    try w.writeAll(json);
    return try out.toOwnedSlice();
}

pub fn parseOpReturnPayload(allocator: std.mem.Allocator, payload: []const u8) !types.EPOCH_CLOSE {
    if (payload.len < ARIA_MAGIC.len) return types.OpReturnError.InvalidPushData;
    if (!std.mem.eql(u8, payload[0..ARIA_MAGIC.len], &ARIA_MAGIC)) return types.OpReturnError.InvalidPushData;

    const header = readVarint(payload[ARIA_MAGIC.len..]) catch return types.OpReturnError.InvalidPushData;
    const json_start = ARIA_MAGIC.len + header.consumed;
    const json_end = json_start + header.len;
    if (json_end > payload.len) return types.OpReturnError.InvalidPushData;

    var parsed = std.json.parseFromSlice(CloseJson, allocator, payload[json_start..json_end], .{}) catch {
        return types.OpReturnError.JsonParseFailed;
    };
    defer parsed.deinit();
    const v = parsed.value;

    if (!std.mem.eql(u8, v.type, "EPOCH_CLOSE")) return types.OpReturnError.InvalidEncoding;
    if (!std.mem.eql(u8, v.aria_version, "1.0")) return types.OpReturnError.InvalidEncoding;

    const epoch_id = try allocator.dupe(u8, v.epoch_id);
    errdefer allocator.free(epoch_id);

    return types.EPOCH_CLOSE{
        .epoch_id = epoch_id,
        .prev_txid = try types.parseHashPrefixed(v.prev_txid),
        .records_merkle_root = try types.parseHashPrefixed(v.records_merkle_root),
        .records_count = v.records_count,
        .duration_ms = v.duration_ms,
    };
}
