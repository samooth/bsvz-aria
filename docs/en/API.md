# API Reference

## Types

### EpochId

Unique epoch identifier in the format `ep_<timestamp_ms>_<sequence_4digits>`.

```zig
pub const EpochId = struct {
    timestamp_ms: u64,
    sequence: u16,

    pub fn format(self: @This(), allocator: std.mem.Allocator) ![]u8;
    pub fn parse(s: []const u8) !EpochId;
};
```

### ModelHash

Associates a `model_id` with a SHA-256 hash.

```zig
pub const ModelHash = struct {
    model_id: []const u8,
    sha256: Hash,
};
```

### EPOCH_OPEN

Initial epoch commitment payload.

```zig
pub const EPOCH_OPEN = struct {
    aria_version: []const u8 = "1.0",
    type: []const u8 = "EPOCH_OPEN",
    epoch_id: EpochId,
    system_id: []const u8,
    model_hashes: std.StringHashMap(Hash),
    state_hash: Hash,
    timestamp: u64,
    nonce: Hash,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void;
};
```

### EPOCH_CLOSE

Epoch closing payload.

```zig
pub const EPOCH_CLOSE = struct {
    aria_version: []const u8 = "1.0",
    type: []const u8 = "EPOCH_CLOSE",
    epoch_id: []const u8,
    prev_txid: Hash,
    records_merkle_root: Hash,
    records_count: u32,
    duration_ms: u64,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void;
};
```

### AuditRecord

Individual inference record.

```zig
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

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void;
};
```

### Config

Global library configuration.

```zig
const Config = struct {
    default_epoch_duration_ms: u64 = 60_000,
    max_records_per_epoch: u32 = 1_000_000,
    merkle_batch_size: usize = 1000,
    default_fee_sats_per_kb: u64 = 500,
    default_store: StoreType = .memory,

    pub const StoreType = enum { memory, sqlite, file };

    pub fn validate(self: Config) !void;
};
```

## Aria

Main struct coordinating the epoch lifecycle.

```zig
pub const Aria = struct {
    allocator: std.mem.Allocator,
    config: Config,
    store: EpochStore,
    spv: SpvClient,

    pub fn init(allocator: std.mem.Allocator, cfg: Config, genesis: Hash) !Aria;
    pub fn deinit(self: *@This()) void;
    pub fn openEpoch(self: *Aria, id: []const u8, system_id: []const u8, model_hashes: []const ModelHash) !*Epoch;
    pub fn addRecord(self: *Aria, epoch: *Epoch, cfg: RecordConfig) !AuditRecord;
    pub fn closeEpoch(self: *Aria, epoch: *Epoch) !CloseResult;
    pub fn verifyEpoch(self: *Aria, epoch: *Epoch) !void;
};
```

## Epoch

Epoch lifecycle.

```zig
pub const Epoch = struct {
    allocator: std.mem.Allocator,
    state: EpochState,
    open_payload: EPOCH_OPEN,
    tree: MerkleTree,
    close_payload: EPOCH_CLOSE,
    records: std.ArrayList(AuditRecord),
    merkle_path: std.ArrayList(MerkleProofNode),
    next_sequence: u32,

    pub fn deinit(self: *@This()) void;
};
```

Functions:

```zig
pub fn createEpoch(allocator: std.mem.Allocator, id: []const u8, system_id: []const u8) !*Epoch;
pub fn addRecordToEpoch(epoch: *Epoch, cfg: RecordConfig) !AuditRecord;
pub fn closeEpoch(epoch: *Epoch) !void;
pub fn validateClose(epoch: *Epoch, expected_root: ?Hash) !void;
pub fn buildEpochProof(epoch: *Epoch, record_id: []const u8) !MerkleProof;
```

## Merkle

RFC 6962 with domain separation.

```zig
pub const MerkleTree = struct {
    allocator: std.mem.Allocator,
    leaves: std.ArrayList(Hash),
    cached_root: ?Hash = null,

    pub fn init(allocator: std.mem.Allocator) MerkleTree;
    pub fn deinit(self: *@This()) void;
};

pub fn addLeaf(tree: *MerkleTree, leaf: Hash) !void;
pub fn addLeaves(tree: *MerkleTree, new_leaves: []const Hash) !void;
pub fn root(tree: *const MerkleTree) !Hash;
pub fn proof(tree: *const MerkleTree, leaf_index: usize) !MerkleProof;
pub fn verifyProof(leaf: Hash, proof: MerkleProof, expected_root: Hash) bool;
```

The root of an empty tree is `SHA-256("")`.

## OP_RETURN

Format: `OP_FALSE OP_RETURN PUSH4(0x41524941) PUSHDATA(<json_bytes>)`

```zig
pub const ARIA_MAGIC = [4]u8{ 0x41, 0x52, 0x49, 0x41 };

pub fn buildOpReturnPayload(allocator: std.mem.Allocator, root: Hash, epoch_id: []const u8, count: usize) ![]u8;
pub fn parseOpReturnPayload(payload: []const u8) !struct { epoch_id: []const u8, root: Hash, count: usize };
```

## SPV

```zig
pub const SpvClient = struct {
    allocator: std.mem.Allocator,
    genesis_hash: Hash,
    tip_hash: Hash,
    tip_height: usize,
};

pub fn initSpv(allocator: std.mem.Allocator, genesis: Hash) SpvClient;
pub fn updateTip(client: *SpvClient, new_hash: Hash, height: usize) void;
pub fn verifySpvProof(client: *SpvClient, txid: Hash, proof: []const u8) !void;
pub fn verifyAriaAnchor(client: *SpvClient, epoch: *const Epoch, anchor_txid: Hash) !void;
```

## Verify

```zig
pub fn verifyEpochOpen(open: *const EPOCH_OPEN) !void;
pub fn verifyEpochClose(close: *const EPOCH_CLOSE, epoch: *const Epoch) !void;
pub fn verifyRecordInEpoch(record: *const AuditRecord, epoch: *const Epoch) !void;
pub fn verifyMerkleRoot(epoch: *const Epoch, expected_root: ?Hash) !void;
```

## Error sets

```zig
pub const EpochError = error{
    InvalidModelId, EmptyModelHashes, InvalidEpochId,
    AlreadyClosed, NotOpened, BroadcastFailed, InsufficientFunds,
    InvalidConfig, InvalidConfidence, SequenceOverflow,
    EmptyInput, EmptyOutput, EpochNotClosed, RootMismatch, RecordNotFound,
};

pub const VerifyError = error{
    OpenTxNotFound, CloseTxNotFound, PrevTxidMismatch,
    EpochIdMismatch, MerkleRootMismatch, ModelIdNotCommitted,
    SpvVerificationFailed, JsonParseFailed, AriaPayloadNotFound,
};

pub const MerkleError = error{ EmptyTree, InvalidProof, LeafNotFound };

pub const OpReturnError = error{
    AriaPayloadNotFound, InvalidPushData, InvalidEncoding, JsonParseFailed,
};
```

## zkML bridge

```zig
pub const ZkMlBridge = struct { ... };

pub fn initZkMlBridge(allocator: std.mem.Allocator) ZkMlBridge;
pub fn deinit(self: *@This()) void;
pub fn commitModel(self: *@This(), model_id: []const u8, model_hash: Hash) !void;
pub fn generateProof(self: *@This(), record: *const AuditRecord) ![]u8;
```
