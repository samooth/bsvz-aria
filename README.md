# bsvz-aria

`bsvz-aria` es una implementación en Zig 0.16+ del estándar BRC-122, **Auditable Real-time Inference Architecture**, para el ecosistema BSV.

ARIA permite registrar de forma auditable el ciclo de vida de inferencias de IA mediante dos compromisos on-chain:

1. `EPOCH_OPEN` compromete los modelos y el estado antes de ejecutar inferencias.
2. `EPOCH_CLOSE` sella el lote de registros mediante una raíz Merkle y lo enlaza con el `EPOCH_OPEN`.

Los `AuditRecord` individuales se almacenan localmente y no se publican uno por uno en la cadena.

## Qué garantiza ARIA

ARIA prueba:

- **Compromiso temporal:** los `model_hashes` y el `state_hash` se publican antes de realizar las inferencias.
- **Consistencia del lote:** todos los registros de un epoch están comprometidos por el `records_merkle_root` publicado en `EPOCH_CLOSE`.
- **Vinculación de epochs:** `EPOCH_CLOSE.prev_txid` enlaza criptográficamente el cierre con su apertura.
- **Detección de alteraciones:** un cambio en un registro, en el identificador del epoch o en el enlace al opening invalida la verificación.

ARIA **no prueba por sí sola la integridad computacional**. No demuestra que se haya ejecutado el modelo comprometido ni que el resultado sea computacionalmente correcto. Esa garantía corresponde a la integración opcional con [`zig-zkml`](https://github.com/samooth/zig-zkml).

La referencia canónica del protocolo es [`JuanmPalencia/aria-bsv`](https://github.com/JuanmPalencia/aria-bsv).

## Flujo de uso

```text
EPOCH_OPEN (OP_RETURN)
        |
        |  inferencias durante el epoch
        v
AuditRecord x N (almacenamiento local)
        |
        v
EPOCH_CLOSE (OP_RETURN)
```

El payload de las transacciones usa el formato:

```text
OP_FALSE OP_RETURN PUSH4(0x41524941) PUSHDATA(varint_len, json_bytes)
```

Donde `0x41524941` es la cadena ASCII `ARIA`. El JSON se serializa sin whitespace fuera de los strings y con un orden de claves determinístico.

## Instalación y build

Se requiere Zig 0.16 o superior y las dependencias configuradas en `build.zig.zon`:

- `bsvz`
- `zig-wallet-toolbox`
- `zig-zkml` (opcional)

Ejecutar los tests:

```bash
zig build test
```

Ejecutar el ejemplo básico:

```bash
zig build run --example basic_epoch
```

Habilitar la integración con zkML:

```bash
zig build test -Dwith_zkml=true
```

Sin `-Dwith_zkml=true`, `zkml_bridge` expone la interfaz correspondiente pero devuelve `error.ZkmlNotAvailable`.

## Ejemplo mínimo

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

La API y el comportamiento exacto de cada módulo están definidos en `DETAIL.md`.

## Integración con zkML

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

## Verificación

`verifyEpoch` obtiene y parsea las transacciones `EPOCH_OPEN` y `EPOCH_CLOSE`, comprueba sus enlaces y, opcionalmente, verifica el cierre mediante SPV:

```zig
const verified = try aria.verifyEpoch(allocator, epoch_open_txid, .{
    .header_source = header_source,
    .tx_fetcher = tx_fetcher,
});
```

`verifyRecord` valida el identificador del epoch, el modelo comprometido y la pertenencia del registro al Merkle root:

```zig
const valid = try aria.verifyRecord(
    allocator,
    &verified,
    &audit_record,
    merkle_proof,
);
```

Si no se proporciona una prueba Merkle, el verificador puede reconstruir el árbol a partir de los registros almacenados localmente.

## Merkle RFC 6962

El árbol utiliza separación de dominio:

- hoja: `SHA-256(0x00 || data)`
- nodo interno: `SHA-256(0x01 || left || right)`

Se admiten árboles con cualquier cantidad de hojas, incluidos los tamaños impares. El root de un árbol vacío es `SHA-256("")`.

## JSON canónico

La serialización usa un serializer propio para garantizar:

- orden determinístico de claves;
- ausencia de whitespace fuera de strings;
- números sin ceros finales innecesarios;
- escaping compatible con RFC 8259.

Esto evita variaciones byte-a-byte entre compilaciones o implementaciones.

## RecordStore

Los registros se almacenan mediante una interfaz `RecordStore` intercambiable:

- `MemoryStore`: implementación en memoria para tests.
- `SqliteStore`: almacenamiento persistente para producción.
- `FileStore`: JSON Lines para integraciones simples.

La interfaz permite agregar, listar y recuperar registros por epoch o por `record_id`. El root Merkle publicado on-chain no permite reconstruir los registros perdidos; conservar el almacenamiento local es responsabilidad del operador.

## Configuración runtime

La configuración por defecto incluye:

| Parámetro | Valor por defecto |
| --- | ---: |
| Duración de epoch | `60_000 ms` |
| Máximo de registros por epoch | `1_000_000` |
| Tamaño de lote Merkle | `1000` |
| Fee | `500 sats/kB` |
| Almacenamiento | `sqlite` |

Los valores deben validarse antes de iniciar un epoch. En particular, la duración y el máximo de registros no pueden ser cero.

## Estructura

```text
src/
├── aria.zig          # punto de entrada y re-exportaciones
├── types.zig         # tipos y payloads BRC-122
├── epoch.zig         # ciclo de vida del epoch
├── record.zig        # creación y hash de AuditRecord
├── merkle.zig        # árbol y pruebas RFC 6962
├── opreturn.zig      # serialización y transacciones OP_RETURN
├── spv.zig           # verificación SPV
└── zkml_bridge.zig   # integración opcional con zig-zkml
```

## Seguridad

El threat model completo, los ataques prevenidos y las limitaciones del protocolo están documentados en [SECURITY.md](SECURITY.md).

En resumen, ARIA previene la fabricación retroactiva de compromisos, la alteración de registros sellados y el replay de epochs. No previene que un operador registre hashes falsos durante la inferencia, ejecute un modelo distinto al comprometido o pierda los registros locales.

## Licencia

Consultar la licencia definida por el repositorio principal y por cada dependencia de Zig.
