const std = @import("std");
const types = @import("types.zig");
const merkle = @import("merkle.zig");
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

pub fn verifySpvProof(client: *SpvClient, _txid: types.Hash, proof: []const u8) !void {
    if (proof.len == 0) return types.VerifyError.SpvVerificationFailed;
    _ = client;
    _ = _txid;
}

pub fn updateTip(client: *SpvClient, _new_hash: types.Hash, _height: usize) void {
    client.tip_hash = _new_hash;
    client.tip_height = _height;
}

pub fn verifyAriaAnchor(client: *SpvClient, epoch: *const types.Epoch, _anchor_txid: types.Hash) !void {
    try verify.verifyMerkleRoot(epoch, null);
    _ = client;
    _ = _anchor_txid;
}
