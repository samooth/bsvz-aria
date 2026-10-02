const std = @import("std");
const types = @import("types.zig");

pub fn addLeaf(tree: *types.MerkleTree, leaf: types.Hash) !void {
    try tree.leaves.append(tree.allocator, leaf);
}

pub fn addLeaves(tree: *types.MerkleTree, new_leaves: []const types.Hash) !void {
    try tree.leaves.appendSlice(tree.allocator, new_leaves);
}

pub fn leafHash(leaf: types.Hash) types.Hash {
    var buf: [33]u8 = undefined;
    buf[0] = 0x00;
    @memcpy(buf[1..33], &leaf);
    return types.hashBytes(&buf);
}

pub fn hashInternal(left: types.Hash, right: types.Hash) types.Hash {
    var buf: [65]u8 = undefined;
    buf[0] = 0x01;
    @memcpy(buf[1..33], &left);
    @memcpy(buf[33..65], &right);
    return types.hashBytes(&buf);
}

pub fn root(tree: *const types.MerkleTree) !types.Hash {
    const n = tree.leaves.items.len;
    if (n == 0) {
        return types.hashBytes("");
    }
    var current = std.ArrayList(types.Hash).empty;
    defer current.deinit(tree.allocator);
    for (tree.leaves.items) |leaf| {
        try current.append(tree.allocator, leafHash(leaf));
    }
    var next = std.ArrayList(types.Hash).empty;
    defer next.deinit(tree.allocator);
    while (current.items.len > 1) {
        next.clearRetainingCapacity();
        var i: usize = 0;
        while (i < current.items.len) : (i += 2) {
            if (i + 1 < current.items.len) {
                try next.append(tree.allocator, hashInternal(current.items[i], current.items[i + 1]));
            } else {
                try next.append(tree.allocator, current.items[i]);
            }
        }
        const tmp = current;
        current = next;
        next = tmp;
    }
    return current.items[0];
}

pub fn proof(tree: *const types.MerkleTree, leaf_index: usize) !types.MerkleProof {
    if (tree.leaves.items.len == 0) return types.MerkleError.EmptyTree;
    if (leaf_index >= tree.leaves.items.len) return types.MerkleError.LeafNotFound;

    var proof_nodes = std.ArrayList(types.MerkleProofNode).empty;
    errdefer proof_nodes.deinit(tree.allocator);

    var current = std.ArrayList(types.Hash).empty;
    defer current.deinit(tree.allocator);
    for (tree.leaves.items) |leaf| {
        try current.append(tree.allocator, leafHash(leaf));
    }
    var next = std.ArrayList(types.Hash).empty;
    defer next.deinit(tree.allocator);

    var current_index = leaf_index;
    while (current.items.len > 1) {
        const sibling_index = current_index ^ 1;
        if (sibling_index < current.items.len) {
            const position: types.MerkleProofNodePosition = if (current_index % 2 == 0) .right else .left;
            try proof_nodes.append(tree.allocator, .{ .hash = current.items[sibling_index], .position = position });
        }

        next.clearRetainingCapacity();
        var i: usize = 0;
        while (i < current.items.len) : (i += 2) {
            if (i + 1 < current.items.len) {
                try next.append(tree.allocator, hashInternal(current.items[i], current.items[i + 1]));
            } else {
                try next.append(tree.allocator, current.items[i]);
            }
        }
        const tmp = current;
        current = next;
        next = tmp;
        current_index /= 2;
    }

    return types.MerkleProof{ .leaf_index = leaf_index, .nodes = proof_nodes };
}

pub fn verifyProof(leaf: types.Hash, merkle_proof: types.MerkleProof, expected_root: types.Hash) bool {
    var current = leafHash(leaf);
    for (merkle_proof.nodes.items) |node| {
        switch (node.position) {
            .left => current = hashInternal(node.hash, current),
            .right => current = hashInternal(current, node.hash),
        }
    }
    return std.mem.eql(u8, &current, &expected_root);
}
