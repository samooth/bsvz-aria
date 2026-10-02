# Guía de Inicio

## Requisitos

- Zig 0.16 o superior
- Git

## Instalación

```bash
git clone https://github.com/samooth/bsvz-aria.git
cd bsvz-aria
zig build --fetch
```

## Dependencias

`bsvz-aria` depende de:

- `bsvz`: primitivas BSV (transacciones, script, SPV, criptografía)
- `zig-zkml`: integración zkML

Las dependencias se resuelven automáticamente con `zig build`.

## Compilar

```bash
zig build
```

## Tests

```bash
zig build test
```

## Ejemplos

### Ejecutar el ejemplo básico

```bash
zig build example-basic
```

Estructura de ejemplos:

```text
src/examples/
└── basic.zig         # Flujo mínimo: init → openEpoch → addRecord → closeEpoch → verifyEpoch
```

## CLI

El binario `bsvz_aria` soporta dos comandos:

```bash
zig build run -- version   # imprime la versión
zig build run -- demo      # demo del ciclo de vida de un epoch en memoria
```

## Flujo de uso mínimo

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

Notas:

- `Aria.init` recibe un `std.Io` (interfaz de E/S de 0.16) usado para timestamps y aleatoriedad.
- El id del epoch debe analizarse como `ep_<timestamp_ms>_<sequence>` (ej. `ep_1700000000000_0001`).
- Se requiere al menos un hash de modelo; `openEpoch` rechaza conjuntos vacíos.
- El llamador es dueño del epoch: `epoch.deinit()` y luego `allocator.destroy(epoch)`.

## Próximos pasos

- Lee la [Referencia de API](API.md) para todos los tipos y funciones.
- Explora la [Integración zkML](ZKML.md) para pruebas computacionales.
- Lee [SECURITY.md](../SECURITY.md) para entender el modelo de amenazas.
