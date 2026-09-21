# Integración zkML

## Concepto

`bsvz-aria` prueba **compromiso temporal y consistencia de lote**, pero **no** prueba integridad computacional. Esa garantía la provee la integración opcional con `zig-zkml`.

ARIA y zkML son capas complementarias:

- **ARIA**: sella cuándo y bajo qué compromiso se realizó el lote.
- **zkML**: demuestra la ejecución computacional del modelo comprometido.

## Habilitar la integración

```bash
zig build test -Dwith_zkml=true
```

Sin `-Dwith_zkml=true`, el módulo `zkml_bridge` expone la interfaz correspondiente pero devuelve `error.ZkmlNotAvailable`.

## Uso básico

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

## API de zkml_bridge

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

## Ciclo de vida de un epoch con zkML

```text
1. Cargar modelo y obtener weights_root via kt_weights_merkle_root
2. Crear EPOCH_OPEN comprometiendo el weights_root
3. Por cada inferencia:
   a. Ejecutar modelo y obtener trace
   b. Generar prueba zkML (prove)
   c. Crear AuditRecord con zkml_proof en metadata
   d. Agregar al epoch
4. Cerrar epoch (EPOCH_CLOSE con records_merkle_root)
```

## Limitaciones

- `zig-zkml` F0 provee `kt_weights_merkle_root` y `zkml_transcript_seed`.
- F2+ (gadgets, prover MoE) están en progreso.
- ARIA no valida la prueba zkML automáticamente; el usuario debe verificarla por separado.
