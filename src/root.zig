const std = @import("std");
const types = @import("types.zig");
const merkle = @import("merkle.zig");
const canonical = @import("canonical.zig");
const record = @import("record.zig");
const epoch_mod = @import("epoch.zig");
const opreturn = @import("opreturn.zig");
const spv = @import("spv.zig");
const verify = @import("verify.zig");

pub const api = .{
    .types = types,
    .merkle = merkle,
    .canonical = canonical,
    .epoch = epoch_mod,
    .record = record,
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
        .apple = 2,
        .mango = 3,
        .zebra = 1,
    };
    const json = try canonical.canonicalJson(obj, std.testing.allocator);
    defer std.testing.allocator.free(json);
    try std.testing.expect(std.mem.order(u8, json, "{\"apple\":2,\"mango\":3,\"zebra\":1}") == .eq);
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
    try std.testing.expect(std.mem.eql(u8, &root, &leaf));
}

test "merkle tree two leaves" {
    var tree = types.MerkleTree.init(std.testing.allocator);
    defer tree.deinit();
    const leaf1 = types.hashBytes("leaf1");
    const leaf2 = types.hashBytes("leaf2");
    try merkle.addLeaf(&tree, leaf1);
    try merkle.addLeaf(&tree, leaf2);
    const root = try merkle.root(&tree);
    const expected = merkle.hashInternal(leaf1, leaf2);
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

test "epoch lifecycle" {
    var epoch = try epoch_mod.createEpoch(std.testing.allocator, "ep_test", "system1");
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
    const rec = try epoch_mod.addRecordToEpoch(epoch, cfg);
    _ = rec;
    try std.testing.expect(epoch.records.items.len == 1);
    try epoch_mod.closeEpoch(epoch);
    try std.testing.expect(epoch.state == .closed);
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
    var tree = types.MerkleTree.init(std.testing.allocator);
    defer tree.deinit();
    try merkle.addLeaf(&tree, types.hashBytes("a"));
    try merkle.addLeaf(&tree, types.hashBytes("b"));
    const root = try merkle.root(&tree);

    const payload = try opreturn.buildOpReturnPayload(std.testing.allocator, root, "ep_001", 2);
    defer std.testing.allocator.free(payload);
    try std.testing.expect(std.mem.startsWith(u8, payload, "ARIA:"));

    const parsed = try opreturn.parseOpReturnPayload(payload);
    try std.testing.expect(parsed.count == 2);
    try std.testing.expect(std.mem.eql(u8, &parsed.root, &root));
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

test "verify merkle root" {
    var fake_epoch = try epoch_mod.createEpoch(std.testing.allocator, "ep_v", "sys");
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
}
