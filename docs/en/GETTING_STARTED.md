# Getting Started

## Requirements

- Zig 0.16 or later
- Git

## Installation

```bash
git clone https://github.com/samooth/bsvz-aria.git
cd bsvz-aria
zig build
```

## Dependencies

`bsvz-aria` depends on:

- `bsvz`: BSV primitives (transactions, script, SPV, crypto)
- `zig-wallet-toolbox`: BRC-100 wallet (optional)
- `zig-zkml`: zkML (optional, requires `-Dwith_zkml=true`)

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
zig build run --example basic_epoch
```

### Example structure

```text
src/examples/
├── basic.zig         # Minimal flow: init → openEpoch → addRecord → closeEpoch → verifyEpoch
├── with_zkml.zig     # zig-zkml integration (F0 weights attestation)
└── verify_spv.zig    # SPV verification of a real EPOCH_CLOSE
```

## Minimal usage flow

```zig
const std = @import("std");
const bsvz_aria = @import("bsvz_aria");
const types = bsvz_aria.api.types;

pub fn main() !void {
    const allocator = std.testing.allocator;

    const genesis = types.hashBytes("genesis");
    var aria = try bsvz_aria.api.aria.init(allocator, types.Config{}, genesis);
    defer aria.deinit();

    const epoch = try aria.openEpoch("ep_001", "my-system", &[_]types.ModelHash{});
    defer {
        epoch.deinit();
        allocator.destroy(epoch);
    }

    const rec = try aria.addRecord(epoch, .{
        .model_id = "model-x",
        .input = "input-1",
        .output = "output-1",
        .confidence = 0.95,
        .latency_ms = 12,
    });
    _ = rec;

    try aria.closeEpoch(epoch);
    try aria.verifyEpoch(epoch);

    std.debug.print("epoch closed and verified\n", .{});
}
```

## Next steps

- Read the [API Reference](API.md) for all types and functions.
- Explore [zkML Integration](ZKML.md) for computational proofs.
- Read [SECURITY.md](../SECURITY.md) to understand the threat model.
