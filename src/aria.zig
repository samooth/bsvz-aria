const std = @import("std");
const types = @import("types.zig");
const epoch_mod = @import("epoch.zig");
const spv = @import("spv.zig");
const verify = @import("verify.zig");
const merkle = @import("merkle.zig");
const canonical = @import("canonical.zig");
const record = @import("record.zig");
const zkml_bridge = @import("zkml_bridge.zig");

pub const Aria = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    config: types.Config,
    store: epoch_mod.EpochStore,
    spv: spv.SpvClient,
    zkml: zkml_bridge.ZkMlBridge,
    last_txid: types.Hash,

    pub fn init(allocator: std.mem.Allocator, cfg: types.Config, genesis: types.Hash, io: std.Io) !Aria {
        try cfg.validate();
        return .{
            .allocator = allocator,
            .io = io,
            .config = cfg,
            .store = epoch_mod.EpochStore.init(allocator),
            .spv = spv.initSpv(allocator, genesis),
            .zkml = zkml_bridge.initZkMlBridge(allocator),
            .last_txid = genesis,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.zkml.deinit();
        self.store.deinit();
    }

    pub fn openEpoch(self: *@This(), id: []const u8, system_id: []const u8, model_hashes: []const types.ModelHash) !*types.Epoch {
        const epoch = try epoch_mod.createEpoch(self.allocator, id, system_id);
        errdefer {
            epoch.deinit();
            self.allocator.destroy(epoch);
        }

        for (model_hashes) |mh| {
            if (epoch.open_payload.model_hashes.contains(mh.model_id)) {
                return types.EpochError.InvalidModelId;
            }
            const key = try self.allocator.dupe(u8, mh.model_id);
            epoch.open_payload.model_hashes.put(key, mh.sha256) catch |err| {
                self.allocator.free(key);
                return err;
            };
        }

        epoch.open_payload.state_hash = try types.computeStateHash(self.allocator, model_hashes);
        const now = std.Io.Timestamp.now(self.io, .real);
        epoch.open_payload.timestamp = @intCast(now.toMilliseconds());
        std.Io.random(self.io, &epoch.open_payload.nonce);

        try verify.verifyEpochOpen(&epoch.open_payload);

        const id_key = try self.allocator.dupe(u8, id);
        self.store.epochs.put(id_key, epoch) catch |err| {
            self.allocator.free(id_key);
            return err;
        };
        return epoch;
    }

    pub fn closeEpoch(self: *@This(), epoch: *types.Epoch) !types.CloseResult {
        const start_ms = std.Io.Timestamp.now(self.io, .real).toMilliseconds();
        try epoch_mod.closeEpoch(epoch, self.last_txid);

        const json = try canonical.canonicalJson(epoch.close_payload, self.allocator);
        defer self.allocator.free(json);
        const txid = types.hashBytes(json);
        self.last_txid = txid;

        const end_ms = std.Io.Timestamp.now(self.io, .real).toMilliseconds();
        return types.CloseResult{
            .txid = txid,
            .records_count = epoch.close_payload.records_count,
            .records_merkle_root = epoch.close_payload.records_merkle_root,
            .duration_ms = @intCast(@max(end_ms - start_ms, 0)),
        };
    }

    pub fn addRecord(self: *@This(), epoch: *types.Epoch, cfg: types.RecordConfig) !*types.AuditRecord {
        try epoch_mod.addRecordToEpoch(epoch, cfg);
        const rec_ptr = &epoch.records.items[epoch.records.items.len - 1];
        self.store.records.put(rec_ptr.record_id, rec_ptr) catch |err| {
            rec_ptr.deinit(epoch.allocator);
            _ = epoch.records.pop();
            _ = epoch.tree.leaves.pop();
            epoch.next_sequence -= 1;
            return err;
        };
        return rec_ptr;
    }

    pub fn verifyEpoch(self: *@This(), epoch: *const types.Epoch) !void {
        _ = self;
        if (epoch.state != .closed) return types.EpochError.NotOpened;
        try verify.verifyMerkleRoot(epoch, epoch.close_payload.records_merkle_root);
        try verify.verifyEpochClose(&epoch.close_payload, epoch);
    }

    pub fn buildRecordProof(self: *@This(), epoch: *types.Epoch, record_id: []const u8) !types.MerkleProof {
        _ = self;
        return try epoch_mod.buildEpochProof(epoch, record_id);
    }
};
