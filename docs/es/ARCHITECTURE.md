# Arquitectura

## Resumen

`bsvz-aria` implementa BRC-122 como una librería Zig 0.16 que permite registro auditable del ciclo de vida de inferencia de IA mediante dos compromisos on-chain: `EPOCH_OPEN` y `EPOCH_CLOSE`. Los `AuditRecord` individuales se almacenan localmente y no se publican uno por uno en la cadena.

## Capas

```
┌─────────────────────────────────────────┐
│  Aplicación (main / ejemplos / CLI)     │
├─────────────────────────────────────────┤
│  aria.zig (struct Aria: ciclo de vida)  │
├─────────────────────────────────────────┤
│  epoch.zig, record.zig, opreturn.zig    │
│  merkle.zig, spv.zig, verify.zig        │
│  zkml_bridge.zig                        │
├─────────────────────────────────────────┤
│  types.zig (modelos de datos + errores) │
│  canonical.zig (JSON determinista)      │
├─────────────────────────────────────────┤
│  bsvz (transacciones, cripto, SPV)      │
│  zig-zkml (pruebas computacionales)     │
└─────────────────────────────────────────┘
```

## Flujo de datos

```text
EPOCH_OPEN (OP_RETURN)
        │
        │  inferencias durante el epoch
        ▼
AuditRecord x N (almacenamiento local, árbol Merkle)
        │
        ▼
EPOCH_CLOSE (OP_RETURN, prev_txid enlaza al cierre anterior)
```

1. **EPOCH_OPEN**: `model_hashes` y `state_hash` se comprometen antes de ejecutar las inferencias; `timestamp` y un `nonce` aleatorio se rellenan.
2. **AuditRecords**: creados localmente por cada inferencia; cada uno se serializa canónicamente, se hashea y se añade al árbol Merkle con número de secuencia.
3. **EPOCH_CLOSE**: se publica `records_merkle_root`; `prev_txid` encadena con el cierre anterior (o el hash de génesis), proporcionando vinculación de epochs.

## Módulos

| Módulo | Responsabilidad |
|--------|-----------------|
| `types.zig` | Tipos de datos, conjuntos de errores, ayudas de hash, clone/deinit de JSON |
| `epoch.zig` | Ciclo de vida del epoch: `createEpoch`, `addRecordToEpoch`, `closeEpoch`, `validateClose`, `buildEpochProof`, índice `EpochStore` |
| `record.zig` | Creación, hash y serialización canónica de `AuditRecord` |
| `merkle.zig` | Árbol Merkle RFC 6962 con separación de dominio: `addLeaf`, `root`, `proof`, `verifyProof` |
| `opreturn.zig` | Payload OP_RETURN BRC-122 (mágica + varint + JSON canónico de `EPOCH_CLOSE`) |
| `spv.zig` | Estado del cliente SPV y validación de pruebas |
| `verify.zig` | Verificación de apertura, cierre, pertenencia de registros y raíces Merkle |
| `zkml_bridge.zig` | Compromisos de modelo y marcadores de prueba deterministas para `zig-zkml` |
| `canonical.zig` | Serializador JSON determinista (claves ordenadas, sin whitespace) |
| `aria.zig` | Fachada `Aria`: coordina el ciclo de vida, el store, el estado SPV y el puente zkML |

## Estrategia de propiedad

- El **llamador** es dueño de cada epoch: `createEpoch`/`openEpoch` devuelven `*Epoch`; el llamador debe invocar `epoch.deinit()` y luego `allocator.destroy(epoch)`.
- `EpochStore` es un índice de consulta: nunca libera epochs ni registros, solo sus propias claves de mapa.
- `Aria.addRecord` devuelve un `*AuditRecord` prestado, propiedad de `epoch.records`; válido hasta la siguiente mutación del epoch.
- `EPOCH_OPEN.system_id` se toma prestado del llamador; `EPOCH_CLOSE.epoch_id` y los campos string de `AuditRecord` son propios y se liberan en `deinit`.
- Los structs que contienen `ArrayList` o `StringHashMap` exponen `deinit(allocator)`.

## Configuración en tiempo de ejecución

```zig
const Config = struct {
    default_epoch_duration_ms: u64 = 60_000,
    max_records_per_epoch: u32 = 1_000_000,
    merkle_batch_size: usize = 1000,
    default_fee_sats_per_kb: u64 = 500,
    default_store: StoreType = .memory,
};
```

Todos los valores se validan antes de iniciar un epoch mediante `Config.validate()`.

## Almacenamiento

`Config.StoreType` declara el almacenamiento previsto (`memory`, `sqlite`, `file`). La implementación en memoria la proporcionan `EpochStore` más la lista de registros por epoch; `sqlite` y `file` están reservados para trabajo futuro.

## Serialización

- **JSON canónico**: claves de struct y objeto ordenadas lexicográficamente, sin whitespace fuera de strings, escaping RFC 8259, hashes como `"sha256:<hex>"`, floats no finitos rechazados.
- **OP_RETURN**: `OP_FALSE OP_RETURN PUSH4(0x41524941) PUSHDATA(varint_len, json_bytes)` donde el JSON es la serialización canónica de `EPOCH_CLOSE`.

## Seguridad

Ver [SECURITY.md](../SECURITY.md) para el modelo de amenazas completo.
