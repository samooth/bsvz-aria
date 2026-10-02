# Architecture

## Overview

`bsvz-aria` implements BRC-122 as a Zig 0.16 library that allows auditable recording of the AI inference lifecycle through two on-chain commitments: `EPOCH_OPEN` and `EPOCH_CLOSE`. Individual `AuditRecord`s are stored locally and are not published one by one on the chain.

## Layers

```
┌─────────────────────────────────────────┐
│  Application (main / examples / CLI)    │
├─────────────────────────────────────────┤
│  aria.zig (Aria struct: lifecycle)      │
├─────────────────────────────────────────┤
│  epoch.zig, record.zig, opreturn.zig    │
│  merkle.zig, spv.zig, verify.zig        │
│  zkml_bridge.zig                        │
├─────────────────────────────────────────┤
│  types.zig (data models + errors)       │
│  canonical.zig (deterministic JSON)     │
├─────────────────────────────────────────┤
│  bsvz (transactions, crypto, SPV)       │
│  zig-zkml (computational proofs)        │
└─────────────────────────────────────────┘
```

## Data flow

```text
EPOCH_OPEN (OP_RETURN)
        │
        │  inferences during the epoch
        ▼
AuditRecord x N (local storage, Merkle tree)
        │
        ▼
EPOCH_CLOSE (OP_RETURN, prev_txid links to previous close)
```

1. **EPOCH_OPEN**: `model_hashes` and `state_hash` are committed before inferences run; `timestamp` and a random `nonce` are filled in.
2. **AuditRecords**: created locally for each inference; each is canonically serialized, hashed, and added to the Merkle tree with sequence number.
3. **EPOCH_CLOSE**: `records_merkle_root` is published; `prev_txid` chains to the previous close (or the genesis hash), providing epoch linking.

## Modules

| Module | Responsibility |
|--------|-----------------|
| `types.zig` | Data types, error sets, hash helpers, JSON clone/deinit |
| `epoch.zig` | Epoch lifecycle: `createEpoch`, `addRecordToEpoch`, `closeEpoch`, `validateClose`, `buildEpochProof`, `EpochStore` index |
| `record.zig` | `AuditRecord` creation, hashing, and canonical serialization |
| `merkle.zig` | RFC 6962 Merkle tree with domain separation: `addLeaf`, `root`, `proof`, `verifyProof` |
| `opreturn.zig` | BRC-122 OP_RETURN payload (magic + varint + canonical JSON of `EPOCH_CLOSE`) |
| `spv.zig` | SPV client state and proof validation |
| `verify.zig` | Verification of open, close, record membership, and Merkle roots |
| `zkml_bridge.zig` | Model commitments and deterministic proof placeholders for `zig-zkml` |
| `canonical.zig` | Deterministic JSON serializer (sorted keys, no whitespace) |
| `aria.zig` | `Aria` facade: coordinates the lifecycle, the store, SPV state, and the zkML bridge |

## Ownership strategy

- The **caller** owns each epoch: `createEpoch`/`openEpoch` return `*Epoch`; the caller must call `epoch.deinit()` and then `allocator.destroy(epoch)`.
- `EpochStore` is a lookup index: it never frees epochs or records, only its own map keys.
- `Aria.addRecord` returns a borrowed `*AuditRecord` owned by `epoch.records`; valid until the next epoch mutation.
- `EPOCH_OPEN.system_id` is borrowed from the caller; `EPOCH_CLOSE.epoch_id` and `AuditRecord` string fields are owned and freed in `deinit`.
- Structs containing `ArrayList` or `StringHashMap` expose `deinit(allocator)`.

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

`Config.StoreType` declares the intended backing store (`memory`, `sqlite`, `file`). The in-memory implementation is provided by `EpochStore` plus the per-epoch record list; `sqlite` and `file` are reserved for future work.

## Serialization

- **Canonical JSON**: struct and object keys sorted lexicographically, no whitespace outside strings, RFC 8259 escaping, hashes as `"sha256:<hex>"`, non-finite floats rejected.
- **OP_RETURN**: `OP_FALSE OP_RETURN PUSH4(0x41524941) PUSHDATA(varint_len, json_bytes)` where the JSON is the canonical serialization of `EPOCH_CLOSE`.

## Security

See [SECURITY.md](../SECURITY.md) for the full threat model.
