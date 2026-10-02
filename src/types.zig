const std = @import("std");

pub const Hash = [32]u8;

pub const EpochId = struct {
    timestamp_ms: u64,
    sequence: u16,

    pub fn format(self: @This(), allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "ep_{d}_{d:0>4}", .{ self.timestamp_ms, self.sequence });
    }

    pub fn parse(s: []const u8) !EpochId {
        if (!std.mem.startsWith(u8, s, "ep_")) return error.InvalidEpochId;
        const rest = s["ep_".len..];
        var parts = std.mem.splitScalar(u8, rest, '_');
        const ts_str = parts.next() orelse return error.InvalidEpochId;
        const seq_str = parts.next() orelse return error.InvalidEpochId;
        if (parts.next() != null) return error.InvalidEpochId;
        const timestamp_ms = try std.fmt.parseInt(u64, ts_str, 10);
        const sequence = try std.fmt.parseInt(u16, seq_str, 10);
        return .{ .timestamp_ms = timestamp_ms, .sequence = sequence };
    }
};

pub const ModelHash = struct {
    model_id: []const u8,
    sha256: Hash,
};

pub const Metadata = struct {
    decision_class: ?[]const u8 = null,
    custom: ?std.json.Value = null,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        if (self.decision_class) |dc| allocator.free(dc);
        if (self.custom) |*c| deinitJsonValue(allocator, c.*);
        self.* = .{};
    }

    pub fn clone(self: *const @This(), allocator: std.mem.Allocator) !Metadata {
        var custom: ?std.json.Value = null;
        if (self.custom) |c| {
            custom = try cloneJsonValue(allocator, c);
        }
        var decision_class: ?[]const u8 = null;
        if (self.decision_class) |dc| {
            decision_class = try allocator.dupe(u8, dc);
        }
        return .{ .decision_class = decision_class, .custom = custom };
    }
};

pub const EPOCH_OPEN = struct {
    aria_version: []const u8 = "1.0",
    type: []const u8 = "EPOCH_OPEN",
    epoch_id: EpochId,
    system_id: []const u8,
    model_hashes: std.StringHashMap(Hash),
    state_hash: Hash,
    timestamp: u64,
    nonce: Hash,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        var it = self.model_hashes.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        self.model_hashes.deinit();
        self.* = .{
            .epoch_id = .{ .timestamp_ms = 0, .sequence = 0 },
            .system_id = "",
            .model_hashes = std.StringHashMap(Hash).init(allocator),
            .state_hash = .{0} ** 32,
            .timestamp = 0,
            .nonce = .{0} ** 32,
        };
    }
};

pub const AuditRecord = struct {
    aria_version: []const u8 = "1.0",
    record_id: []const u8,
    epoch_id: []const u8,
    model_id: []const u8,
    input_hash: Hash,
    output_hash: Hash,
    confidence: f64,
    latency_ms: u32,
    sequence: u32,
    metadata: ?Metadata = null,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.record_id);
        allocator.free(self.epoch_id);
        allocator.free(self.model_id);
        if (self.metadata) |*m| m.deinit(allocator);
        self.* = .{
            .record_id = "",
            .epoch_id = "",
            .model_id = "",
            .input_hash = .{0} ** 32,
            .output_hash = .{0} ** 32,
            .confidence = 0,
            .latency_ms = 0,
            .sequence = 0,
            .metadata = null,
        };
    }
};

pub const EPOCH_CLOSE = struct {
    aria_version: []const u8 = "1.0",
    type: []const u8 = "EPOCH_CLOSE",
    epoch_id: []const u8,
    prev_txid: Hash,
    records_merkle_root: Hash,
    records_count: u32,
    duration_ms: u64,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.epoch_id);
        self.* = .{
            .epoch_id = "",
            .prev_txid = .{0} ** 32,
            .records_merkle_root = .{0} ** 32,
            .records_count = 0,
            .duration_ms = 0,
        };
    }
};

pub const Config = struct {
    default_epoch_duration_ms: u64 = 60_000,
    max_records_per_epoch: u32 = 1_000_000,
    merkle_batch_size: usize = 1000,
    default_fee_sats_per_kb: u64 = 500,
    default_store: StoreType = .memory,

    pub const StoreType = enum { memory, sqlite, file };

    pub fn validate(self: Config) !void {
        if (self.max_records_per_epoch == 0) return error.InvalidConfig;
        if (self.default_epoch_duration_ms == 0) return error.InvalidConfig;
    }
};

pub const RecordConfig = struct {
    model_id: []const u8,
    input: []const u8,
    output: []const u8,
    confidence: f64 = 0.0,
    latency_ms: u32 = 0,
    metadata: ?Metadata = null,
};

pub const CloseResult = struct {
    txid: Hash,
    records_count: u32,
    records_merkle_root: Hash,
    duration_ms: u64,
};

pub const EpochError = error{
    InvalidModelId,
    EmptyModelHashes,
    InvalidEpochId,
    AlreadyClosed,
    NotOpened,
    BroadcastFailed,
    InsufficientFunds,
    InvalidConfig,
    InvalidConfidence,
    SequenceOverflow,
    EmptyInput,
    EmptyOutput,
    EpochNotClosed,
    RootMismatch,
    CountMismatch,
    RecordNotFound,
};

pub const RecordError = error{
    InvalidModelId,
    EmptyInput,
    EmptyOutput,
    InvalidConfidence,
    SequenceOverflow,
};

pub const VerifyError = error{
    OpenTxNotFound,
    CloseTxNotFound,
    PrevTxidMismatch,
    EpochIdMismatch,
    MerkleRootMismatch,
    ModelIdNotCommitted,
    SpvVerificationFailed,
    JsonParseFailed,
    AriaPayloadNotFound,
    SequenceMismatch,
};

pub const MerkleError = error{
    EmptyTree,
    InvalidProof,
    LeafNotFound,
};

pub const OpReturnError = error{
    AriaPayloadNotFound,
    InvalidPushData,
    InvalidEncoding,
    JsonParseFailed,
};

fn deinitJsonValue(allocator: std.mem.Allocator, value: std.json.Value) void {
    switch (value) {
        .object => |obj| {
            var mutable_obj = obj;
            var it = mutable_obj.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                deinitJsonValue(allocator, entry.value_ptr.*);
            }
            mutable_obj.deinit(allocator);
        },
        .array => |arr| {
            var mutable_arr = arr;
            for (mutable_arr.items) |item| deinitJsonValue(allocator, item);
            mutable_arr.deinit();
        },
        .string => |s| allocator.free(s),
        else => {},
    }
}

pub fn cloneJsonValue(allocator: std.mem.Allocator, value: std.json.Value) !std.json.Value {
    switch (value) {
        .null => return .null,
        .bool => |b| return .{ .bool = b },
        .integer => |i| return .{ .integer = i },
        .float => |f| return .{ .float = f },
        .number_string => |ns| {
            const copy = try allocator.dupe(u8, ns);
            return .{ .number_string = copy };
        },
        .string => |s| {
            const copy = try allocator.dupe(u8, s);
            return .{ .string = copy };
        },
        .array => |arr| {
            var new_arr = std.json.Array.init(allocator);
            for (arr.items) |item| {
                try new_arr.append(try cloneJsonValue(allocator, item));
            }
            return .{ .array = new_arr };
        },
        .object => |obj| {
            var new_obj = std.json.ObjectMap.empty;
            var it = obj.iterator();
            while (it.next()) |entry| {
                const key = try allocator.dupe(u8, entry.key_ptr.*);
                const val = try cloneJsonValue(allocator, entry.value_ptr.*);
                try new_obj.put(allocator, key, val);
            }
            return .{ .object = new_obj };
        },
    }
}

pub fn hashBytes(data: []const u8) Hash {
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &out, .{});
    return out;
}

pub fn hashToHex(hash: Hash) [64]u8 {
    return std.fmt.bytesToHex(hash, .lower);
}

pub fn hashToPrefixed(hash: Hash) [71]u8 {
    const hex = hashToHex(hash);
    var result: [71]u8 = undefined;
    @memcpy(result[0.."sha256:".len], "sha256:");
    @memcpy(result["sha256:".len..], &hex);
    return result;
}

pub fn parseHashPrefixed(s: []const u8) !Hash {
    if (std.mem.startsWith(u8, s, "sha256:")) {
        const hex_part = s["sha256:".len..];
        if (hex_part.len != 64) return error.InvalidHash;
        var out: [32]u8 = undefined;
        _ = try std.fmt.hexToBytes(&out, hex_part);
        return out;
    }
    if (s.len == 64) {
        var out: [32]u8 = undefined;
        _ = try std.fmt.hexToBytes(&out, s);
        return out;
    }
    return error.InvalidHash;
}

pub fn computeStateHash(allocator: std.mem.Allocator, model_hashes: []const ModelHash) !Hash {
    var sorted = try std.ArrayList(ModelHash).initCapacity(allocator, model_hashes.len);
    defer sorted.deinit(allocator);
    try sorted.appendSlice(allocator, model_hashes);
    std.mem.sort(ModelHash, sorted.items, {}, struct {
        fn lessThan(_: void, a: ModelHash, b: ModelHash) bool {
            return std.mem.lessThan(u8, a.model_id, b.model_id);
        }
    }.lessThan);

    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(allocator);
    for (sorted.items) |mh| {
        try buf.appendSlice(allocator, mh.model_id);
        try buf.appendSlice(allocator, &mh.sha256);
    }
    return hashBytes(buf.items);
}

pub const MerkleProofNode = struct {
    hash: Hash,
    position: MerkleProofNodePosition,
};

pub const MerkleProofNodePosition = enum { left, right };

pub const MerkleProof = struct {
    leaf_index: usize,
    nodes: std.ArrayList(MerkleProofNode),

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.nodes.deinit(allocator);
        self.* = .{ .leaf_index = 0, .nodes = std.ArrayList(MerkleProofNode).empty };
    }
};

pub const MerkleTree = struct {
    allocator: std.mem.Allocator,
    leaves: std.ArrayList(Hash),

    pub fn init(allocator: std.mem.Allocator) MerkleTree {
        return .{
            .allocator = allocator,
            .leaves = std.ArrayList(Hash).empty,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.leaves.deinit(self.allocator);
        self.* = .{
            .allocator = undefined,
            .leaves = std.ArrayList(Hash).empty,
        };
    }
};

pub const EpochState = enum { open, closed };

pub const Epoch = struct {
    allocator: std.mem.Allocator,
    state: EpochState,
    open_payload: EPOCH_OPEN,
    tree: MerkleTree,
    close_payload: EPOCH_CLOSE,
    records: std.ArrayList(AuditRecord),
    merkle_path: std.ArrayList(MerkleProofNode),
    next_sequence: u32,
    flags: u32,

    pub fn deinit(self: *@This()) void {
        self.open_payload.deinit(self.allocator);
        self.close_payload.deinit(self.allocator);
        self.tree.deinit();
        self.merkle_path.deinit(self.allocator);
        for (self.records.items) |*rec| rec.deinit(self.allocator);
        self.records.deinit(self.allocator);
        self.* = .{
            .allocator = undefined,
            .state = .open,
            .open_payload = EPOCH_OPEN{
                .aria_version = "1.0",
                .type = "EPOCH_OPEN",
                .epoch_id = .{ .timestamp_ms = 0, .sequence = 0 },
                .system_id = "",
                .model_hashes = std.StringHashMap(Hash).init(self.allocator),
                .state_hash = .{0} ** 32,
                .timestamp = 0,
                .nonce = .{0} ** 32,
            },
            .tree = MerkleTree.init(self.allocator),
            .close_payload = EPOCH_CLOSE{
                .aria_version = "1.0",
                .type = "EPOCH_CLOSE",
                .epoch_id = "",
                .prev_txid = .{0} ** 32,
                .records_merkle_root = .{0} ** 32,
                .records_count = 0,
                .duration_ms = 0,
            },
            .records = std.ArrayList(AuditRecord).empty,
            .merkle_path = std.ArrayList(MerkleProofNode).empty,
            .next_sequence = 0,
            .flags = 0,
        };
    }
};
