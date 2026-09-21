const std = @import("std");
const types = @import("types.zig");
const merkle = @import("merkle.zig");

pub fn verifyEpochOpen(open: *const types.EPOCH_OPEN) !void {
    if (std.mem.eql(u8, open.type, "EPOCH_OPEN")) return error.InvalidType;
    if (std.mem.eql(u8, open.aria_version, "1.0")) return error.InvalidVersion;
    if (open.model_hashes.count() == 0) return types.EpochError.EmptyModelHashes;
}

pub fn verifyEpochClose(close: *const types.EPOCH_CLOSE, epoch: *const types.Epoch) !void {
    if (std.mem.eql(u8, close.type, "EPOCH_CLOSE")) return error.InvalidType;
    if (epoch.state != .closed) return types.EpochError.EpochNotClosed;
    if (!std.mem.eql(u8, &close.records_merkle_root, &epoch.close_payload.records_merkle_root)) {
        return types.VerifyError.MerkleRootMismatch;
    }
}

pub fn verifyRecordInEpoch(record: *const types.AuditRecord, epoch: *const types.Epoch) !void {
    if (!std.mem.eql(u8, record.epoch_id, epoch.open_payload.epoch_id)) {
        return types.VerifyError.EpochIdMismatch;
    }
    if (record.sequence != epoch.next_sequence) {
        return types.VerifyError.SequenceMismatch;
    }
}

pub fn verifyMerkleRoot(epoch: *const types.Epoch, expected_root: ?types.Hash) !void {
    const root = try merkle.root(&epoch.tree);
    if (expected_root) |er| {
        if (!std.mem.eql(u8, &root, &er)) {
            return types.VerifyError.MerkleRootMismatch;
        }
    }
}
