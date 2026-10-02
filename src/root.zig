const std = @import("std");
const types = @import("types.zig");
const merkle = @import("merkle.zig");
const canonical = @import("canonical.zig");
const record = @import("record.zig");
const epoch_mod = @import("epoch.zig");
const opreturn = @import("opreturn.zig");
const spv = @import("spv.zig");
const verify = @import("verify.zig");
const aria = @import("aria.zig");
const zkml_bridge = @import("zkml_bridge.zig");

pub const api = .{
    .types = types,
    .merkle = merkle,
    .canonical = canonical,
    .epoch = epoch_mod,
    .record = record,
    .aria = aria,
    .opreturn = opreturn,
    .spv = spv,
    .verify = verify,
    .zkml_bridge = zkml_bridge,
};

pub fn version() []const u8 {
    return "0.1.0";
}

test "hash determinism" {
    const data = "aria-bsv";
    const h1 = types.hashBytes(data);
    const h2 = types.hashBytes(data);
    try std.testing.expect(std.mem.eql(u8, &h1, &h2));
}

test "canonical json sorting" {
    const obj = .{
        .zebra = 1,
        .apple = 2,
        .mango = 3,
    };
    const json = try canonical.canonicalJson(obj, std.testing.allocator);
    defer std.testing.allocator.free(json);
    try std.testing.expect(std.mem.order(u8, json, "{\"apple\":2,\"mango\":3,\"zebra\":1}") == .eq);
}

test "canonical json rejects non-finite floats" {
    const obj = .{ .value = std.math.nan(f64) };
    try std.testing.expectError(error.InvalidFloat, canonical.canonicalJson(obj, std.testing.allocator));
}

test "merkle tree empty root" {
    var tree = types.MerkleTree.init(std.testing.allocator);
    defer tree.deinit();
    const root = try merkle.root(&tree);
    const expected = types.hashBytes("");
    try std.testing.expect(std.mem.eql(u8, &root, &expected));
}

test "merkle tree single leaf" {
    var tree = types.MerkleTree.init(std.testing.allocator);
    defer tree.deinit();
    const leaf = types.hashBytes("leaf");
    try merkle.addLeaf(&tree, leaf);
    const root = try merkle.root(&tree);
    try std.testing.expect(std.mem.eql(u8, &root, &merkle.leafHash(leaf)));
}

test "merkle tree two leaves" {
    var tree = types.MerkleTree.init(std.testing.allocator);
    defer tree.deinit();
    const leaf1 = types.hashBytes("leaf1");
    const leaf2 = types.hashBytes("leaf2");
    try merkle.addLeaf(&tree, leaf1);
    try merkle.addLeaf(&tree, leaf2);
    const root = try merkle.root(&tree);
    const expected = merkle.hashInternal(merkle.leafHash(leaf1), merkle.leafHash(leaf2));
    try std.testing.expect(std.mem.eql(u8, &root, &expected));
}

test "merkle proof verification" {
    var tree = types.MerkleTree.init(std.testing.allocator);
    defer tree.deinit();
    const leaf1 = types.hashBytes("leaf1");
    const leaf2 = types.hashBytes("leaf2");
    const leaf3 = types.hashBytes("leaf3");
    try merkle.addLeaf(&tree, leaf1);
    try merkle.addLeaf(&tree, leaf2);
    try merkle.addLeaf(&tree, leaf3);
    const root = try merkle.root(&tree);
    var proof = try merkle.proof(&tree, 0);
    defer proof.deinit(std.testing.allocator);
    try std.testing.expect(merkle.verifyProof(leaf1, proof, root));
    var bad_proof = try merkle.proof(&tree, 1);
    defer bad_proof.deinit(std.testing.allocator);
    try std.testing.expect(!merkle.verifyProof(leaf1, bad_proof, root));
}

test "epoch id parse round-trip" {
    const id = try types.EpochId.parse("ep_1700000000000_0001");
    try std.testing.expectEqual(@as(u64, 1700000000000), id.timestamp_ms);
    try std.testing.expectEqual(@as(u16, 1), id.sequence);
    const formatted = try id.format(std.testing.allocator);
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings("ep_1700000000000_0001", formatted);
}

test "epoch lifecycle" {
    var epoch = try epoch_mod.createEpoch(std.testing.allocator, "ep_1700000000000_0001", "system1");
    defer {
        epoch.deinit();
        std.testing.allocator.destroy(epoch);
    }
    try std.testing.expect(epoch.state == .open);
    const cfg = types.RecordConfig{
        .model_id = "model1",
        .input = "input1",
        .output = "output1",
        .confidence = 0.9,
        .latency_ms = 100,
    };
    try epoch_mod.addRecordToEpoch(epoch, cfg);
    try std.testing.expect(epoch.records.items.len == 1);
    try epoch_mod.closeEpoch(epoch, types.hashBytes("prev"));
    try std.testing.expect(epoch.state == .closed);
}

test "record validation" {
    var epoch = try epoch_mod.createEpoch(std.testing.allocator, "ep_1700000000000_0002", "system1");
    defer {
        epoch.deinit();
        std.testing.allocator.destroy(epoch);
    }
    try std.testing.expectError(types.RecordError.EmptyInput, epoch_mod.addRecordToEpoch(epoch, .{ .model_id = "m", .input = "", .output = "o" }));
    try std.testing.expectError(types.RecordError.EmptyOutput, epoch_mod.addRecordToEpoch(epoch, .{ .model_id = "m", .input = "i", .output = "" }));
    try std.testing.expectError(types.RecordError.InvalidConfidence, epoch_mod.addRecordToEpoch(epoch, .{ .model_id = "m", .input = "i", .output = "o", .confidence = 1.5 }));
}

test "add record to closed epoch fails" {
    var epoch = try epoch_mod.createEpoch(std.testing.allocator, "ep_1700000000000_0003", "system1");
    defer {
        epoch.deinit();
        std.testing.allocator.destroy(epoch);
    }
    try epoch_mod.closeEpoch(epoch, types.hashBytes("prev"));
    try std.testing.expectError(types.EpochError.AlreadyClosed, epoch_mod.addRecordToEpoch(epoch, .{ .model_id = "m", .input = "i", .output = "o" }));
}

test "record serialization round-trip" {
    const rec = types.AuditRecord{
        .aria_version = "1.0",
        .record_id = "rec_001",
        .epoch_id = "ep_001",
        .model_id = "model-1",
        .input_hash = types.hashBytes("input"),
        .output_hash = types.hashBytes("output"),
        .confidence = 0.9,
        .latency_ms = 10,
        .sequence = 1,
        .metadata = null,
    };
    const json = try record.serializeRecord(&rec, std.testing.allocator);
    defer std.testing.allocator.free(json);
    try std.testing.expect(json.len > 0);
    try std.testing.expect(std.mem.eql(u8, json[0..1], "{"));
}

test "opreturn payload round-trip" {
    var close = types.EPOCH_CLOSE{
        .epoch_id = try std.testing.allocator.dupe(u8, "ep_1700000000000_0001"),
        .prev_txid = types.hashBytes("open"),
        .records_merkle_root = types.hashBytes("root"),
        .records_count = 2,
        .duration_ms = 100,
    };
    defer close.deinit(std.testing.allocator);

    const payload = try opreturn.buildOpReturnPayload(std.testing.allocator, &close);
    defer std.testing.allocator.free(payload);
    try std.testing.expect(std.mem.eql(u8, payload[0..4], "ARIA"));

    var parsed = try opreturn.parseOpReturnPayload(std.testing.allocator, payload);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectEqual(close.records_count, parsed.records_count);
    try std.testing.expectEqual(close.duration_ms, parsed.duration_ms);
    try std.testing.expect(std.mem.eql(u8, close.epoch_id, parsed.epoch_id));
    try std.testing.expect(std.mem.eql(u8, &close.prev_txid, &parsed.prev_txid));
    try std.testing.expect(std.mem.eql(u8, &close.records_merkle_root, &parsed.records_merkle_root));
}

test "opreturn parse rejects invalid payload" {
    try std.testing.expectError(types.OpReturnError.InvalidPushData, opreturn.parseOpReturnPayload(std.testing.allocator, "nope"));
}

test "spv client init and tip update" {
    const genesis = types.hashBytes("genesis");
    var client = spv.initSpv(std.testing.allocator, genesis);
    try std.testing.expect(std.mem.eql(u8, &client.genesis_hash, &genesis));
    try std.testing.expect(std.mem.eql(u8, &client.tip_hash, &genesis));

    const new_tip = types.hashBytes("block1");
    spv.updateTip(&client, new_tip, 1);
    try std.testing.expect(std.mem.eql(u8, &client.tip_hash, &new_tip));
    try std.testing.expect(client.tip_height == 1);
}

test "spv proof validation" {
    var client = spv.initSpv(std.testing.allocator, types.hashBytes("genesis"));
    const txid = types.hashBytes("tx");
    try std.testing.expectError(types.VerifyError.SpvVerificationFailed, spv.verifySpvProof(&client, txid, ""));
    try std.testing.expectError(types.VerifyError.SpvVerificationFailed, spv.verifySpvProof(&client, txid, "short"));
    try spv.verifySpvProof(&client, txid, "x" ** 32);
}

test "verify epoch open rejects invalid type" {
    var open = types.EPOCH_OPEN{
        .epoch_id = .{ .timestamp_ms = 1, .sequence = 1 },
        .system_id = "sys",
        .model_hashes = std.StringHashMap(types.Hash).init(std.testing.allocator),
        .state_hash = types.hashBytes(""),
        .timestamp = 1,
        .nonce = types.hashBytes(""),
    };
    defer open.deinit(std.testing.allocator);
    open.type = "WRONG";
    try std.testing.expectError(error.InvalidType, verify.verifyEpochOpen(&open));
}

test "verify epoch open rejects empty model hashes" {
    var open = types.EPOCH_OPEN{
        .epoch_id = .{ .timestamp_ms = 1, .sequence = 1 },
        .system_id = "sys",
        .model_hashes = std.StringHashMap(types.Hash).init(std.testing.allocator),
        .state_hash = types.hashBytes(""),
        .timestamp = 1,
        .nonce = types.hashBytes(""),
    };
    defer open.deinit(std.testing.allocator);
    try std.testing.expectError(types.EpochError.EmptyModelHashes, verify.verifyEpochOpen(&open));
}

test "verify record in epoch" {
    var epoch = try epoch_mod.createEpoch(std.testing.allocator, "ep_1700000000000_0004", "sys");
    defer {
        epoch.deinit();
        std.testing.allocator.destroy(epoch);
    }
    try epoch_mod.addRecordToEpoch(epoch, .{ .model_id = "m", .input = "i", .output = "o" });
    const rec = epoch.records.items[0];
    try verify.verifyRecordInEpoch(&rec, epoch);

    const bad = types.AuditRecord{
        .record_id = "bad",
        .epoch_id = "ep_1700000000000_0004",
        .model_id = "m",
        .input_hash = types.hashBytes(""),
        .output_hash = types.hashBytes(""),
        .confidence = 0.5,
        .latency_ms = 1,
        .sequence = 99,
    };
    try std.testing.expectError(types.VerifyError.SequenceMismatch, verify.verifyRecordInEpoch(&bad, epoch));
}

test "verify merkle root" {
    var fake_epoch = try epoch_mod.createEpoch(std.testing.allocator, "ep_1700000000000_0005", "sys");
    defer {
        fake_epoch.deinit();
        std.testing.allocator.destroy(fake_epoch);
    }
    const leaf = types.hashBytes("x");
    try merkle.addLeaf(&fake_epoch.tree, leaf);
    const root = try merkle.root(&fake_epoch.tree);
    fake_epoch.state = .closed;
    fake_epoch.close_payload.records_merkle_root = root;

    try verify.verifyMerkleRoot(fake_epoch, root);
    try std.testing.expectError(types.VerifyError.MerkleRootMismatch, verify.verifyMerkleRoot(fake_epoch, types.hashBytes("other")));
}

test "compute state hash is deterministic and order-independent" {
    const models = [_]types.ModelHash{
        .{ .model_id = "b", .sha256 = types.hashBytes("b") },
        .{ .model_id = "a", .sha256 = types.hashBytes("a") },
    };
    const reordered = [_]types.ModelHash{
        .{ .model_id = "a", .sha256 = types.hashBytes("a") },
        .{ .model_id = "b", .sha256 = types.hashBytes("b") },
    };
    const h1 = try types.computeStateHash(std.testing.allocator, &models);
    const h2 = try types.computeStateHash(std.testing.allocator, &reordered);
    try std.testing.expect(std.mem.eql(u8, &h1, &h2));
}

test "zkml bridge commit and proof" {
    var bridge = zkml_bridge.initZkMlBridge(std.testing.allocator);
    defer bridge.deinit();
    const model_hash = types.hashBytes("model");
    try bridge.commitModel("model-1", model_hash);
    try std.testing.expectError(error.DuplicateModel, bridge.commitModel("model-1", model_hash));

    const rec = types.AuditRecord{
        .record_id = "rec_1",
        .epoch_id = "ep_1",
        .model_id = "model-1",
        .input_hash = types.hashBytes("in"),
        .output_hash = types.hashBytes("out"),
        .confidence = 0.5,
        .latency_ms = 1,
        .sequence = 0,
    };
    const proof = try bridge.generateProof(&rec);
    defer std.testing.allocator.free(proof);
    try std.testing.expectEqual(@as(usize, 32), proof.len);

    const rec_unknown = types.AuditRecord{
        .record_id = "rec_2",
        .epoch_id = "ep_1",
        .model_id = "unknown",
        .input_hash = types.hashBytes("in"),
        .output_hash = types.hashBytes("out"),
        .confidence = 0.5,
        .latency_ms = 1,
        .sequence = 1,
    };
    try std.testing.expectError(types.EpochError.InvalidModelId, bridge.generateProof(&rec_unknown));
}
