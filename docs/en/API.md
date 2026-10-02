# API Reference

## Types

### Hash

`pub const Hash = [32]u8` — a SHA-256 digest.

Helpers:

```zig
pub fn hashBytes(data: []const u8) Hash;
pub fn hashToHex(hash: Hash) [64]u8;
pub fn hashToPrefixed(hash: Hash) [71]u8;   // "sha256:" + hex
pub fn parseHashPrefixed(s: []const u8) !Hash;  // accepts "sha256:<hex>" or bare <hex>
```

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

### Metadata

Optional per-record metadata.

```zig
pub const Metadata = struct {
    decision_class: ?[]const u8 = null,
    custom: ?std.json.Value = null,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void;
    pub fn clone(self: *const @This(), allocator: std.mem.Allocator) !Metadata;
};
```

### EPOCH_OPEN

Opening commitment payload. `system_id` is **borrowed** from the caller; `model_hashes` keys are owned.

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

### AuditRecord

Individual inference record. `record_id`, `epoch_id` and `model_id` are **owned** (freed in `deinit`).

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

### EPOCH_CLOSE

Closing commitment payload. `epoch_id` is **owned** (formatted at close time).

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

### Config

```zig
pub const Config = struct {
    default_epoch_duration_ms: u64 = 60_000,
    max_records_per_epoch: u32 = 1_000_000,
    merkle_batch_size: usize = 1000,
    default_fee_sats_per_kb: u64 = 500,
    default_store: StoreType = .memory,

    pub const StoreType = enum { memory, sqlite, file };
    pub fn validate(self: Config) !void;
};
```

### RecordConfig / CloseResult

```zig
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
```

### Error sets

```zig
pub const EpochError = error{
    InvalidModelId, EmptyModelHashes, InvalidEpochId,
    AlreadyClosed, NotOpened, BroadcastFailed, InsufficientFunds,
    InvalidConfig, InvalidConfidence, SequenceOverflow,
    EmptyInput, EmptyOutput, EpochNotClosed, RootMismatch,
    CountMismatch, RecordNotFound,
};

pub const RecordError = error{
    InvalidModelId, EmptyInput, EmptyOutput,
    InvalidConfidence, SequenceOverflow,
};

pub const VerifyError = error{
    OpenTxNotFound, CloseTxNotFound, PrevTxidMismatch,
    EpochIdMismatch, MerkleRootMismatch, ModelIdNotCommitted,
    SpvVerificationFailed, JsonParseFailed, AriaPayloadNotFound,
    SequenceMismatch,
};

pub const MerkleError = error{ EmptyTree, InvalidProof, LeafNotFound };

pub const OpReturnError = error{
    AriaPayloadNotFound, InvalidPushData, InvalidEncoding, JsonParseFailed,
};
```

## Aria

Main struct coordinating the epoch lifecycle. All functions are declared inside the struct and are called with method syntax.

```zig
pub const Aria = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    config: types.Config,
    store: epoch.EpochStore,
    spv: spv.SpvClient,
    zkml: zkml_bridge.ZkMlBridge,
    last_txid: types.Hash,

    pub fn init(allocator: std.mem.Allocator, cfg: types.Config, genesis: types.Hash, io: std.Io) !Aria;
    pub fn deinit(self: *@This()) void;

    pub fn openEpoch(self: *@This(), id: []const u8, system_id: []const u8, model_hashes: []const types.ModelHash) !*types.Epoch;
    pub fn closeEpoch(self: *@This(), epoch: *types.Epoch) !types.CloseResult;
    pub fn addRecord(self: *@This(), epoch: *types.Epoch, cfg: types.RecordConfig) !*types.AuditRecord;
    pub fn verifyEpoch(self: *@This(), epoch: *const types.Epoch) !void;
    pub fn buildRecordProof(self: *@This(), epoch: *types.Epoch, record_id: []const u8) !types.MerkleProof;
};
```

Ownership notes:

- `openEpoch` computes `state_hash` from `model_hashes`, fills `timestamp` from `io` and a random `nonce`, then validates with `verifyEpochOpen`. The epoch is registered in `store` (borrowed pointer) but **owned by the caller**: call `epoch.deinit()` then `allocator.destroy(epoch)`.
- `closeEpoch` chains `prev_txid` to the previous close (or the genesis hash for the first epoch), derives the `txid` as `SHA-256(canonical JSON of EPOCH_CLOSE)`, and measures `duration_ms` with `io`.
- `addRecord` returns a **borrowed** `*AuditRecord` owned by `epoch.records`; the pointer is valid until the next mutation of the epoch.
- `verifyEpoch` recomputes the Merkle root and compares it against the committed `records_merkle_root` (tamper detection), then checks close-payload consistency.

## Epoch

```zig
pub const EpochStore = struct {
    pub fn init(allocator: std.mem.Allocator) EpochStore;
    pub fn deinit(self: *@This()) void;
    pub fn getEpoch(self: *@This(), id: []const u8) ?*types.Epoch;
    pub fn getRecord(self: *@This(), id: []const u8) ?*types.AuditRecord;
};

pub fn createEpoch(allocator: std.mem.Allocator, id: []const u8, system_id: []const u8) !*types.Epoch;
pub fn addRecordToEpoch(epoch: *types.Epoch, cfg: types.RecordConfig) !void;
pub fn closeEpoch(epoch: *types.Epoch, prev_txid: types.Hash) !void;
pub fn validateClose(epoch: *types.Epoch, expected_root: ?types.Hash) !void;
pub fn buildEpochProof(epoch: *types.Epoch, record_id: []const u8) !types.MerkleProof;
```

`EpochStore` is an index: it never frees epochs or records. `createEpoch` parses `id` strictly as `ep_<timestamp_ms>_<sequence>` and rejects duplicates of model ids at open time (`EpochError.InvalidModelId`).

## Record

```zig
pub fn createRecord(allocator: std.mem.Allocator, epoch: *const types.Epoch, cfg: types.RecordConfig) !types.AuditRecord;
pub fn hashRecord(record: *const types.AuditRecord, allocator: std.mem.Allocator) ![32]u8;
pub fn serializeRecord(record: *const types.AuditRecord, allocator: std.mem.Allocator) ![]u8;
```

`createRecord` validates: non-empty `input`/`output`, `confidence` in `[0, 1]`, and `sequence <= 999999`.

## Merkle

RFC 6962 Merkle tree with domain separation:

- leaf hash: `SHA-256(0x00 || leaf)`
- internal hash: `SHA-256(0x01 || left || right)`
- empty tree root: `SHA-256("")`
- odd nodes are promoted (not duplicated)

```zig
pub fn addLeaf(tree: *types.MerkleTree, leaf: types.Hash) !void;
pub fn addLeaves(tree: *types.MerkleTree, new_leaves: []const types.Hash) !void;
pub fn root(tree: *const types.MerkleTree) !types.Hash;
pub fn proof(tree: *const types.MerkleTree, leaf_index: usize) !types.MerkleProof;
pub fn verifyProof(leaf: types.Hash, merkle_proof: types.MerkleProof, expected_root: types.Hash) bool;
pub fn leafHash(leaf: types.Hash) types.Hash;
pub fn hashInternal(left: types.Hash, right: types.Hash) types.Hash;
```

## OP_RETURN

BRC-122 payload format: `OP_FALSE OP_RETURN PUSH4(0x41524941) PUSHDATA(varint_len, json_bytes)` where the JSON is the canonical serialization of `EPOCH_CLOSE`.

```zig
pub const ARIA_MAGIC = [4]u8{ 0x41, 0x52, 0x49, 0x41 };

pub fn buildOpReturnPayload(allocator: std.mem.Allocator, close: *const types.EPOCH_CLOSE) ![]u8;
pub fn parseOpReturnPayload(allocator: std.mem.Allocator, payload: []const u8) !types.EPOCH_CLOSE;
```

The length prefix is a Bitcoin varint (`<0xfd`: 1 byte; `0xfd`+2, `0xfe`+4, `0xff`+8 bytes, little-endian).

## SPV

```zig
pub const SpvClient = struct {
    allocator: std.mem.Allocator,
    genesis_hash: types.Hash,
    tip_hash: types.Hash,
    tip_height: usize,
};

pub fn initSpv(allocator: std.mem.Allocator, genesis: types.Hash) SpvClient;
pub fn updateTip(client: *SpvClient, new_hash: types.Hash, height: usize) void;
pub fn verifySpvProof(client: *SpvClient, txid: types.Hash, proof: []const u8) !void;
pub fn verifyAriaAnchor(client: *SpvClient, epoch: *const types.Epoch, anchor_txid: types.Hash) !void;
```

`verifySpvProof` currently performs structural validation (non-empty, multiple of 32 bytes). Full header-chain verification against `bsvz` primitives is a follow-up; see [SECURITY.md](../SECURITY.md).

## Verify

```zig
pub fn verifyEpochOpen(open: *const types.EPOCH_OPEN) !void;
pub fn verifyEpochClose(close: *const types.EPOCH_CLOSE, epoch: *const types.Epoch) !void;
pub fn verifyRecordInEpoch(record: *const types.AuditRecord, epoch: *const types.Epoch) !void;
pub fn verifyMerkleRoot(epoch: *const types.Epoch, expected_root: ?types.Hash) !void;
```

- `verifyEpochOpen`: checks `type == "EPOCH_OPEN"`, `aria_version == "1.0"`, and at least one committed model.
- `verifyEpochClose`: checks `type == "EPOCH_CLOSE"`, closed state, and that the committed Merkle root and record count match the epoch.
- `verifyRecordInEpoch`: checks the record's `epoch_id` matches the epoch and `sequence < next_sequence`.
- `verifyMerkleRoot`: recomputes the root from the tree and compares against `expected_root` when provided.

## zkML bridge

```zig
pub const ZkMlBridge = struct {
    pub fn init(allocator: std.mem.Allocator) ZkMlBridge;
    pub fn deinit(self: *@This()) void;
    pub fn commitModel(self: *@This(), model_id: []const u8, model_hash: types.Hash) !void;
    pub fn generateProof(self: *@This(), record: *const types.AuditRecord) ![]u8;
};

pub fn initZkMlBridge(allocator: std.mem.Allocator) ZkMlBridge;
```

`generateProof` returns a 32-byte deterministic commitment proof: `SHA-256(SHA-256(record_json) || model_commitment)`. It fails with `EpochError.InvalidModelId` when the record's model has no registered commitment. This is a placeholder until full `zig-zkml` proof generation is wired in; see [ZKML.md](ZKML.md).

## Canonical JSON

```zig
pub fn canonicalJson(value: anytype, allocator: std.mem.Allocator) ![]u8;
```

Deterministic serialization: struct keys sorted lexicographically, object keys sorted, no whitespace outside strings, RFC 8259 escaping, `Hash` fields as `"sha256:<hex>"` strings, and `NaN`/`Inf` rejected with `error.InvalidFloat`.
