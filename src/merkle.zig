const std = @import("std");
const types = @import("types.zig");

pub fn addLeaf(tree: *types.MerkleTree, leaf: types.Hash) !void {
    try tree.leaves.append(tree.allocator, leaf);
    tree.cached_root = null;
}

pub fn addLeaves(tree: *types.MerkleTree, new_leaves: []const types.Hash) !void {
    try tree.leaves.appendSlice(tree.allocator, new_leaves);
    tree.cached_root = null;
}

pub fn root(tree: *const types.MerkleTree) !types.Hash {
    if (tree.cached_root) |r| return r;
    if (tree.leaves.items.len == 0) {
        return types.hashBytes("");
    }
    var current = std.ArrayList(types.Hash).empty;
    try current.appendSlice(tree.allocator, tree.leaves.items);
    var next = std.ArrayList(types.Hash).empty;
    defer next.deinit(tree.allocator);
    while (current.items.len > 1) {
        next.clearRetainingCapacity();
        var i: usize = 0;
        while (i < current.items.len) : (i += 2) {
            if (i + 1 < current.items.len) {
                const combined = hashInternal(current.items[i], current.items[i + 1]);
                try next.append(tree.allocator, combined);
            } else {
                const combined = hashInternal(current.items[i], current.items[i]);
                try next.append(tree.allocator, combined);
            }
        }
        const tmp = current;
        current = next;
        next = tmp;
    }
    defer current.deinit(tree.allocator);
    return current.items[0];
}

pub fn proof(tree: *const types.MerkleTree, leaf_index: usize) !types.MerkleProof {
    if (leaf_index >= tree.leaves.items.len) return error.LeafNotFound;
    if (tree.leaves.items.len == 0) return error.EmptyTree;

    var proof_nodes = std.ArrayList(types.MerkleProofNode).empty;
    errdefer proof_nodes.deinit(tree.allocator);

    var current_index = leaf_index;
    var current_level = tree.leaves.items;
    var next_level = std.ArrayList(types.Hash).empty;
    defer next_level.deinit(tree.allocator);

    while (current_level.len > 1) {
        const sibling_index = current_index ^ 1;
        if (sibling_index < current_level.len) {
            if (current_index % 2 == 0) {
                try proof_nodes.append(tree.allocator, .{ .hash = current_level[sibling_index], .position = .right });
            } else {
                try proof_nodes.append(tree.allocator, .{ .hash = current_level[sibling_index], .position = .left });
            }
        }

        next_level.clearRetainingCapacity();
        var i: usize = 0;
        while (i < current_level.len) : (i += 2) {
            if (i + 1 < current_level.len) {
                const combined = hashInternal(current_level[i], current_level[i + 1]);
                try next_level.append(tree.allocator, combined);
            } else {
                const combined = hashInternal(current_level[i], current_level[i]);
                try next_level.append(tree.allocator, combined);
            }
        }
        current_level = next_level.items;
        current_index /= 2;
    }

    return types.MerkleProof{ .leaf_index = leaf_index, .nodes = proof_nodes };
}

pub fn verifyProof(leaf: types.Hash, merkle_proof: types.MerkleProof, expected_root: types.Hash) bool {
    var current = leaf;
    for (merkle_proof.nodes.items) |node| {
        switch (node.position) {
            .left => current = hashInternal(node.hash, current),
            .right => current = hashInternal(current, node.hash),
        }
    }
    return std.mem.eql(u8, &current, &expected_root);
}

pub fn hashInternal(left: types.Hash, right: types.Hash) types.Hash {
    var buf: [64]u8 = undefined;
    @memcpy(buf[0..32], &left);
    @memcpy(buf[32..64], &right);
    return types.hashBytes(&buf);
}
