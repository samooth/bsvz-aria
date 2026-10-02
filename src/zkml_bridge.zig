const std = @import("std");
const types = @import("types.zig");
const canonical = @import("canonical.zig");

pub const ZkMlBridge = struct {
    allocator: std.mem.Allocator,
    proof_buffer: std.ArrayList(u8),
    model_commitments: std.StringHashMap(types.Hash),

    pub fn init(allocator: std.mem.Allocator) ZkMlBridge {
        return .{
            .allocator = allocator,
            .proof_buffer = std.ArrayList(u8).empty,
            .model_commitments = std.StringHashMap(types.Hash).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        var it = self.model_commitments.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.model_commitments.deinit();
        self.proof_buffer.deinit(self.allocator);
        self.* = .{
            .allocator = undefined,
            .proof_buffer = std.ArrayList(u8).empty,
            .model_commitments = std.StringHashMap(types.Hash).init(self.allocator),
        };
    }

    pub fn commitModel(self: *@This(), model_id: []const u8, model_hash: types.Hash) !void {
        if (self.model_commitments.contains(model_id)) return error.DuplicateModel;
        const owned_id = try self.allocator.dupe(u8, model_id);
        errdefer self.allocator.free(owned_id);
        try self.model_commitments.put(owned_id, model_hash);
    }

    pub fn generateProof(self: *@This(), record: *const types.AuditRecord) ![]u8 {
        const commitment = self.model_commitments.get(record.model_id) orelse {
            return types.EpochError.InvalidModelId;
        };
        const json = try canonical.canonicalJson(record, self.allocator);
        defer self.allocator.free(json);

        var combined: [64]u8 = undefined;
        const json_hash = types.hashBytes(json);
        @memcpy(combined[0..32], &json_hash);
        @memcpy(combined[32..64], &commitment);

        const digest = types.hashBytes(&combined);
        const proof = try self.allocator.alloc(u8, 32);
        @memcpy(proof, &digest);
        return proof;
    }
};

pub fn initZkMlBridge(allocator: std.mem.Allocator) ZkMlBridge {
    return ZkMlBridge.init(allocator);
}
