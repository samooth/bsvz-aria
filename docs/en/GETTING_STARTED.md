# Getting Started

## Requirements

- Zig 0.16 or later
- Git

## Installation

```bash
git clone https://github.com/samooth/bsvz-aria.git
cd bsvz-aria
zig build --fetch
```

## Dependencies

`bsvz-aria` depends on:

- `bsvz`: BSV primitives (transactions, script, SPV, crypto)
- `zig-zkml`: zkML integration

Dependencies are resolved automatically with `zig build`.

## Build

```bash
zig build
```

## Tests

```bash
zig build test
```

## Examples

### Run the basic example

```bash
zig build example-basic
```

Example structure:

```text
src/examples/
└── basic.zig         # Minimal flow: init → openEpoch → addRecord → closeEpoch → verifyEpoch
```

## CLI

The `bsvz_aria` binary supports two commands:

```bash
zig build run -- version   # print the version
zig build run -- demo      # in-memory epoch lifecycle demo
```

## Minimal usage flow

```zig
const std = @import("std");
const bsvz_aria = @import("bsvz_aria");
const types = bsvz_aria.api.types;
const aria = bsvz_aria.api.aria;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const genesis = types.hashBytes("genesis");
    var app = try aria.Aria.init(allocator, .{}, genesis, io);
    defer app.deinit();

    const model_hash = types.hashBytes("model-bytes");
    const epoch = try app.openEpoch("ep_1700000000000_0001", "my-system", &[_]types.ModelHash{
        .{ .model_id = "my-model", .sha256 = model_hash },
    });
    defer {
        epoch.deinit();
        allocator.destroy(epoch);
    }

    _ = try app.addRecord(epoch, .{
        .model_id = "my-model",
        .input = "input-1",
        .output = "output-1",
        .confidence = 0.95,
        .latency_ms = 12,
    });

    const result = try app.closeEpoch(epoch);
    try app.verifyEpoch(epoch);

    std.debug.print("records={d}, merkle root={s}\n", .{
        result.records_count,
        types.hashToHex(result.records_merkle_root),
    });
}
```

Notes:

- `Aria.init` takes an `std.Io` (0.16 I/O interface) used for timestamps and randomness.
- The epoch id must parse as `ep_<timestamp_ms>_<sequence>` (e.g. `ep_1700000000000_0001`).
- At least one model hash is required; `openEpoch` rejects empty model sets.
- The caller owns the epoch: `epoch.deinit()` then `allocator.destroy(epoch)`.

## Next steps

- Read the [API Reference](API.md) for all types and functions.
- Explore [zkML Integration](ZKML.md) for computational proofs.
- Read [SECURITY.md](../SECURITY.md) to understand the threat model.
