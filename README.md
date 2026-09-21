# bsvz-aria

`bsvz-aria` is a Zig 0.16+ implementation of the BRC-122 standard, **Auditable Real-time Inference Architecture**, for the BSV ecosystem.

`bsvz-aria` es una implementación en Zig 0.16+ del estándar BRC-122, **Auditable Real-time Inference Architecture**, para el ecosistema BSV.

ARIA allows auditable recording of the AI inference lifecycle through two on-chain commitments:
ARIA permite registrar de forma auditable el ciclo de vida de inferencias de IA mediante dos compromisos on-chain:

1. `EPOCH_OPEN` commits the models and state before running inferences.
2. `EPOCH_CLOSE` seals the batch of records through a Merkle root and links it to `EPOCH_OPEN`.

Individual `AuditRecord`s are stored locally and are not published one by one on-chain.
Los `AuditRecord` individuales se almacenan localmente y no se publican uno por uno en la cadena.

## What ARIA guarantees / Qué garantiza ARIA

ARIA proves:
ARIA prueba:

- **Temporal commitment:** `model_hashes` and `state_hash` are published before inferences are run.
- **Batch consistency:** all records in an epoch are committed by the `records_merkle_root` published in `EPOCH_CLOSE`.
- **Epoch linking:** `EPOCH_CLOSE.prev_txid` cryptographically links the close to its opening.
- **Tamper detection:** a change to a record, epoch identifier, or opening link invalidates verification.

ARIA **alone does not prove computational integrity**. It does not prove that the committed model was executed or that the result is computationally correct. That guarantee is provided by the optional integration with [`zig-zkml`](https://github.com/samooth/zig-zkml).

ARIA **no prueba por sí sola la integridad computacional**. No demuestra que se haya ejecutado el modelo comprometido ni que el resultado sea computacionalmente correcto. Esa garantía corresponde a la integración opcional con [`zig-zkml`](https://github.com/samooth/zig-zkml).

The canonical protocol reference is [`JuanmPalencia/aria-bsv`](https://github.com/JuanmPalencia/aria-bsv).

## Usage flow / Flujo de uso

```text
EPOCH_OPEN (OP_RETURN)
        |
        |  inferences during the epoch
        ▼
AuditRecord x N (local storage)
        |
        ▼
EPOCH_CLOSE (OP_RETURN)
```

The transaction payload uses the format:
El payload de las transacciones usa el formato:

```text
OP_FALSE OP_RETURN PUSH4(0x41524941) PUSHDATA(varint_len, json_bytes)
```

Where `0x41524941` is the ASCII string `ARIA`. JSON is serialized without whitespace outside strings and with deterministic key ordering.
Donde `0x41524941` es la cadena ASCII `ARIA`. El JSON se serializa sin whitespace fuera de los strings y con un orden de claves determinístico.

## Installation and build / Instalación y build

Zig 0.16+ is required and the dependencies configured in `build.zig.zon`:
Se requiere Zig 0.16 o superior y las dependencias configuradas en `build.zig.zon`:

- `bsvz`
- `zig-wallet-toolbox`
- `zig-zkml` (optional / opcional)

Run tests / Ejecutar los tests:

```bash
zig build test
```

Run the basic example / Ejecutar el ejemplo básico:

```bash
zig build run --example basic_epoch
```

Enable zkML integration / Habilitar la integración con zkML:

```bash
zig build test -Dwith_zkml=true
```

Without `-Dwith_zkml=true`, `zkml_bridge` exposes the corresponding interface but returns `error.ZkmlNotAvailable`.

## Minimal example / Ejemplo mínimo

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

## zkML Integration / Integración con zkML

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

`zig-zkml` permite obtener la raíz de los pesos del modelo y adjuntar pruebas computacionales a los registros.

ARIA and zkML are complementary layers: ARIA seals when and under what commitment the batch was performed; zkML proves computational execution.
ARIA y zkML son capas complementarias: ARIA sella cuándo y bajo qué compromiso se realizó el lote; zkML demuestra la ejecución computacional.

## Verification / Verificación

`verifyEpoch` fetches and parses the `EPOCH_OPEN` and `EPOCH_CLOSE` transactions, checks their links, and optionally verifies the close via SPV:

```zig
const verified = try aria.verifyEpoch(allocator, epoch_open_txid, .{
    .header_source = header_source,
    .tx_fetcher = tx_fetcher,
});
```

`verifyRecord` validates the epoch identifier, the committed model, and the record's membership in the Merkle root:

```zig
const valid = try aria.verifyRecord(
    allocator,
    &verified,
    &audit_record,
    merkle_proof,
);
```

If no Merkle proof is provided, the verifier can rebuild the tree from locally stored records.
Si no se proporciona una prueba Merkle, el verificador puede reconstruir el árbol a partir de los registros almacenados localmente.

## Merkle RFC 6962

The tree uses domain separation:
El árbol utiliza separación de dominio:

- leaf: `SHA-256(0x00 || data)`
- internal node: `SHA-256(0x01 || left || right)`

Trees with any number of leaves are supported, including odd sizes. The root of an empty tree is `SHA-256("")`.
Se admiten árboles con cualquier cantidad de hojas, incluidos los tamaños impares. El root de un árbol vacío es `SHA-256("")`.

## Canonical JSON

Serialization uses a custom serializer to guarantee:
La serialización usa un serializer propio para garantizar:

- deterministic key ordering;
- no whitespace outside strings;
- no unnecessary trailing zeros;
- RFC 8259 compatible escaping.

This avoids byte-a-byte variations across builds or implementations.
Esto evita variaciones byte-a-byte entre compilaciones o implementaciones.

## RecordStore

Records are stored through a pluggable `RecordStore` interface:
Los registros se almacenan mediante una interfaz `RecordStore` intercambiable:

- `MemoryStore`: in-memory implementation for tests.
- `SqliteStore`: persistent storage for production.
- `FileStore`: JSON Lines for simple integrations.

The interface allows adding, listing, and recovering records by epoch or by `record_id`. The Merkle root published on-chain does not allow rebuilding lost records; preserving local storage is the operator's responsibility.
La interfaz permite agregar, listar y recuperar registros por epoch o por `record_id`. El root Merkle publicado on-chain no permite reconstruir los registros perdidos; conservar el almacenamiento local es responsabilidad del operador.

## Runtime configuration / Configuración runtime

The default configuration includes:
La configuración por defecto incluye:

| Parameter | Default value |
| --- | ---: |
| Epoch duration | `60_000 ms` |
| Max records per epoch | `1_000_000` |
| Merkle batch size | `1000` |
| Fee | `500 sats/kB` |
| Storage | `sqlite` |

Values must be validated before starting an epoch. In particular, duration and max records cannot be zero.
Los valores deben validarse antes de iniciar un epoch. En particular, la duración y el máximo de registros no pueden ser cero.

## Structure / Estructura

```text
src/
├── aria.zig          # entry point and re-exports
├── types.zig         # BRC-122 types and payloads
├── epoch.zig         # epoch lifecycle
├── record.zig        # AuditRecord creation and hashing
├── merkle.zig        # RFC 6962 tree and proofs
├── opreturn.zig      # OP_RETURN serialization and transactions
├── spv.zig           # SPV verification
└── zkml_bridge.zig   # optional zig-zkml integration
```

## Security / Seguridad

The full threat model, prevented attacks, and protocol limitations are documented in [SECURITY.md](SECURITY.md).

El threat model completo, los ataques prevenidos y las limitaciones del protocolo están documentados en [SECURITY.md](SECURITY.md).

In short, ARIA prevents retroactive commitment fabrication, tampering with sealed records, and epoch replay. It does not prevent an operator from registering false hashes during inference, running a model different from the committed one, or losing local records.
En resumen, ARIA previene la fabricación retroactiva de compromisos, la alteración de registros sellados y el replay de epochs. No previene que un operador registre hashes falsos durante la inferencia, ejecute un modelo distinto al comprometido o pierda los registros locales.

## License / Licencia

Refer to the license defined by the main repository and by each Zig dependency.
Consultar la licencia definida por el repositorio principal y por cada dependencia de Zig.

## Documentation / Documentación

Full documentation is available in [`docs/`](docs/):
La documentación completa está disponible en [`docs/`](docs/):

### English

- [Introduction](docs/en/README.md)
- [Architecture](docs/en/ARCHITECTURE.md)
- [API Reference](docs/en/API.md)
- [Getting Started](docs/en/GETTING_STARTED.md)
- [zkML Integration](docs/en/ZKML.md)
- [Contributing](docs/en/CONTRIBUTING.md)

### Español

- [Introducción](docs/es/README.md)
- [Arquitectura](docs/es/ARCHITECTURE.md)
- [Referencia de API](docs/es/API.md)
- [Guía de Inicio](docs/es/GETTING_STARTED.md)
- [Integración zkML](docs/es/ZKML.md)
- [Contribución](docs/es/CONTRIBUTING.md)
