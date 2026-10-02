const std = @import("std");
const types = @import("types.zig");
const merkle = @import("merkle.zig");
const record = @import("record.zig");

pub const EpochStore = struct {
    allocator: std.mem.Allocator,
    epochs: std.StringHashMap(*types.Epoch),
    records: std.StringHashMap(*types.AuditRecord),

    pub fn init(allocator: std.mem.Allocator) EpochStore {
        return .{
            .allocator = allocator,
            .epochs = std.StringHashMap(*types.Epoch).init(allocator),
            .records = std.StringHashMap(*types.AuditRecord).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        var it = self.epochs.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.epochs.deinit();
        self.records.deinit();
        self.* = .{
            .allocator = undefined,
            .epochs = std.StringHashMap(*types.Epoch).init(self.allocator),
            .records = std.StringHashMap(*types.AuditRecord).init(self.allocator),
        };
    }

    pub fn getEpoch(self: *@This(), id: []const u8) ?*types.Epoch {
        return self.epochs.get(id);
    }

    pub fn getRecord(self: *@This(), id: []const u8) ?*types.AuditRecord {
        return self.records.get(id);
    }
};

pub fn createEpoch(allocator: std.mem.Allocator, id: []const u8, system_id: []const u8) !*types.Epoch {
    const epoch_id = try types.EpochId.parse(id);
    const model_hashes = std.StringHashMap(types.Hash).init(allocator);
    const tree = types.MerkleTree.init(allocator);
    const records = std.ArrayList(types.AuditRecord).empty;
    const open = types.EPOCH_OPEN{
        .epoch_id = epoch_id,
        .system_id = system_id,
        .model_hashes = model_hashes,
        .state_hash = types.hashBytes(""),
        .timestamp = epoch_id.timestamp_ms,
        .nonce = types.hashBytes(""),
    };
    const epoch = try allocator.create(types.Epoch);
    epoch.* = types.Epoch{
        .allocator = allocator,
        .state = .open,
        .open_payload = open,
        .tree = tree,
        .close_payload = types.EPOCH_CLOSE{
            .aria_version = "1.0",
            .type = "EPOCH_CLOSE",
            .epoch_id = "",
            .prev_txid = types.hashBytes(""),
            .records_merkle_root = types.hashBytes(""),
            .records_count = 0,
            .duration_ms = 0,
        },
        .records = records,
        .merkle_path = std.ArrayList(types.MerkleProofNode).empty,
        .next_sequence = 0,
        .flags = 0,
    };
    return epoch;
}

pub fn addRecordToEpoch(epoch: *types.Epoch, cfg: types.RecordConfig) !void {
    if (epoch.state != .open) return types.EpochError.AlreadyClosed;
    const rec = try record.createRecord(epoch.allocator, epoch, cfg);
    const hash = try record.hashRecord(&rec, epoch.allocator);
    try merkle.addLeaf(&epoch.tree, hash);
    try epoch.records.append(epoch.allocator, rec);
    epoch.next_sequence += 1;
}

pub fn closeEpoch(epoch: *types.Epoch, prev_txid: types.Hash) !void {
    if (epoch.state != .open) return types.EpochError.AlreadyClosed;
    const root_hash = try merkle.root(&epoch.tree);
    const epoch_id_str = try epoch.open_payload.epoch_id.format(epoch.allocator);
    epoch.close_payload = types.EPOCH_CLOSE{
        .epoch_id = epoch_id_str,
        .prev_txid = prev_txid,
        .records_merkle_root = root_hash,
        .records_count = @intCast(epoch.records.items.len),
        .duration_ms = 0,
    };
    epoch.state = .closed;
}

pub fn validateClose(epoch: *types.Epoch, expected_root: ?types.Hash) !void {
    if (epoch.state != .closed) return types.EpochError.EpochNotClosed;
    if (!std.mem.eql(u8, &epoch.close_payload.records_merkle_root, &expected_root orelse epoch.close_payload.records_merkle_root)) {
        return types.EpochError.RootMismatch;
    }
    if (epoch.close_payload.records_count != epoch.records.items.len) {
        return types.EpochError.CountMismatch;
    }
}

pub fn buildEpochProof(epoch: *types.Epoch, record_id: []const u8) !types.MerkleProof {
    if (epoch.state != .closed) return types.EpochError.EpochNotClosed;
    const index = for (epoch.records.items, 0..) |rec, i| {
        if (std.mem.eql(u8, rec.record_id, record_id)) break i;
    } else return types.EpochError.RecordNotFound;
    return try merkle.proof(&epoch.tree, index);
}
