# Arquitectura

## Visión general

`bsvz-aria` implementa BRC-122 como una librería Zig 0.16+ que permite registrar de forma auditable el ciclo de vida de inferencias de IA mediante dos compromisos on-chain: `EPOCH_OPEN` y `EPOCH_CLOSE`. Los `AuditRecord` individuales se almacenan localmente y no se publican uno por uno en la cadena.

## Capas

```
┌─────────────────────────────────────────┐
│  Aplicación (main / examples / CLI)     │
├─────────────────────────────────────────┤
│  aria.zig (Aria struct + re-exports)    │
├─────────────────────────────────────────┤
│  epoch.zig, record.zig, opreturn.zig   │
│  merkle.zig, spv.zig, verify.zig       │
├─────────────────────────────────────────┤
│  types.zig (modelos de datos + errores) │
├─────────────────────────────────────────┤
│  canonical.zig (JSON determinista)      │
├─────────────────────────────────────────┤
│  bsvz (transacciones, crypto, SPV)      │
│  zig-wallet-toolbox (broadcast opcional)│
│  zig-zkml (integración opcional)        │
└─────────────────────────────────────────┘
```

## Flujo de datos

```text
EPOCH_OPEN (OP_RETURN)
        │
        │  inferencias durante el epoch
        ▼
AuditRecord x N (almacenamiento local)
        │
        ▼
EPOCH_CLOSE (OP_RETURN)
```

1. **EPOCH_OPEN**: se comprometen los `model_hashes` y el `state_hash` on-chain.
2. **AuditRecords**: se crean localmente por cada inferencia; cada uno se hashea y se agrega al árbol Merkle.
3. **EPOCH_CLOSE**: se publica el `records_merkle_root` y el `prev_txid` enlaza con el `EPOCH_OPEN`.

## Módulos

| Módulo | Responsabilidad |
|--------|-----------------|
| `types.zig` | Tipos de datos, error sets, helpers de hash, canonical JSON clone/deinit |
| `epoch.zig` | Ciclo de vida del epoch: `createEpoch`, `addRecordToEpoch`, `closeEpoch`, `validateClose`, `buildEpochProof` |
| `record.zig` | Creación y serialización de `AuditRecord` |
| `merkle.zig` | Árbol Merkle RFC 6962: `addLeaf`, `root`, `proof`, `verifyProof` |
| `opreturn.zig` | Serialización y parsing de payloads OP_RETURN |
| `spv.zig` | Verificación SPV del CLOSE contra headers |
| `verify.zig` | Verificación de apertura, cierre y pertenencia de records |
| `zkml_bridge.zig` | Integración opcional con `zig-zkml` |
| `canonical.zig` | Serializador JSON determinista |

## Estrategia de ownership

- Los structs que contienen `ArrayList` o `StringHashMap` exponen `deinit(allocator)` para liberar memoria.
- `createEpoch` allocatea con `allocator.create`; el caller debe liberar con `allocator.destroy(epoch)` tras `epoch.deinit()`.
- `addRecordToEpoch` devuelve el `AuditRecord` por valor; el ownership lo retiene `epoch.records`.
- Los strings duplicados (ej. `record_id`, `epoch_id`, `model_id`) se liberan en `deinit`.

## Configuración runtime

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

## Storage

`RecordStore` es una interfaz pluggable para almacenar `AuditRecord`:

- `MemoryStore`: implementación en memoria para tests.
- `SqliteStore`: almacenamiento persistente en SQLite para producción.
- `FileStore`: JSON Lines para integraciones simples.

## Serialización

- **JSON canónico**: orden de claves determinístico, sin whitespace fuera de strings, números sin ceros finales innecesarios, escaping RFC 8259.
- **OP_RETURN**: `OP_FALSE OP_RETURN PUSH4(0x41524941) PUSHDATA(<json_bytes>)`.

## Seguridad

Ver [SECURITY.md](../SECURITY.md) para el threat model completo.
