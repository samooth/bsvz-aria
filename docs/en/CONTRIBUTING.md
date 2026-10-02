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

The example must run:

```bash
zig build example-basic
```

### Required tests

- Merkle RFC 6962: 1 leaf, 2 leaves, 3 leaves (odd, promoted node), empty tree.
- JSON determinism: shuffled struct field declaration order and object key insertion order produce identical bytes.
- Tamper detection: modify a record → Merkle root mismatch.
- Record validation: empty input/output, confidence out of `[0, 1]`.
- Epoch lifecycle: add to closed epoch fails; close chains `prev_txid`.
- OP_RETURN round-trip: build and parse `EPOCH_CLOSE` payload.
- zkML bridge: duplicate commitment rejected; proof for uncommitted model fails.

## Project structure

```text
bsvz-aria/
├── build.zig
├── build.zig.zon
├── README.md
├── SECURITY.md
├── LICENSE
├── .github/workflows/ci.yml
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
└── src/
    ├── aria.zig
    ├── types.zig
    ├── epoch.zig
    ├── record.zig
    ├── merkle.zig
    ├── opreturn.zig
    ├── spv.zig
    ├── verify.zig
    ├── zkml_bridge.zig
    ├── canonical.zig
    ├── root.zig
    ├── main.zig
    └── examples/
        └── basic.zig
```

## Reporting bugs

Open an issue with:
- Zig version.
- Steps to reproduce.
- Output of `zig build test`.

For security vulnerabilities, see [SECURITY.md](../SECURITY.md).

## License

This project is licensed under the **OPEN BSV License**.
