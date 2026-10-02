# Integración zkML

## Concepto

`bsvz-aria` prueba **compromiso temporal y consistencia de lote**, pero **no** prueba la integridad computacional. Esa garantía la provee la integración con `zig-zkml`.

ARIA y zkML son capas complementarias:

- **ARIA**: sella cuándo y bajo qué compromiso se realizó el lote.
- **zkML**: prueba la ejecución computacional del modelo comprometido.

## Uso básico

```zig
const std = @import("std");
const bsvz_aria = @import("bsvz-aria");
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

## API de zkml_bridge

```zig
pub const ZkMlBridge = struct {
    pub fn init(allocator: std.mem.Allocator) ZkMlBridge;
    pub fn deinit(self: *@This()) void;
    pub fn commitModel(self: *@This(), model_id: []const u8, model_hash: types.Hash) !void;
    pub fn generateProof(self: *@This(), record: *const types.AuditRecord) ![]u8;
};
```

- `commitModel` registra el compromiso SHA-256 de los pesos para un `model_id` (los duplicados se rechazan).
- `generateProof` devuelve un marcador determinista de 32 bytes: `SHA-256(SHA-256(record_json) || model_commitment)`. Falla con `EpochError.InvalidModelId` si el modelo del registro no tiene compromiso registrado.

## Ciclo de vida del epoch con zkML

```text
1. Cargar el modelo y obtener weights_root
2. Registrar el compromiso vía zkml.commitModel
3. Crear EPOCH_OPEN comprometiendo weights_root
4. Por cada inferencia:
   a. Ejecutar el modelo y obtener el trace
   b. Generar la prueba zkML (prover de zig-zkml)
   c. Crear AuditRecord con zkml_proof en metadata
   d. Añadir al epoch
5. Cerrar el epoch (EPOCH_CLOSE con records_merkle_root)
```

## Limitaciones

- `generateProof` es un marcador de compromiso determinista, no una prueba de conocimiento cero real. La integración completa del prover de `zig-zkml` (F0 `kt_weights_merkle_root`, `zkml_transcript_seed`; F2+ gadgets y prover MoE) está en progreso upstream.
- ARIA no valida la prueba zkML automáticamente; el usuario debe verificarla por separado.
