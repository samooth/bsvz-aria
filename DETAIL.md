Acá va el prompt extendido para `bsvz-aria`, con el mismo nivel de detalle que el de privacy. Reemplazá el prompt anterior por este.

---

# Prompt Expandido: `bsvz-aria` — Implementation Specification

## Contexto general

Estoy construyendo `bsvz-aria`, una implementación en Zig 0.16+ del estándar BRC-122 (Auditable Real-time Inference Architecture) para el ecosistema BSV. Esta especificación responde a los detalles de implementación requeridos.

**Stack del que dependo:**
- `bsvz`: primitivas BSV (transactions, script, SPV, BEEF, crypto)
- `zig-zkml`: zkML sobre ktransformers-zig (F0 weights attestation ya funciona)
- `zig-ai`: inferencia IA nativa en Zig (en desarrollo)
- `zig-wallet-toolbox`: wallet BRC-100 con storage pluggable

**Principio rector**: ARIA prueba **compromiso temporal y consistencia de lote**, NO integridad computacional. La integridad computacional es responsabilidad de `zig-zkml`. ARIA y zkML son capas complementarias.

**Referencia canónica**: `github.com/JuanmPalencia/aria-bsv` (Python). Tu implementación debe ser byte-a-byte compatible donde el estándar lo exige.

---

## 1. Module Implementation Details

### 1.1 Firmas de funciones por módulo

**`src/types.zig` — Tipos fundamentales:**

```zig
pub const EpochId = struct {
    timestamp_ms: u64,
    sequence: u16,  // 4 digits, 0000-9999
    
    pub fn format(self: EpochId, allocator: std.mem.Allocator) ![]u8 {
        // "ep_<timestamp_ms>_<sequence_4digits>"
        // Ejemplo: "ep_1742848200000_0042"
    }
    
    pub fn parse(s: []const u8) !EpochId;
};

pub const ModelHash = struct {
    model_id: []const u8,
    sha256: [32]u8,  // hex: "sha256:<64_hex_chars>"
};

pub const EPOCH_OPEN = struct {
    aria_version: []const u8 = "1.0",
    type: []const u8 = "EPOCH_OPEN",
    epoch_id: EpochId,
    system_id: []const u8,
    model_hashes: std.StringHashMap([32]u8),  // model_id -> sha256
    state_hash: [32]u8,
    timestamp: u64,  // unix seconds
    nonce: [16]u8,  // 32 hex chars
};

pub const AuditRecord = struct {
    aria_version: []const u8 = "1.0",
    record_id: []const u8,  // "rec_<epoch_id>_<sequence_6digits>"
    epoch_id: []const u8,
    model_id: []const u8,
    input_hash: [32]u8,
    output_hash: [32]u8,
    confidence: f64,  // 0.0..1.0
    latency_ms: u32,
    sequence: u32,
    metadata: ?Metadata = null,
};

pub const Metadata = struct {
    decision_class: ?[]const u8 = null,
    custom: ?std.json.Value = null,
};

pub const EPOCH_CLOSE = struct {
    aria_version: []const u8 = "1.0",
    type: []const u8 = "EPOCH_CLOSE",
    epoch_id: []const u8,
    prev_txid: [32]u8,  // txid of EPOCH_OPEN (display-order)
    records_merkle_root: [32]u8,
    records_count: u32,
    duration_ms: u64,
};
```

**`src/epoch.zig` — Ciclo de vida del epoch:**

```zig
pub const Epoch = struct {
    allocator: std.mem.Allocator,
    open_payload: EPOCH_OPEN,
    open_txid: ?[32]u8 = null,
    records: std.ArrayList(AuditRecord),
    record_store: RecordStore,
    close_payload: ?EPOCH_CLOSE = null,
    close_txid: ?[32]u8 = null,
    config: Config,
    
    pub fn open(allocator: std.mem.Allocator, cfg: OpenConfig) !*Epoch;
    pub fn addRecord(self: *Epoch, record_cfg: RecordConfig) !void;
    pub fn close(self: *Epoch, close_cfg: CloseConfig) !CloseResult;
    pub fn getMerkleRoot(self: *const Epoch) ![32]u8;
    pub fn getRecordCount(self: *const Epoch) u32;
};

pub const OpenConfig = struct {
    system_id: []const u8,
    model_hashes: []const ModelHash,
    state_hash: ?[32]u8 = null,  // null = compute from model_hashes
    wallet: ?*wtb.Wallet = null,  // para broadcast
    broadcast: bool = true,
    nonce: ?[16]u8 = null,  // null = random
};

pub const RecordConfig = struct {
    model_id: []const u8,
    input: []const u8,  // se hashea localmente
    output: []const u8,  // se hashea localmente
    confidence: f64 = 0.0,
    latency_ms: u32 = 0,
    metadata: ?Metadata = null,
};

pub const CloseConfig = struct {
    wallet: ?*wtb.Wallet = null,
    broadcast: bool = true,
};

pub const CloseResult = struct {
    txid: [32]u8,
    records_count: u32,
    records_merkle_root: [32]u8,
    duration_ms: u64,
};
```

**`src/record.zig` — AuditRecord creation:**

```zig
pub fn createRecord(
    allocator: std.mem.Allocator,
    epoch: *const Epoch,
    cfg: RecordConfig,
) !AuditRecord;

pub fn hashRecord(record: *const AuditRecord) ![32]u8 {
    // SHA-256 del canonical JSON del record
    // Este hash es el leaf del Merkle tree
}

pub fn serializeRecord(record: *const AuditRecord) ![]u8 {
    // JSON canónico sin whitespace
}
```

**`src/merkle.zig` — RFC 6962 Merkle tree:**

```zig
pub const MerkleTree = struct {
    allocator: std.mem.Allocator,
    leaves: std.ArrayList([32]u8),
    cached_root: ?[32]u8 = null,
    
    pub fn init(allocator: std.mem.Allocator) MerkleTree;
    pub fn addLeaf(self: *MerkleTree, leaf: [32]u8) !void;
    pub fn addLeaves(self: *MerkleTree, leaves: []const [32]u8) !void;
    pub fn root(self: *MerkleTree) ![32]u8;
    pub fn proof(self: *const MerkleTree, leaf_index: usize) !MerkleProof;
    pub fn verifyProof(leaf: [32]u8, proof: MerkleProof, root: [32]u8) bool;
};

pub const MerkleProof = struct {
    leaf_index: usize,
    nodes: std.ArrayList(MerkleProofNode),
};

pub const MerkleProofNode = struct {
    hash: [32]u8,
    position: enum { left, right },
};
```

**`src/opreturn.zig` — Serialización OP_RETURN:**

```zig
pub const ARIA_MAGIC: [4]u8 = .{ 0x41, 0x52, 0x49, 0x41 };  // "ARIA"

pub fn serializeOpen(open: *const EPOCH_OPEN) ![]u8 {
    // Retorna el payload JSON sin whitespace
}

pub fn serializeClose(close: *const EPOCH_CLOSE) ![]u8 {
    // Retorna el payload JSON sin whitespace
}

pub fn buildOpenTx(
    allocator: std.mem.Allocator,
    open: *const EPOCH_OPEN,
    wallet: *wtb.Wallet,
) !bsvz.transaction.Transaction {
    // OP_FALSE OP_RETURN PUSH4(ARIA_MAGIC) PUSHDATA(json_bytes)
}

pub fn buildCloseTx(
    allocator: std.mem.Allocator,
    close: *const EPOCH_CLOSE,
    wallet: *wtb.Wallet,
) !bsvz.transaction.Transaction;

pub fn parseFromTx(tx: *const bsvz.transaction.Transaction) !union(enum) {
    open: EPOCH_OPEN,
    close: EPOCH_CLOSE,
};
```

**`src/spv.zig` — Verificación SPV:**

```zig
pub const HeaderSource = struct {
    /// Retorna el block header para una height dada
    getHeaderByHeight: *const fn (height: u32) !bsvz.spv.BlockHeader,
    /// Retorna el block header para un hash dado
    getHeaderByHash: *const fn (hash: [32]u8) !bsvz.spv.BlockHeader,
};

pub fn verifyCloseSpv(
    close_txid: [32]u8,
    close_tx: *const bsvz.transaction.Transaction,
    header_source: HeaderSource,
) !void {
    // Verifica que close_tx está minado en un bloque válido
}
```

**`src/zkml_bridge.zig` — Integración con zig-zkml:**

```zig
pub fn weightsMerkleRoot(model_handle: anytype) ![32]u8 {
    // Wrapper sobre kt_weights_merkle_root de zig-zkml F0
    // Si -Dwith_zkml=false, retorna error.ZkmlNotAvailable
}

pub fn attachProofToRecord(
    record: *AuditRecord,
    zkml_proof: []const u8,
) !void {
    // Adjunta prueba zkML al metadata.custom del record
}
```

**`src/verify.zig` — Verificación completa:**

```zig
pub const VerifyResult = struct {
    valid: bool,
    open_payload: EPOCH_OPEN,
    close_payload: EPOCH_CLOSE,
    error_code: ?VerifyError = null,
};

pub fn verifyEpoch(
    allocator: std.mem.Allocator,
    open_txid: [32]u8,
    cfg: VerifyConfig,
) !VerifyResult;

pub const VerifyConfig = struct {
    close_txid: ?[32]u8 = null,  // null = buscar por prev_txid
    header_source: ?HeaderSource = null,  // null = skip SPV
    tx_fetcher: TxFetcher,  // para traer transacciones
};

pub fn verifyRecord(
    allocator: std.mem.Allocator,
    epoch: *const VerifyResult,
    record: *const AuditRecord,
    merkle_proof: ?MerkleProof = null,
) !bool;
```

### 1.2 Formato del JSON canónico

**Decisión de diseño:** Implementar un **serializer propio** que garantice:
1. Orden de keys determinístico (orden de declaración en el struct)
2. Sin whitespace fuera de strings
3. Números sin trailing zeros innecesarios
4. Strings escapados según RFC 8259

**NO usar `std.json.stringify`** porque el orden de keys puede no ser estable entre compilaciones.

```zig
pub fn canonicalJson(value: anytype, allocator: std.mem.Allocator) ![]u8 {
    // Implementación manual que garantiza determinismo byte-a-byte
    // Ejemplo para EPOCH_OPEN:
    // {"aria_version":"1.0","type":"EPOCH_OPEN","epoch_id":"ep_...","system_id":"...",...}
}
```

**Test de determinismo:** 100 iteraciones del mismo struct → mismo JSON byte-a-byte.

### 1.3 Formato OP_RETURN exacto

```
OP_FALSE OP_RETURN PUSH4(0x41524941) PUSHDATA(varint_len, json_bytes)

donde:
- OP_FALSE = 0x00
- OP_RETURN = 0x6a
- PUSH4 = 0x04 0x41 0x52 0x49 0x41  ("ARIA" en ASCII)
- PUSHDATA = varint(len(json_bytes)) || json_bytes
```

**Ejemplo completo (EPOCH_OPEN):**
```
00 6a 04 41 52 49 41 fd 01 2c 7b 22 61 72 69 61 ...
^^ ^^ ^^ ^^^^^^^^^^^^^ ^^ ^^^^^ ^^^^^^^^^^^^^^^^^^^^
OF OR PUSH4 "ARIA"    len=300  JSON payload
```

### 1.4 Error handling

**Error sets completos:**

```zig
pub const EpochError = error{
    InvalidModelId,          // model_id no está en EPOCH_OPEN.model_hashes
    EmptyModelHashes,        // al menos 1 model_hash requerido
    InvalidEpochId,          // formato inválido
    AlreadyClosed,           // intentar addRecord después de close
    NotOpened,               // intentar close sin open
    BroadcastFailed,
    InsufficientFunds,
};

pub const RecordError = error{
    InvalidModelId,
    EmptyInput,
    EmptyOutput,
    InvalidConfidence,       // fuera de [0, 1]
    SequenceOverflow,        // > 999999
};

pub const VerifyError = error{
    OpenTxNotFound,
    CloseTxNotFound,
    PrevTxidMismatch,        // close.prev_txid != open_txid
    EpochIdMismatch,         // close.epoch_id != open.epoch_id
    MerkleRootMismatch,      // record no está en el árbol
    ModelIdNotCommitted,     // record.model_id no estaba en open
    SpvVerificationFailed,
    JsonParseFailed,
};

pub const MerkleError = error{
    EmptyTree,
    InvalidProof,
    LeafNotFound,
};
```

**Reglas:**
- Toda función pública retorna error union (`!T`).
- Errores internos de Zig (`OutOfMemory`) se propagan sin wrap.
- Errores específicos se mapean a los error sets de arriba.
- **Nunca** usar `catch unreachable` en código público.

---

## 2. Integration Details

### 2.1 Wallet integration (`zig-wallet-toolbox`)

**Enfoque:** `bsvz-aria` usa `zig-wallet-toolbox` para emitir transacciones, pero NO depende de él hard. Si el usuario no tiene wallet, puede construir las transacciones manualmente.

```zig
pub fn broadcastOpenTx(
    allocator: std.mem.Allocator,
    open: *const EPOCH_OPEN,
    wallet: *wtb.Wallet,
) ![32]u8 {
    // 1. Construir OP_RETURN con serializeOpen
    // 2. wallet.createAction con output OP_RETURN
    // 3. wallet.signAction
    // 4. Retornar txid
}
```

**Alternativa sin wallet:** usar `bsvz.broadcast` directamente (WhatsOnChain, TAAL, Arc).

```zig
pub fn broadcastOpenTxManual(
    allocator: std.mem.Allocator,
    open: *const EPOCH_OPEN,
    utxos: []const bsvz.transaction.OutPoint,
    privkey: bsvz.primitives.ec.PrivateKey,
    broadcaster: bsvz.broadcast.Broadcaster,
) ![32]u8;
```

### 2.2 RecordStore pluggable

**Interfaz:**

```zig
pub const RecordStore = struct {
    /// Agrega un record al storage
    addRecord: *const fn (record: AuditRecord) anyerror!void,
    /// Recupera todos los records de un epoch
    getRecords: *const fn (epoch_id: []const u8) anyerror![]AuditRecord,
    /// Recupera un record específico
    getRecord: *const fn (record_id: []const u8) anyerror!?AuditRecord,
};
```

**Implementaciones incluidas:**

```zig
pub const MemoryStore = struct {
    // En memoria, para tests
    records: std.ArrayList(AuditRecord),
};

pub const SqliteStore = struct {
    // En SQLite, para producción
    db_path: []const u8,
    // Schema: records(record_id TEXT PRIMARY KEY, epoch_id TEXT, data JSON)
};

pub const FileStore = struct {
    // JSON Lines en archivo, para simplicidad
    file_path: []const u8,
};
```

**Default:** `MemoryStore` en tests, `SqliteStore` en ejemplos de producción.

### 2.3 zkML integration (`zig-zkml`)

**Build flag:** `-Dwith_zkml=true` habilita la integración. Sin el flag, `zkml_bridge.zig` es un stub que retorna `error.ZkmlNotAvailable`.

**Con el flag:**

```zig
const zkml = @import("zig-zkml");

pub fn weightsMerkleRoot(model_handle: anytype) ![32]u8 {
    // Llama a zkml.kt_weights_merkle_root(model_handle)
    // Retorna la raíz Blake3+Merkle de los pesos
}
```

**Uso en EPOCH_OPEN:**

```zig
const weights_root = try aria.zkml_bridge.weightsMerkleRoot(my_model);

const epoch = try aria.Epoch.open(allocator, .{
    .system_id = "my-inference-service",
    .model_hashes = &.{
        .{ .model_id = "qwen3-next", .sha256 = weights_root },
    },
    .wallet = &wallet,
});
```

**Adjuntar prueba zkML a un record:**

```zig
const inference_result = try zig_ai.infer(.{ .model = model, .input = input });
const zkml_proof = try zig_zkml.prove(.{
    .model_root = weights_root,
    .trace = inference_result.trace,
});

try epoch.addRecord(.{
    .model_id = "qwen3-next",
    .input = input,
    .output = inference_result.output,
    .metadata = .{
        .custom = .{ .zkml_proof = .{ .bytes = zkml_proof } },
    },
});
```

### 2.4 zig-ai integration (opcional)

`zig-ai` es la librería de inferencia nativa. `bsvz-aria` NO depende de ella directamente, pero el usuario puede integrarla así:

```zig
const ai = @import("zig-ai");
const aria = @import("bsvz-aria");

const result = try ai.infer(.{ .model = model, .input = input });

try epoch.addRecord(.{
    .model_id = "my-model",
    .input = input,
    .output = result.output,
    .confidence = result.confidence,
    .latency_ms = result.latency_ms,
});
```

---

## 3. Algorithm Implementation

### 3.1 Construcción del Merkle tree RFC 6962

**Algoritmo:**

```
Input: lista de leaves (hashes de AuditRecords)
Output: raíz Merkle

1. Si hay 0 leaves: return SHA-256("")
2. Si hay 1 leaf: return leaf
3. Construir nivel por nivel:
   current_level = leaves
   while len(current_level) > 1:
     next_level = []
     for i in 0..len(current_level) step 2:
       if i+1 < len(current_level):
         // Dos hijos
         combined = SHA-256(0x01 || current_level[i] || current_level[i+1])
       else:
         // Un hijo impar (RFC 6962: subir el impar)
         combined = SHA-256(0x01 || current_level[i] || current_level[i])
       next_level.append(combined)
     current_level = next_level
   return current_level[0]
```

**Separación de dominio (RFC 6962):**
- Leaf hash: `SHA-256(0x00 || data)`
- Internal hash: `SHA-256(0x01 || left || right)`

Esto previene ataques de segunda preimagen donde un atacante podría confundir leaves con nodos internos.

**Merkle proof:**

```
Input: leaf_index, tree
Output: lista de (hash, position) para reconstruir la raíz

1. current_index = leaf_index
2. current_level = leaves
3. proof_nodes = []
4. while len(current_level) > 1:
     sibling_index = current_index XOR 1
     if sibling_index < len(current_level):
       proof_nodes.append((current_level[sibling_index], 
                          if current_index % 2 == 0: right else: left))
     // Construir siguiente nivel
     next_level = []
     for i in 0..len(current_level) step 2:
       next_level.append(hash_pair(current_level[i], current_level[i+1]))
     current_level = next_level
     current_index = current_index / 2
5. return proof_nodes
```

**Verificación de proof:**

```
Input: leaf, proof_nodes, expected_root
Output: bool

1. current = leaf
2. for (sibling, position) in proof_nodes:
     if position == left:
       current = SHA-256(0x01 || sibling || current)
     else:
       current = SHA-256(0x01 || current || sibling)
3. return current == expected_root
```

### 3.2 Verificación de epoch (algoritmo completo)

```
Input: open_txid, optional close_txid, header_source
Output: VerifyResult

1. Fetch open_tx por open_txid (usando tx_fetcher)
2. Parsear ARIA payload de open_tx
   - Si no hay payload ARIA: return VerifyError.OpenTxNotFound
   - Si payload.type != "EPOCH_OPEN": return VerifyError.JsonParseFailed
3. Si close_txid no fue proveído:
   - Buscar transacciones con prev_txid == open_txid
   - Filtrar por payload.type == "EPOCH_CLOSE"
   - Si no se encuentra: return VerifyError.CloseTxNotFound
4. Fetch close_tx por close_txid
5. Parsear ARIA payload de close_tx
   - Si payload.type != "EPOCH_CLOSE": return VerifyError.JsonParseFailed
6. Verificar enlaces:
   - close.prev_txid == open_txid
     Si falla: return VerifyError.PrevTxidMismatch (TAMPERED)
   - close.epoch_id == open.epoch_id
     Si falla: return VerifyError.EpochIdMismatch (TAMPERED)
7. Si header_source fue proveído:
   - verifyCloseSpv(close_txid, close_tx, header_source)
   - Si falla: return VerifyError.SpvVerificationFailed
8. Return VerifyResult{valid=true, open_payload, close_payload}
```

### 3.3 Verificación de record individual

```
Input: epoch (verificado), record, optional merkle_proof
Output: bool

1. Verificar record.epoch_id == epoch.open_payload.epoch_id
   Si falla: return false (TAMPERED)
2. Verificar record.model_id está en epoch.open_payload.model_hashes
   Si falla: return false (TAMPERED)
3. Si merkle_proof fue proveído:
   - Hash del record = hashRecord(record)
   - Verify proof contra epoch.close_payload.records_merkle_root
   - Si falla: return false (TAMPERED)
4. Si no hay merkle_proof pero hay RecordStore local:
   - Reconstruir árbol desde todos los records del epoch
   - Verificar que el hash del record está en el árbol
   - Verificar que la raíz coincide con close.records_merkle_root
   - Si falla: return false (TAMPERED)
5. Return true
```

### 3.4 Generación de nonce

```
Input: nada (o seed opcional)
Output: [16]u8

1. Si seed fue proveído: usar HMAC-DRBG(seed) para generar 16 bytes
2. Si no: usar std.crypto.random para 16 bytes
3. Retornar como [16]u8
```

**Propósito del nonce:** prevenir que dos EPOCH_OPEN con los mismos model_hashes y state_hash produzcan la misma transacción (lo que causaría conflicto de txid).

### 3.5 Cálculo de state_hash (si no se provee)

```
Input: model_hashes
Output: state_hash [32]u8

1. Ordenar model_hashes por model_id (lexicográfico)
2. Concatenar: model_id_1 || sha256_1 || model_id_2 || sha256_2 || ...
3. state_hash = SHA-256(concatenated)
```

Esto da un state_hash determinístico si el usuario no lo especifica.

---

## 4. Configuration/Setup

### 4.1 `build.zig` completo

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // Feature flag: zkML integration
    const with_zkml = b.option(bool, "with_zkml", "Enable zig-zkml integration") orelse false;
    
    // Dependencies
    const bsvz_dep = b.dependency("bsvz", .{
        .target = target,
        .optimize = optimize,
    });
    
    const wtb_dep = b.dependency("zig-wallet-toolbox", .{
        .target = target,
        .optimize = optimize,
    });
    
    const zkml_dep = if (with_zkml) b.dependency("zig-zkml", .{
        .target = target,
        .optimize = optimize,
    }) else null;
    
    // Main module
    const aria_mod = b.addModule("bsvz-aria", .{
        .root_source_file = b.path("src/aria.zig"),
        .imports = &.{
            .{ .name = "bsvz", .module = bsvz_dep.module("bsvz") },
            .{ .name = "zig-wallet-toolbox", .module = wtb_dep.module("zig-wallet-toolbox") },
        },
    });
    
    if (zkml_dep) |zkml| {
        aria_mod.addImport("zig-zkml", zkml.module("zig-zkml"));
    }
    
    // Tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/aria.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.root_module.addImport("bsvz", bsvz_dep.module("bsvz"));
    unit_tests.root_module.addImport("zig-wallet-toolbox", wtb_dep.module("zig-wallet-toolbox"));
    if (zkml_dep) |zkml| {
        unit_tests.root_module.addImport("zig-zkml", zkml.module("zig-zkml"));
    }
    
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
    
    // Examples
    for ([_][]const u8{
        "examples/basic_epoch.zig",
        "examples/with_zkml.zig",
        "examples/verify_spv.zig",
    }) |example_file| {
        const exe = b.addExecutable(.{
            .name = std.fs.path.basename(example_file),
            .root_source_file = b.path(example_file),
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("bsvz", bsvz_dep.module("bsvz"));
        exe.root_module.addImport("zig-wallet-toolbox", wtb_dep.module("zig-wallet-toolbox"));
        exe.root_module.addImport("bsvz-aria", aria_mod);
        if (zkml_dep) |zkml| {
            exe.root_module.addImport("zig-zkml", zkml.module("zig-zkml"));
        }
        b.installArtifact(exe);
    }
}
```

### 4.2 `build.zig.zon`

```zig
.{
    .name = "bsvz-aria",
    .version = "0.1.0",
    .dependencies = .{
        .bsvz = .{
            .url = "https://github.com/samooth/bsvz/archive/<pinned-commit>.tar.gz",
            .hash = "<content-hash>",
        },
        .@"zig-wallet-toolbox" = .{
            .url = "https://github.com/samooth/zig-wallet-toolbox/archive/<pinned-commit>.tar.gz",
            .hash = "<content-hash>",
        },
        // zig-zkml solo si -Dwith_zkml=true
    },
    .paths = .{"build.zig", "build.zig.zon", "src", "examples", "README.md", "SECURITY.md"},
}
```

### 4.3 Runtime configuration

```zig
pub const Config = struct {
    // Epoch defaults
    default_epoch_duration_ms: u64 = 60_000,  // 1 minuto
    
    // Records
    max_records_per_epoch: u32 = 1_000_000,
    
    // Merkle
    merkle_batch_size: usize = 1000,  // para reconstrucción incremental
    
    // Fees
    default_fee_sats_per_kb: u64 = 500,
    
    // Storage
    default_store: StoreType = .sqlite,
    
    pub const StoreType = enum { memory, sqlite, file };
    
    pub fn validate(self: Config) !void {
        if (self.max_records_per_epoch == 0) return error.InvalidConfig;
        if (self.default_epoch_duration_ms == 0) return error.InvalidConfig;
    }
};
```

---

## 5. Security Implementation

### 5.1 Threat model

**Ataques que PREVIENE:**
- **Fabricación retroactiva**: EPOCH_OPEN se compromete ANTES de inferir, así que no se puede inventar un modelo después
- **Alteración de records**: el Merkle root en EPOCH_CLOSE sella todos los records; alterar uno rompe la raíz
- **Desconexión de epochs**: el `prev_txid` en EPOCH_CLOSE enlaza criptográficamente con el OPEN
- **Replay de epochs**: cada epoch tiene un `epoch_id` único (timestamp + sequence)

**Ataques que NO PREVIENE (documentar en SECURITY.md):**
- **Mentiras en el momento**: el operador puede registrar hashes falsos DURANTE la inferencia (ARIA no verifica cómputo, eso es zkML)
- **Ejecución de modelo distinto**: el operador puede comprometer un modelo X pero ejecutar Y (ARIA no verifica ejecución)
- **Metadata de red**: IPs, timing de broadcast pueden correlacionar
- **Disponibilidad**: si el operador pierde los AuditRecords locales, no se pueden recuperar (solo el Merkle root queda on-chain)

### 5.2 Parámetros criptográficos

**Hashes:**
- SHA-256 para Merkle tree (RFC 6962 con separación 0x00/0x01)
- SHA-256 para hashes de input/output/model
- SHA-256d (double) NO se usa en ARIA (solo en Fiat-Shamir de firmas, que ARIA no hace)

**Merkle tree:**
- RFC 6962 (Certificate Transparency)
- Leaf hash: `SHA-256(0x00 || data)`
- Internal hash: `SHA-256(0x01 || left || right)`

**Transacciones:**
- P2PKH para outputs de fee (si aplica)
- OP_RETURN para payload ARIA
- Standard sighash ALL para firma

### 5.3 Secure random number generation

**Usar `std.crypto.random` para:**
- Nonce del EPOCH_OPEN (si no se provee)
- Cualquier otro valor aleatorio

**Nunca usar:**
- `std.rand.DefaultPrng` sin seed explícito
- Valores hardcodeados

**Testing:** permitir seed override para reproducibilidad:

```zig
pub fn secureRandomWithSeed(seed: ?[32]u8) std.rand.Random {
    if (seed) |s| {
        return std.rand.DefaultPrng.init(s).random();
    }
    return std.crypto.random;
}
```

### 5.4 Validación de inputs

**En cada función pública:**

```zig
pub fn open(allocator: std.mem.Allocator, cfg: OpenConfig) !*Epoch {
    if (cfg.system_id.len == 0) return EpochError.InvalidEpochId;
    if (cfg.model_hashes.len == 0) return EpochError.EmptyModelHashes;
    
    for (cfg.model_hashes) |mh| {
        if (mh.model_id.len == 0) return EpochError.InvalidModelId;
    }
    // ... más validaciones
}
```

**Validación de JSON parseado:**

```zig
fn parseOpenPayload(json_bytes: []const u8) !EPOCH_OPEN {
    // Validar que todos los campos requeridos están presentes
    // Validar tipos (epoch_id es string, timestamp es number, etc.)
    // Validar longitudes (model_id no vacío, sha256 es 64 hex chars)
}
```

---

## Tests obligatorios (expandidos)

### Merkle RFC 6962 test vectors

```zig
test "merkle: RFC 6962 known vectors" {
    // Vector 1: 1 leaf
    const leaf1 = sha256("leaf1");
    const root1 = try merkleRoot(&.{leaf1});
    try std.testing.expectEqual(leaf1, root1);
    
    // Vector 2: 2 leaves
    const leaf2 = sha256("leaf2");
    const expected_root2 = sha256(&.{0x01} ++ leaf1 ++ leaf2);
    const root2 = try merkleRoot(&.{leaf1, leaf2});
    try std.testing.expectEqual(expected_root2, root2);
    
    // Vector 3: 3 leaves (impar)
    const leaf3 = sha256("leaf3");
    const combined_12 = sha256(&.{0x01} ++ leaf1 ++ leaf2);
    const expected_root3 = sha256(&.{0x01} ++ combined_12 ++ leaf3);
    const root3 = try merkleRoot(&.{leaf1, leaf2, leaf3});
    try std.testing.expectEqual(expected_root3, root3);
    
    // Vector 4: 7 leaves (impar grande)
    // ... similar
}
```

### JSON determinism test

```zig
test "json: deterministic serialization" {
    const open = EPOCH_OPEN{
        .epoch_id = .{ .timestamp_ms = 1742848200000, .sequence = 42 },
        .system_id = "test-system",
        .model_hashes = .{ .{ .model_id = "model1", .sha256 = [32]u8{...} }},
        // ...
    };
    
    var results = std.ArrayList([]u8).init(allocator);
    for (0..100) |_| {
        const json = try canonicalJson(open, allocator);
        try results.append(json);
    }
    
    // Todos deben ser idénticos byte-a-byte
    for (results.items[1..]) |json| {
        try std.testing.expectEqualSlices(u8, results.items[0], json);
    }
}
```

### Tamper detection tests

```zig
test "verify: tampered CLOSE prev_txid" {
    // Crear epoch válido
    const epoch = try createTestEpoch(allocator);
    try epoch.close(.{});
    
    // Alterar 1 bit del prev_txid en el CLOSE
    var tampered_close = epoch.close_payload.?;
    tampered_close.prev_txid[0] ^= 0x01;
    
    const result = try verifyEpoch(allocator, epoch.open_txid.?, .{
        .close_txid = epoch.close_txid.?,
    });
    
    try std.testing.expectError(VerifyError.PrevTxidMismatch, result);
}

test "verify: tampered record" {
    const epoch = try createTestEpochWithRecords(allocator, 10);
    try epoch.close(.{});
    
    // Alterar 1 record
    var tampered_record = epoch.records.items[5];
    tampered_record.input_hash[0] ^= 0x01;
    
    const valid = try verifyRecord(allocator, &epoch.verify_result, &tampered_record, null);
    try std.testing.expect(!valid);
}
```

### Empty epoch test

```zig
test "epoch: empty epoch (0 records)" {
    var epoch = try Epoch.open(allocator, .{
        .system_id = "test",
        .model_hashes = &.{.{ .model_id = "m1", .sha256 = [32]u8{...} }},
        .broadcast = false,
    });
    
    const result = try epoch.close(.{ .broadcast = false });
    
    try std.testing.expectEqual(@as(u32, 0), result.records_count);
    // Merkle root de árbol vacío debe ser SHA-256("")
    try std.testing.expectEqual(sha256(""), result.records_merkle_root);
}
```

### SPV round-trip test

```zig
test "spv: verify CLOSE against fake header" {
    // Construir header fake con Merkle root que incluye close_tx
    const close_tx = try createFakeCloseTx(allocator);
    const header = try createFakeHeaderWithTx(allocator, close_tx);
    
    const header_source = HeaderSource{
        .getHeaderByHash = fake_get_header,
        .getHeaderByHeight = fake_get_header_by_height,
    };
    
    try verifyCloseSpv(close_tx.txid, close_tx, header_source);
}
```

### zkML integration test (con `-Dwith_zkml=true`)

```zig
test "zkml: weights root matches EPOCH_OPEN" {
    const model = try loadTestModel();
    const weights_root = try zkml_bridge.weightsMerkleRoot(model);
    
    var epoch = try Epoch.open(allocator, .{
        .system_id = "test",
        .model_hashes = &.{.{ .model_id = "test-model", .sha256 = weights_root }},
        .broadcast = false,
    });
    
    // Verificar que el model_id está en el epoch
    try std.testing.expect(epoch.open_payload.model_hashes.contains("test-model"));
    try std.testing.expectEqual(weights_root, epoch.open_payload.model_hashes.get("test-model").?);
}
```

---

## Deliverables finales

1. **Código Zig compilable**: `zig build --summary all test` pasa sin leaks.
   - Sin `-Dwith_zkml`: todos los tests pasan
   - Con `-Dwith_zkml=true`: tests de integración zkML también pasan

2. **README.md**:
   - Qué es ARIA y qué problema resuelve
   - Qué prueba (compromiso temporal + integridad de lote) y qué NO prueba (integridad computacional)
   - Integración con zig-zkml para pruebas computacionales
   - Ejemplo mínimo completo
   - Configuración runtime
   - RecordStore pluggable (memory/sqlite/file)

3. **SECURITY.md**:
   - Threat model completo
   - Ataques prevenidos y no prevenidos
   - Parámetros criptográficos
   - Consideraciones de disponibilidad (AuditRecords locales)

4. **Tests**: todos los listados arriba pasan.

5. **Examples**: 3 ejemplos compilables y ejecutables:
   - `basic_epoch.zig`: epoch simple con 3 records fake
   - `with_zkml.zig`: epoch usando kt_weights_merkle_root de F0
   - `verify_spv.zig`: verificación SPV de un CLOSE real

---

## Estilo y convenciones

- Comentarios en inglés.
- Documentación pública (`///`) en cada tipo/función exportada.
- Naming: `camelCase` funciones, `PascalCase` tipos, `snake_case` archivos.
- Allocator-aware: todas las funciones que allocan reciben `std.mem.Allocator`.
- Error sets específicos (ver sección 1.4).
- **Nunca** usar `catch unreachable` en código público.
- Tests usan `std.testing` con allocator tracking.
- JSON canónico con serializer propio (NO `std.json.stringify`).

---

Usá este prompt con tu agente. Si pide más detalles sobre algún punto específico (por ejemplo, el formato exacto del JSON canónico, o la integración con un RecordStore particular), decime y lo ampliamos. También puedo preparar prompts equivalentes para `bsvz-notary` (BRC-220), `bsvz-timebank` (BRC-168), o `bsvz-exchange` (BRC-79) cuando los necesites.
