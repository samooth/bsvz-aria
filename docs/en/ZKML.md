# zkML Integration

## Concept

`bsvz-aria` proves **temporal commitment and batch consistency**, but **does not** prove computational integrity. That guarantee is provided by the optional integration with `zig-zkml`.

ARIA and zkML are complementary layers:

- **ARIA**: seals when and under what commitment the batch was performed.
- **zkML**: proves the computational execution of the committed model.

## Enable integration

```bash
zig build test -Dwith_zkml=true
```

Without `-Dwith_zkml=true`, the `zkml_bridge` module exposes the corresponding interface but returns `error.ZkmlNotAvailable`.

## Basic usage

```zig
const zkml = @import("zig-zkml");

const weights_root = try aria.zkml_bridge.commitModel("qwen3-next", model_hash);

var epoch = try aria.Epoch.open(allocator, .{
    .system_id = "my-inference-service",
    .model_hashes = &.{
        .{ .model_id = "qwen3-next", .sha256 = weights_root },
    },
    .broadcast = false,
});

const zkml_proof = try zkml.prove(.{
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

## zkml_bridge API

```zig
pub const ZkMlBridge = struct {
    allocator: std.mem.Allocator,
    proof_buffer: std.ArrayList(u8),
    model_commitments: std.StringHashMap(Hash),
};

pub fn initZkMlBridge(allocator: std.mem.Allocator) ZkMlBridge;
pub fn deinit(self: *@This()) void;
pub fn commitModel(self: *@This(), model_id: []const u8, model_hash: Hash) !void;
pub fn generateProof(self: *@This(), record: *const AuditRecord) ![]u8;
```

## Epoch lifecycle with zkML

```text
1. Load model and obtain weights_root via kt_weights_merkle_root
2. Create EPOCH_OPEN committing the weights_root
3. For each inference:
   a. Execute model and obtain trace
   b. Generate zkML proof (prove)
   c. Create AuditRecord with zkml_proof in metadata
   d. Add to epoch
4. Close epoch (EPOCH_CLOSE with records_merkle_root)
```

## Limitations

- `zig-zkml` F0 provides `kt_weights_merkle_root` and `zkml_transcript_seed`.
- F2+ (gadgets, prover MoE) are in progress.
- ARIA does not validate the zkML proof automatically; the user must verify it separately.
