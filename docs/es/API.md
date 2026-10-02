# Referencia de API

## Tipos

### Hash

`pub const Hash = [32]u8` — un digest SHA-256.

Ayudas:

```zig
pub fn hashBytes(data: []const u8) Hash;
pub fn hashToHex(hash: Hash) [64]u8;
pub fn hashToPrefixed(hash: Hash) [71]u8;   // "sha256:" + hex
pub fn parseHashPrefixed(s: []const u8) !Hash;  // acepta "sha256:<hex>" o <hex> sin prefijo
```

### EpochId

Identificador único de epoch en el formato `ep_<timestamp_ms>_<sequence_4dígitos>`.

```zig
pub const EpochId = struct {
    timestamp_ms: u64,
    sequence: u16,

    pub fn format(self: @This(), allocator: std.mem.Allocator) ![]u8;
    pub fn parse(s: []const u8) !EpochId;
};
```

### ModelHash

Asocia un `model_id` con un hash SHA-256.

```zig
pub const ModelHash = struct {
    model_id: []const u8,
    sha256: Hash,
};
```

### Metadata

Metadatos opcionales por registro.

```zig
pub const Metadata = struct {
    decision_class: ?[]const u8 = null,
    custom: ?std.json.Value = null,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void;
    pub fn clone(self: *const @This(), allocator: std.mem.Allocator) !Metadata;
};
```

### EPOCH_OPEN

Payload de apertura. `system_id` se toma **prestado** del llamador; las claves de `model_hashes` son propias.

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

Registro individual de inferencia. `record_id`, `epoch_id` y `model_id` son **propios** (liberados en `deinit`).

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

Payload de cierre. `epoch_id` es **propio** (formateado al cerrar).

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

### Conjuntos de errores

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

Estructura principal que coordina el ciclo de vida del epoch. Todas las funciones se declaran dentro de la estructura y se invocan con sintaxis de método.

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

Notas de propiedad:

- `openEpoch` calcula `state_hash` a partir de `model_hashes`, rellena `timestamp` desde `io` y un `nonce` aleatorio, y valida con `verifyEpochOpen`. El epoch se registra en `store` (puntero prestado) pero es **del llamador**: invocar `epoch.deinit()` y luego `allocator.destroy(epoch)`.
- `closeEpoch` encadena `prev_txid` al cierre anterior (o al hash de génesis para el primero), deriva el `txid` como `SHA-256(JSON canónico de EPOCH_CLOSE)` y mide `duration_ms` con `io`.
- `addRecord` devuelve un `*AuditRecord` **prestado**, propiedad de `epoch.records`; el puntero es válido hasta la siguiente mutación del epoch.
- `verifyEpoch` recalcula la raíz Merkle y la compara con la `records_merkle_root` comprometida (detección de alteraciones), y luego verifica la consistencia del payload de cierre.

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

`EpochStore` es un índice: nunca libera epochs ni registros. `createEpoch` analiza `id` estrictamente como `ep_<timestamp_ms>_<sequence>` y rechaza ids de modelo duplicados al abrir (`EpochError.InvalidModelId`).

## Record

```zig
pub fn createRecord(allocator: std.mem.Allocator, epoch: *const types.Epoch, cfg: types.RecordConfig) !types.AuditRecord;
pub fn hashRecord(record: *const types.AuditRecord, allocator: std.mem.Allocator) ![32]u8;
pub fn serializeRecord(record: *const types.AuditRecord, allocator: std.mem.Allocator) ![]u8;
```

`createRecord` valida: `input`/`output` no vacíos, `confidence` en `[0, 1]` y `sequence <= 999999`.

## Merkle

Árbol Merkle RFC 6962 con separación de dominio:

- hash de hoja: `SHA-256(0x00 || hoja)`
- hash interno: `SHA-256(0x01 || izquierdo || derecho)`
- raíz de árbol vacío: `SHA-256("")`
- nodos impares se promueven (no se duplican)

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

Formato de payload BRC-122: `OP_FALSE OP_RETURN PUSH4(0x41524941) PUSHDATA(varint_len, json_bytes)` donde el JSON es la serialización canónica de `EPOCH_CLOSE`.

```zig
pub const ARIA_MAGIC = [4]u8{ 0x41, 0x52, 0x49, 0x41 };

pub fn buildOpReturnPayload(allocator: std.mem.Allocator, close: *const types.EPOCH_CLOSE) ![]u8;
pub fn parseOpReturnPayload(allocator: std.mem.Allocator, payload: []const u8) !types.EPOCH_CLOSE;
```

El prefijo de longitud es un varint de Bitcoin (`<0xfd`: 1 byte; `0xfd`+2, `0xfe`+4, `0xff`+8 bytes, little-endian).

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

`verifySpvProof` actualmente realiza validación estructural (no vacío, múltiplo de 32 bytes). La verificación completa de la cadena de encabezados contra las primitivas de `bsvz` es un trabajo pendiente; ver [SECURITY.md](../SECURITY.md).

## Verify

```zig
pub fn verifyEpochOpen(open: *const types.EPOCH_OPEN) !void;
pub fn verifyEpochClose(close: *const types.EPOCH_CLOSE, epoch: *const types.Epoch) !void;
pub fn verifyRecordInEpoch(record: *const types.AuditRecord, epoch: *const types.Epoch) !void;
pub fn verifyMerkleRoot(epoch: *const types.Epoch, expected_root: ?types.Hash) !void;
```

- `verifyEpochOpen`: verifica `type == "EPOCH_OPEN"`, `aria_version == "1.0"` y al menos un modelo comprometido.
- `verifyEpochClose`: verifica `type == "EPOCH_CLOSE"`, estado cerrado, y que la raíz Merkle y el conteo de registros comprometidos coincidan con el epoch.
- `verifyRecordInEpoch`: verifica que el `epoch_id` del registro coincida con el epoch y que `sequence < next_sequence`.
- `verifyMerkleRoot`: recalcula la raíz desde el árbol y la compara con `expected_root` cuando se proporciona.

## Puente zkML

```zig
pub const ZkMlBridge = struct {
    pub fn init(allocator: std.mem.Allocator) ZkMlBridge;
    pub fn deinit(self: *@This()) void;
    pub fn commitModel(self: *@This(), model_id: []const u8, model_hash: types.Hash) !void;
    pub fn generateProof(self: *@This(), record: *const types.AuditRecord) ![]u8;
};

pub fn initZkMlBridge(allocator: std.mem.Allocator) ZkMlBridge;
```

`generateProof` devuelve una prueba de compromiso determinista de 32 bytes: `SHA-256(SHA-256(record_json) || model_commitment)`. Falla con `EpochError.InvalidModelId` si el modelo del registro no tiene compromiso registrado. Esto es un marcador de posición hasta integrar la generación de pruebas real de `zig-zkml`; ver [ZKML.md](ZKML.md).

## JSON canónico

```zig
pub fn canonicalJson(value: anytype, allocator: std.mem.Allocator) ![]u8;
```

Serialización determinista: claves de struct y objeto ordenadas lexicográficamente, sin whitespace fuera de strings, escaping RFC 8259, campos `Hash` como strings `"sha256:<hex>"`, y `NaN`/`Inf` rechazados con `error.InvalidFloat`.
