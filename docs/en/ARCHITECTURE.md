# Architecture

## Overview

`bsvz-aria` implements BRC-122 as a Zig 0.16+ library that allows auditable recording of the AI inference lifecycle through two on-chain commitments: `EPOCH_OPEN` and `EPOCH_CLOSE`. Individual `AuditRecord`s are stored locally and are not published one by one on the chain.

## Layers

```
┌─────────────────────────────────────────┐
│  Application (main / examples / CLI)    │
├─────────────────────────────────────────┤
│  aria.zig (Aria struct + re-exports)    │
├─────────────────────────────────────────┤
│  epoch.zig, record.zig, opreturn.zig   │
│  merkle.zig, spv.zig, verify.zig       │
├─────────────────────────────────────────┤
│  types.zig (data models + errors)       │
├─────────────────────────────────────────┤
│  canonical.zig (deterministic JSON)     │
├─────────────────────────────────────────┤
│  bsvz (transactions, crypto, SPV)       │
│  zig-wallet-toolbox (optional broadcast)│
│  zig-zkml (optional integration)        │
└─────────────────────────────────────────┘
```

## Data flow

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

1. **EPOCH_OPEN**: `model_hashes` and `state_hash` are committed on-chain.
2. **AuditRecords**: created locally for each inference; each is hashed and added to the Merkle tree.
3. **EPOCH_CLOSE**: `records_merkle_root` is published and `prev_txid` links back to `EPOCH_OPEN`.

## Modules

| Module | Responsibility |
|--------|-----------------|
| `types.zig` | Data types, error sets, hash helpers, canonical JSON clone/deinit |
| `epoch.zig` | Epoch lifecycle: `createEpoch`, `addRecordToEpoch`, `closeEpoch`, `validateClose`, `buildEpochProof` |
| `record.zig` | `AuditRecord` creation and serialization |
| `merkle.zig` | RFC 6962 Merkle tree: `addLeaf`, `root`, `proof`, `verifyProof` |
| `opreturn.zig` | OP_RETURN payload serialization and parsing |
| `spv.zig` | SPV verification of CLOSE against headers |
| `verify.zig` | Verification of open, close, and record membership |
| `zkml_bridge.zig` | Optional integration with `zig-zkml` |
| `canonical.zig` | Deterministic JSON serializer |

## Ownership strategy

- Structs containing `ArrayList` or `StringHashMap` expose `deinit(allocator)` to free memory.
- `createEpoch` allocates with `allocator.create`; the caller must free it with `allocator.destroy(epoch)` after `epoch.deinit()`.
- `addRecordToEpoch` returns the `AuditRecord` by value; ownership stays in `epoch.records`.
- Duplicated strings (e.g. `record_id`, `epoch_id`, `model_id`) are freed in `deinit`.

## Runtime configuration

```zig
const Config = struct {
    default_epoch_duration_ms: u64 = 60_000,
    max_records_per_epoch: u32 = 1_000_000,
    merkle_batch_size: usize = 1000,
    default_fee_sats_per_kb: u64 = 500,
    default_store: StoreType = .memory,
};
```

All values are validated before starting an epoch via `Config.validate()`.

## Storage

`RecordStore` is a pluggable interface for storing `AuditRecord`s:

- `MemoryStore`: in-memory implementation for tests.
- `SqliteStore`: persistent SQLite storage for production.
- `FileStore`: JSON Lines for simple integrations.

## Serialization

- **Canonical JSON**: deterministic key order, no whitespace outside strings, no unnecessary trailing zeros, RFC 8259 escaping.
- **OP_RETURN**: `OP_FALSE OP_RETURN PUSH4(0x41524941) PUSHDATA(<json_bytes>)`.

## Security

See [SECURITY.md](../SECURITY.md) for the full threat model.
