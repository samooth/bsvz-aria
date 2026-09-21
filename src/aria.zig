const std = @import("std");
const types = @import("types.zig");
const epoch_mod = @import("epoch.zig");
const spv = @import("spv.zig");
const verify = @import("verify.zig");

pub const Aria = struct {
    allocator: std.mem.Allocator,
    config: types.Config,
    store: epoch_mod.EpochStore,
    spv: spv.SpvClient,
    zkml: ?*std.Build.Module = null,
};

pub fn init(allocator: std.mem.Allocator, cfg: types.Config, genesis: types.Hash) !Aria {
    try cfg.validate();
    return .{
        .allocator = allocator,
        .config = cfg,
        .store = epoch_mod.EpochStore.init(allocator),
        .spv = spv.initSpv(allocator, genesis),
        .zkml = null,
    };
}

pub fn deinit(self: *@This()) void {
    self.store.deinit();
}

pub fn openEpoch(self: *Aria, id: []const u8, _system_id: []const u8, _model_hashes: []const types.ModelHash) !*types.Epoch {
    const timestamp = std.time.milliTimestamp();
    const epoch = try epoch_mod.createEpoch(self.allocator, id, self.spv.tip_height, @intCast(timestamp));
    errdefer self.allocator.free(epoch);
    _ = _system_id;
    _ = _model_hashes;

    try verify.verifyEpochOpen(&epoch.open_payload);
    try self.store.epochs.put(self.allocator, try self.allocator.dupe(u8, id), epoch);
    return epoch;
}

pub fn closeEpoch(self: *Aria, epoch: *types.Epoch) !types.CloseResult {
    try epoch_mod.closeEpoch(epoch);
    const merkle_mod = @import("merkle.zig");
    const root = try merkle_mod.root(&epoch.tree);
    _ = self;
    return types.CloseResult{
        .txid = root,
        .records_count = epoch.close_payload.final_record_count,
        .records_merkle_root = root,
        .duration_ms = 0,
    };
}

pub fn addRecord(self: *Aria, epoch: *types.Epoch, cfg: types.RecordConfig) !types.AuditRecord {
    _ = self;
    return try epoch_mod.addRecordToEpoch(epoch, cfg);
}

pub fn verifyEpoch(self: *Aria, epoch: *types.Epoch) !void {
    _ = self;
    try verify.verifyMerkleRoot(epoch, null);
    try verify.verifyEpochClose(&epoch.close_payload, epoch);
}
