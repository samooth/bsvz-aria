const std = @import("std");
const types = @import("types.zig");
const verify = @import("verify.zig");

pub const SpvClient = struct {
    allocator: std.mem.Allocator,
    genesis_hash: types.Hash,
    tip_hash: types.Hash,
    tip_height: usize,
};

pub fn initSpv(allocator: std.mem.Allocator, genesis: types.Hash) SpvClient {
    return .{
        .allocator = allocator,
        .genesis_hash = genesis,
        .tip_hash = genesis,
        .tip_height = 0,
    };
}

pub fn verifySpvProof(client: *SpvClient, txid: types.Hash, proof: []const u8) !void {
    if (proof.len == 0) return types.VerifyError.SpvVerificationFailed;
    if (proof.len % 32 != 0) return types.VerifyError.SpvVerificationFailed;
    _ = client;
    _ = txid;
}

pub fn updateTip(client: *SpvClient, new_hash: types.Hash, height: usize) void {
    client.tip_hash = new_hash;
    client.tip_height = height;
}

pub fn verifyAriaAnchor(client: *SpvClient, epoch: *const types.Epoch, anchor_txid: types.Hash) !void {
    try verify.verifyMerkleRoot(epoch, null);
    _ = client;
    _ = anchor_txid;
}
