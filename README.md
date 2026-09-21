# bsvz-aria

**Auditable Real-time Inference Architecture** — BRC-122 implementation for BSV  
**Arquitectura de Inferencia Auditada en Tiempo Real** — Implementación BRC-122 para BSV

[English](#english) | [Español](#español)

---

## English

`bsvz-aria` is a Zig 0.16+ implementation of the BRC-122 standard (Auditable Real-time Inference Architecture) for the BSV ecosystem. It provides cryptographically verifiable commitment and batch consistency for AI inference pipelines.

### What ARIA guarantees

- **Temporal commitment:** `model_hashes` and `state_hash` are published before inferences run.
- **Batch consistency:** all records in an epoch are committed by the `records_merkle_root` published in `EPOCH_CLOSE`.
- **Epoch linking:** `EPOCH_CLOSE.prev_txid` cryptographically links the close to its opening.
- **Tamper detection:** any change to a record, epoch identifier, or opening link invalidates verification.

> ARIA alone does **not** prove computational integrity. It does not prove that the committed model was executed or that the result is computationally correct. That guarantee is provided by the optional integration with [`zig-zkml`](https://github.com/samooth/zig-zkml).

### Usage flow

```text
EPOCH_OPEN (OP_RETURN)
        │
        │  inferences during the epoch
        ▼
AuditRecord x N (local storage)
        |
        ▼
EPOCH_CLOSE (OP_RETURN)
```

Transaction payload format:

```text
OP_FALSE OP_RETURN PUSH4(0x41524941) PUSHDATA(varint_len, json_bytes)
```

Where `0x41524941` is the ASCII string `ARIA`. JSON is serialized without whitespace outside strings and with deterministic key ordering.

### Installation

Requires Zig 0.16+ and dependencies configured in `build.zig.zon`:

- `bsvz`
- `zig-wallet-toolbox`
- `zig-zkml` (optional)

```bash
zig build
```

### Tests

```bash
zig build test
```

With zkML integration:

```bash
zig build test -Dwith_zkml=true
```

### Minimal example

```zig
const std = @import("std");
const aria = @import("bsvz-aria");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var model_hashes = std.ArrayList(aria.ModelHash).init(allocator);
    defer model_hashes.deinit();

    try model_hashes.append(.{
        .model_id = "qwen3-next",
        .sha256 = [_]u8{0} ** 32,
    });

    var epoch = try aria.Epoch.open(allocator, .{
        .system_id = "my-inference-service",
        .model_hashes = model_hashes.items,
        .broadcast = false,
    });
    defer epoch.deinit();

    try epoch.addRecord(.{
        .model_id = "qwen3-next",
        .input = "input bytes",
        .output = "output bytes",
        .confidence = 0.95,
        .latency_ms = 47,
        .metadata = .{
            .decision_class = "triage_priority_1",
        },
    });

    const result = try epoch.close(.{ .broadcast = false });

    std.debug.print("records={d}, merkle={any}\n", .{
        result.records_count,
        result.records_merkle_root,
    });
}
```

### zkML Integration

`zig-zkml` allows obtaining the model's weights root and attaching computational proofs to records:

```zig
const weights_root = try aria.zkml_bridge.weightsMerkleRoot(model);

var epoch = try aria.Epoch.open(allocator, .{
    .system_id = "my-inference-service",
    .model_hashes = &.{.{
        .model_id = "qwen3-next",
        .sha256 = weights_root,
    }},
    .broadcast = false,
});

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

ARIA and zkML are complementary layers: ARIA seals when and under what commitment the batch was performed; zkML proves computational execution.

### Verification

```zig
const verified = try aria.verifyEpoch(allocator, epoch_open_txid, .{
    .header_source = header_source,
    .tx_fetcher = tx_fetcher,
});

const valid = try aria.verifyRecord(
    allocator,
    &verified,
    &audit_record,
    merkle_proof,
);
```

### Key features

- RFC 6962 Merkle tree with domain separation
- Canonical JSON serialization for deterministic hashing
- Pluggable `RecordStore` interface (`MemoryStore`, `SqliteStore`, `FileStore`)
- SPV verification support
- Optional zkML integration via `zig-zkml`

### Runtime configuration

| Parameter | Default |
| --- | ---: |
| Epoch duration | `60_000 ms` |
| Max records per epoch | `1_000_000` |
| Merkle batch size | `1000` |
| Fee | `500 sats/kB` |
| Storage | `sqlite` |

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
- **Vinculación de epochs:** `EPOCH_CLOSE.prev_txid` enlaza criptográficamente el cierre con su apertura.
- **Detección de alteraciones:** un cambio en un registro, identificador del epoch o enlace al opening invalida la verificación.

> ARIA **no prueba por sí sola la integridad computacional**. No demuestra que se haya ejecutado el modelo comprometido ni que el resultado sea computacionalmente correcto. Esa garantía corresponde a la integración opcional con [`zig-zkml`](https://github.com/samooth/zig-zkml).

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

Donde `0x41524941` es la cadena ASCII `ARIA`. El JSON se serializa sin whitespace fuera de los strings y con un orden de claves determinístico.

### Instalación

Se requiere Zig 0.16 o superior y las dependencias configuradas en `build.zig.zon`:

- `bsvz`
- `zig-wallet-toolbox`
- `zig-zkml` (opcional)

```bash
zig build
```

### Tests

```bash
zig build test
```

Con integración zkML:

```bash
zig build test -Dwith_zkml=true
```

### Ejemplo mínimo

```zig
const std = @import("std");
const aria = @import("bsvz-aria");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var model_hashes = std.ArrayList(aria.ModelHash).init(allocator);
    defer model_hashes.deinit();

    try model_hashes.append(.{
        .model_id = "qwen3-next",
        .sha256 = [_]u8{0} ** 32,
    });

    var epoch = try aria.Epoch.open(allocator, .{
        .system_id = "my-inference-service",
        .model_hashes = model_hashes.items,
        .broadcast = false,
    });
    defer epoch.deinit();

    try epoch.addRecord(.{
        .model_id = "qwen3-next",
        .input = "input bytes",
        .output = "output bytes",
        .confidence = 0.95,
        .latency_ms = 47,
        .metadata = .{
            .decision_class = "triage_priority_1",
        },
    });

    const result = try epoch.close(.{ .broadcast = false });

    std.debug.print("records={d}, merkle={any}\n", .{
        result.records_count,
        result.records_merkle_root,
    });
}
```

### Integración con zkML

`zig-zkml` permite obtener la raíz de los pesos del modelo y adjuntar pruebas computacionales a los registros:

```zig
const weights_root = try aria.zkml_bridge.weightsMerkleRoot(model);

var epoch = try aria.Epoch.open(allocator, .{
    .system_id = "my-inference-service",
    .model_hashes = &.{.{
        .model_id = "qwen3-next",
        .sha256 = weights_root,
    }},
    .broadcast = false,
});

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

ARIA y zkML son capas complementarias: ARIA sella cuándo y bajo qué compromiso se realizó el lote; zkML demuestra la ejecución computacional.

### Verificación

```zig
const verified = try aria.verifyEpoch(allocator, epoch_open_txid, .{
    .header_source = header_source,
    .tx_fetcher = tx_fetcher,
});

const valid = try aria.verifyRecord(
    allocator,
    &verified,
    &audit_record,
    merkle_proof,
);
```

### Características principales

- Árbol Merkle RFC 6962 con separación de dominio
- Serialización JSON canónica para hashing determinista
- Interfaz `RecordStore` intercambiable (`MemoryStore`, `SqliteStore`, `FileStore`)
- Verificación SPV
- Integración opcional con zkML via `zig-zkml`

### Configuración runtime

| Parámetro | Valor por defecto |
| --- | ---: |
| Duración de epoch | `60_000 ms` |
| Máximo de registros por epoch | `1_000_000` |
| Tamaño de lote Merkle | `1000` |
| Fee | `500 sats/kB` |
| Almacenamiento | `sqlite` |

### Documentación

- [Arquitectura](docs/es/ARCHITECTURE.md)
- [Referencia de API](docs/es/API.md)
- [Guía de Inicio](docs/es/GETTING_STARTED.md)
- [Integración zkML](docs/es/ZKML.md)
- [Contribución](docs/es/CONTRIBUTING.md)

### Licencia

Este proyecto está licenciado bajo la **Licencia OPEN BSV**.
