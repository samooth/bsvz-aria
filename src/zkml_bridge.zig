const std = @import("std");
const types = @import("types.zig");

pub const ZkMlBridge = struct {
    allocator: std.mem.Allocator,
    proof_buffer: std.ArrayList(u8),
    model_commitments: std.StringHashMap(types.Hash),
};

pub fn initZkMlBridge(allocator: std.mem.Allocator) ZkMlBridge {
    return .{
        .allocator = allocator,
        .proof_buffer = std.ArrayList(u8).empty,
        .model_commitments = std.StringHashMap(types.Hash).empty,
    };
}

pub fn deinit(self: *@This()) void {
    self.proof_buffer.deinit(self.allocator);
    self.model_commitments.deinit();
    self.* = .{
        .allocator = undefined,
        .proof_buffer = std.ArrayList(u8).empty,
        .model_commitments = std.StringHashMap(types.Hash).empty,
    };
}

pub fn commitModel(self: *@This(), model_id: []const u8, model_hash: types.Hash) !void {
    const owned_id = try self.allocator.dupe(u8, model_id);
    try self.model_commitments.put(self.allocator, owned_id, model_hash);
}

pub fn generateProof(self: *@This(), record: *const types.AuditRecord) ![]u8 {
    _ = record;
    return self.proof_buffer.items;
}
