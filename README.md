# bsvz-aria

**Auditable Real-time Inference Architecture** — BRC-122 implementation for BSV  
**Arquitectura de Inferencia Auditada en Tiempo Real** — Implementación BRC-122 para BSV

[English](#english) | [Español](#español)

---

## English

`bsvz-aria` is a Zig 0.16 implementation of the BRC-122 standard (Auditable Real-time Inference Architecture) for the BSV ecosystem. It provides cryptographically verifiable commitment and batch consistency for AI inference pipelines.

### What ARIA guarantees

- **Temporal commitment:** `model_hashes` and `state_hash` are published before inferences run.
- **Batch consistency:** all records in an epoch are committed by the `records_merkle_root` published in `EPOCH_CLOSE`.
- **Epoch linking:** `EPOCH_CLOSE.prev_txid` cryptographically links each close to the previous one (or to the genesis hash).
- **Tamper detection:** any change to a record, epoch identifier, or opening link invalidates verification.

> ARIA alone does **not** prove computational integrity. It does not prove that the committed model was executed or that the result is computationally correct. That guarantee is provided by the integration with [`zig-zkml`](https://github.com/samooth/zig-zkml).

### Usage flow

```text
EPOCH_OPEN (OP_RETURN)
        │
        │  inferences during the epoch
        ▼
AuditRecord x N (local storage)
        │
        ▼
EPOCH_CLOSE (OP_RETURN)
```

Transaction payload format:

```text
OP_FALSE OP_RETURN PUSH4(0x41524941) PUSHDATA(varint_len, json_bytes)
```

Where `0x41524941` is the ASCII string `ARIA`. The JSON is the canonical serialization of `EPOCH_CLOSE`: no whitespace outside strings, deterministic key ordering, hashes as `"sha256:<hex>"`.

### Installation

Requires Zig 0.16+ and dependencies configured in `build.zig.zon`:

- `bsvz`
- `zig-zkml`

```bash
zig build
```

### Tests

```bash
zig build test
```

### Minimal example

```zig
const std = @import("std");
const bsvz_aria = @import("bsvz-aria");
const types = bsvz_aria.api.types;
const aria = bsvz_aria.api.aria;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const genesis = types.hashBytes("genesis");
    var app = try aria.Aria.init(allocator, .{}, genesis, io);
    defer app.deinit();

    const model_hash = types.hashBytes("model-weights");
    const epoch = try app.openEpoch("ep_1700000000000_0001", "my-inference-service", &[_]types.ModelHash{
        .{ .model_id = "qwen3-next", .sha256 = model_hash },
    });
    defer {
        epoch.deinit();
        allocator.destroy(epoch);
    }

    _ = try app.addRecord(epoch, .{
        .model_id = "qwen3-next",
        .input = "input bytes",
        .output = "output bytes",
        .confidence = 0.95,
        .latency_ms = 47,
        .metadata = .{
            .decision_class = "triage_priority_1",
        },
    });

    const result = try app.closeEpoch(epoch);
    try app.verifyEpoch(epoch);

    std.debug.print("records={d}, merkle={s}\n", .{
        result.records_count,
        types.hashToHex(result.records_merkle_root),
    });
}
```

### zkML integration

`zig-zkml` allows obtaining the model's weights root and attaching computational proofs to records:

```zig
const weights_root = types.hashBytes("model-weights");
try app.zkml.commitModel("qwen3-next", weights_root);

const epoch = try app.openEpoch("ep_1700000000000_0001", "my-inference-service", &[_]types.ModelHash{
    .{ .model_id = "qwen3-next", .sha256 = weights_root },
});
```

ARIA and zkML are complementary layers: ARIA seals when and under what commitment the batch was performed; zkML proves computational execution. See [ZKML.md](docs/en/ZKML.md) — note that `ZkMlBridge.generateProof` currently returns a deterministic commitment placeholder, not a full zero-knowledge proof.

### Verification

```zig
const result = try app.closeEpoch(epoch);
try app.verifyEpoch(epoch);   // recomputes the Merkle root and compares against the commitment

const proof = try app.buildRecordProof(epoch, record_id);
const valid = types.merkle.verifyProof(record_hash, proof, result.records_merkle_root);
```

### Key features

- RFC 6962 Merkle tree with domain separation
- Canonical JSON serialization for deterministic hashing
- In-memory epoch and record store (`EpochStore`)
- SPV proof validation support
- zkML bridge with model commitments via `zig-zkml`

### Runtime configuration

| Parameter | Default |
| --- | ---: |
| Epoch duration | `60_000 ms` |
| Max records per epoch | `1_000_000` |
| Merkle batch size | `1000` |
| Fee | `500 sats/kB` |
| Storage | `memory` |

### Documentation

- [Architecture](docs/en/ARCHITECTURE.md)
- [API Reference](docs/en/API.md)
- [Getting Started](docs/en/GETTING_STARTED.md)
- [zkML Integration](docs/en/ZKML.md)
- [Contributing](docs/en/CONTRIBUTING.md)

### License

This project is licensed under the **OPEN BSV License**.

---

## Español

`bsvz-aria` es una implementación en Zig 0.16+ del estándar BRC-122 (Auditable Real-time Inference Architecture) para el ecosistema BSV. Provee compromiso y consistencia de lote criptográficamente verificables para pipelines de inferencia de IA.

### Qué garantiza ARIA

- **Compromiso temporal:** los `model_hashes` y `state_hash` se publican antes de realizar las inferencias.
- **Consistencia del lote:** todos los registros de un epoch están comprometidos por el `records_merkle_root` publicado en `EPOCH_CLOSE`.
- **Vinculación de epochs:** `EPOCH_CLOSE.prev_txid` enlaza criptográficamente cada cierre con el anterior (o con el hash de génesis).
- **Detección de alteraciones:** un cambio en un registro, identificador del epoch o enlace de apertura invalida la verificación.

> ARIA **no prueba por sí sola la integridad computacional**. No demuestra que se haya ejecutado el modelo comprometido ni que el resultado sea computacionalmente correcto. Esa garantía corresponde a la integración con [`zig-zkml`](https://github.com/samooth/zig-zkml).

### Flujo de uso

```text
EPOCH_OPEN (OP_RETURN)
        |
        |  inferencias durante el epoch
        ▼
AuditRecord x N (almacenamiento local)
        |
        ▼
EPOCH_CLOSE (OP_RETURN)
```

Formato del payload de transacciones:

```text
OP_FALSE OP_RETURN PUSH4(0x41524941) PUSHDATA(varint_len, json_bytes)
```

Donde `0x41524941` es la cadena ASCII `ARIA`. El JSON es la serialización canónica de `EPOCH_CLOSE`: sin whitespace fuera de los strings, orden de claves determinístico, hashes como `"sha256:<hex>"`.

### Instalación

Se requiere Zig 0.16+ y las dependencias configuradas en `build.zig.zon`:

- `bsvz`
- `zig-zkml`

```bash
zig build
```

### Tests

```bash
zig build test
```

### Ejemplo mínimo

```zig
const std = @import("std");
const bsvz_aria = @import("bsvz-aria");
const types = bsvz_aria.api.types;
const aria = bsvz_aria.api.aria;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const genesis = types.hashBytes("genesis");
    var app = try aria.Aria.init(allocator, .{}, genesis, io);
    defer app.deinit();

    const model_hash = types.hashBytes("model-weights");
    const epoch = try app.openEpoch("ep_1700000000000_0001", "my-inference-service", &[_]types.ModelHash{
        .{ .model_id = "qwen3-next", .sha256 = model_hash },
    });
    defer {
        epoch.deinit();
        allocator.destroy(epoch);
    }

    _ = try app.addRecord(epoch, .{
        .model_id = "qwen3-next",
        .input = "input bytes",
        .output = "output bytes",
        .confidence = 0.95,
        .latency_ms = 47,
        .metadata = .{
            .decision_class = "triage_priority_1",
        },
    });

    const result = try app.closeEpoch(epoch);
    try app.verifyEpoch(epoch);

    std.debug.print("records={d}, merkle={s}\n", .{
        result.records_count,
        types.hashToHex(result.records_merkle_root),
    });
}
```

### Integración con zkML

`zig-zkml` permite obtener la raíz de los pesos del modelo y adjuntar pruebas computacionales a los registros:

```zig
const weights_root = types.hashBytes("model-weights");
try app.zkml.commitModel("qwen3-next", weights_root);

const epoch = try app.openEpoch("ep_1700000000000_0001", "my-inference-service", &[_]types.ModelHash{
    .{ .model_id = "qwen3-next", .sha256 = weights_root },
});
```

ARIA y zkML son capas complementarias: ARIA sella cuándo y bajo qué compromiso se realizó el lote; zkML prueba la ejecución computacional. Ver [ZKML.md](docs/es/ZKML.md) — ten en cuenta que `ZkMlBridge.generateProof` actualmente devuelve un marcador de compromiso determinista, no una prueba de conocimiento cero completa.

### Verificación

```zig
const result = try app.closeEpoch(epoch);
try app.verifyEpoch(epoch);   // recalcula la raíz Merkle y la compara con el compromiso

const proof = try app.buildRecordProof(epoch, record_id);
const valid = types.merkle.verifyProof(record_hash, proof, result.records_merkle_root);
```

### Características principales

- Árbol Merkle RFC 6962 con separación de dominio
- Serialización JSON canónica para hashing determinista
- Store de epochs y registros en memoria (`EpochStore`)
- Soporte de validación de pruebas SPV
- Puente zkML con compromisos de modelo via `zig-zkml`

### Configuración runtime

| Parámetro | Valor por defecto |
| --- | ---: |
| Duración de epoch | `60_000 ms` |
| Máximo de registros por epoch | `1_000_000` |
| Tamaño de lote Merkle | `1000` |
| Fee | `500 sats/kB` |
| Almacenamiento | `memory` |

### Documentación

- [Arquitectura](docs/es/ARCHITECTURE.md)
- [Referencia de API](docs/es/API.md)
- [Guía de Inicio](docs/es/GETTING_STARTED.md)
- [Integración zkML](docs/es/ZKML.md)
- [Contribución](docs/es/CONTRIBUTING.md)

### Licencia

Este proyecto está licenciado bajo la **Licencia OPEN BSV**.
