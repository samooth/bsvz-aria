# Contributing

## How to contribute

1. Fork and clone the repository.
2. Create a feature branch: `git checkout -b feature/my-change`.
3. Run `zig build test` before committing.
4. Open a PR with a clear description of the change.

## Code style

- Comments in English.
- Public documentation (`///`) on every exported type/function.
- Naming: `camelCase` functions, `PascalCase` types, `snake_case` files.
- Allocator-aware: all allocating functions receive `std.mem.Allocator`.
- Use specific error sets; never use `catch unreachable` in public code.
- Run `zig fmt` before committing.

## Tests

All tests must pass:

```bash
zig build test
```

With zkML enabled:

```bash
zig build test -Dwith_zkml=true
```

### Required tests

- Merkle RFC 6962: 1 leaf, 2 leaves, 4 leaves, 7 leaves (odd).
- JSON determinism: 100 iterations → same byte-a-byte JSON.
- Tamper detection: modify `prev_txid` in CLOSE → `PrevTxidMismatch`.
- Tamper detection: change 1 AuditRecord → Merkle proof failure.
- Empty epoch: open without records, close with `records_count=0`.
- SPV round-trip: fake CLOSE verified against fake header.
- zkML integration: `weightsMerkleRoot` matches EPOCH_OPEN.

## Project structure

```text
bsvz-aria/
├── build.zig
├── build.zig.zon
├── README.md
├── SECURITY.md
├── docs/
│   ├── README.md
│   ├── es/
│   │   ├── README.md
│   │   ├── ARCHITECTURE.md
│   │   ├── API.md
│   │   ├── GETTING_STARTED.md
│   │   ├── ZKML.md
│   │   └── CONTRIBUTING.md
│   └── en/
│       ├── README.md
│       ├── ARCHITECTURE.md
│       ├── API.md
│       ├── GETTING_STARTED.md
│       ├── ZKML.md
│       └── CONTRIBUTING.md
├── src/
│   ├── aria.zig
│   ├── types.zig
│   ├── epoch.zig
│   ├── record.zig
│   ├── merkle.zig
│   ├── opreturn.zig
│   ├── spv.zig
│   ├── verify.zig
│   ├── zkml_bridge.zig
│   ├── canonical.zig
│   ├── root.zig
│   ├── main.zig
│   └── examples/
│       ├── basic.zig
│       ├── with_zkml.zig
│       └── verify_spv.zig
```

## Reporting bugs

Open an issue with:
- Zig version.
- Steps to reproduce.
- Output of `zig build test`.

For security vulnerabilities, see [SECURITY.md](../SECURITY.md).

## License

Refer to the license defined by the main repository and by each Zig dependency.
