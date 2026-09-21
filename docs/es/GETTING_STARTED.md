# Guía de Inicio

## Requisitos

- Zig 0.16 o superior
- Git

## Instalación

```bash
git clone https://github.com/samooth/bsvz-aria.git
cd bsvz-aria
zig build
```

## Dependencias

`bsvz-aria` depende de:

- `bsvz`: primitivas BSV (transacciones, script, SPV, crypto)
- `zig-wallet-toolbox`: wallet BRC-100 (opcional)
- `zig-zkml`: zkML (opcional, requiere `-Dwith_zkml=true`)

Las dependencias se resuelven automáticamente con `zig build`.

## Build

```bash
zig build
```

## Tests

```bash
zig build test
```

## Ejemplos

### Ejecutar ejemplo básico

```bash
zig build run --example basic_epoch
```

### Estructura de ejemplos

```text
src/examples/
├── basic.zig         # Flujo mínimo: init → openEpoch → addRecord → closeEpoch → verifyEpoch
├── with_zkml.zig     # Integración con zig-zkml (F0 weights attestation)
└── verify_spv.zig    # Verificación SPV de un EPOCH_CLOSE real
```

## Flujo mínimo de uso

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

    std.debug.print("epoch cerrado y verificado\n", .{});
}
```

## Próximos pasos

- Leer la [Referencia de API](API.md) para todos los tipos y funciones.
- Explorar [Integración zkML](ZKML.md) para pruebas computacionales.
- Leer [SECURITY.md](../SECURITY.md) para entender el threat model.
