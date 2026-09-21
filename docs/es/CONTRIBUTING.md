# Contribución

## Cómo contribuir

1. Fork y clonar el repositorio.
2. Crear una rama feature: `git checkout -b feature/mi-cambio`.
3. Ejecutar `zig build test` antes de commitear.
4. Abrir un PR con descripción clara del cambio.

## Estilo de código

- Comentarios en inglés.
- Documentación pública (`///`) en cada tipo/función exportada.
- Naming: `camelCase` funciones, `PascalCase` tipos, `snake_case` archivos.
- Allocator-aware: todas las funciones que allocan reciben `std.mem.Allocator`.
- Usar error sets específicos; nunca `catch unreachable` en código público.
- Usar `zig fmt` antes de commitear.

## Tests

Todos los tests deben pasar:

```bash
zig build test
```

Con zkML habilitado:

```bash
zig build test -Dwith_zkml=true
```

### Tests obligatorios

- Merkle RFC 6962: 1 hoja, 2 hojas, 4 hojas, 7 hojas (impar).
- JSON determinismo: 100 iteraciones → mismo JSON byte-a-byte.
- Tamper detection: modificar `prev_txid` en CLOSE → `PrevTxidMismatch`.
- Tamper detection: cambiar 1 AuditRecord → falla Merkle proof.
- Empty epoch: open sin records, close con `records_count=0`.
- SPV round-trip: CLOSE fake verificado contra header fake.
- zkML integration: `weightsMerkleRoot` coincide con EPOCH_OPEN.

## Estructura del proyecto

```text
bsvz-aria/
├── build.zig
├── build.zig.zon
├── README.md
├── SECURITY.md
├── docs/
│   ├── README.md
│   ├── ARCHITECTURE.md
│   ├── API.md
│   ├── GETTING_STARTED.md
│   ├── ZKML.md
│   └── CONTRIBUTING.md
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

## Reportar bugs

Abrir un issue con:
- Versión de Zig.
- Pasos para reproducir.
- Output de `zig build test`.

Para vulnerabilidades de seguridad, ver [SECURITY.md](../SECURITY.md).

## Licencia

Consultar la licencia definida por el repositorio principal y por cada dependencia de Zig.
