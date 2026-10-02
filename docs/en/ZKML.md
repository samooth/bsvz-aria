# zkML Integration

## Concept

`bsvz-aria` proves **temporal commitment and batch consistency**, but **does not** prove computational integrity. That guarantee is provided by the integration with `zig-zkml`.

ARIA and zkML are complementary layers:

- **ARIA**: seals when and under what commitment the batch was performed.
- **zkML**: proves the computational execution of the committed model.

## Basic usage

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

    const weights_root = types.hashBytes("model-weights");
    try app.zkml.commitModel("qwen3-next", weights_root);

    const epoch = try app.openEpoch("ep_1700000000000_0001", "my-inference-service", &[_]types.ModelHash{
        .{ .model_id = "qwen3-next", .sha256 = weights_root },
    });
    defer {
        epoch.deinit();
        allocator.destroy(epoch);
    }

    const rec = try app.addRecord(epoch, .{
        .model_id = "qwen3-next",
        .input = input,
        .output = inference_result.output,
        .metadata = .{
            .custom = .{ .zkml_proof = .{ .bytes = zkml_proof } },
        },
    });

    const result = try app.closeEpoch(epoch);
    try app.verifyEpoch(epoch);
}
```

## zkml_bridge API

```zig
pub const ZkMlBridge = struct {
    pub fn init(allocator: std.mem.Allocator) ZkMlBridge;
    pub fn deinit(self: *@This()) void;
    pub fn commitModel(self: *@This(), model_id: []const u8, model_hash: types.Hash) !void;
    pub fn generateProof(self: *@This(), record: *const types.AuditRecord) ![]u8;
};
```

- `commitModel` registers the SHA-256 weights commitment for a `model_id` (duplicates are rejected).
- `generateProof` returns a 32-byte deterministic placeholder: `SHA-256(SHA-256(record_json) || model_commitment)`. It fails with `EpochError.InvalidModelId` if the record's model has no registered commitment.

## Epoch lifecycle with zkML

```text
1. Load model and obtain weights_root
2. Register the commitment via zkml.commitModel
3. Create EPOCH_OPEN committing the weights_root
4. For each inference:
   a. Execute model and obtain trace
   b. Generate zkML proof (zig-zkml prover)
   c. Create AuditRecord with zkml_proof in metadata
   d. Add to epoch
5. Close epoch (EPOCH_CLOSE with records_merkle_root)
```

## Limitations

- `generateProof` is a deterministic commitment placeholder, not a real zero-knowledge proof. Full `zig-zkml` prover integration (F0 `kt_weights_merkle_root`, `zkml_transcript_seed`; F2+ gadgets and prover MoE) is in progress upstream.
- ARIA does not validate the zkML proof automatically; the user must verify it separately.
