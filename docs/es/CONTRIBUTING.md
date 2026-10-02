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

El ejemplo debe ejecutarse:

```bash
zig build example-basic
```

### Tests obligatorios

- Merkle RFC 6962: 1 hoja, 2 hojas, 3 hojas (impar, nodo promovido), árbol vacío.
- JSON determinismo: orden de declaración de campos y orden de inserción de claves de objeto producen bytes idénticos.
- Tamper detection: modificar un registro → fallo de raíz Merkle.
- Validación de registro: input/output vacíos, confidence fuera de `[0, 1]`.
- Ciclo de vida: añadir a un epoch cerrado falla; close encadena `prev_txid`.
- OP_RETURN round-trip: construir y analizar payload de `EPOCH_CLOSE`.
- Puente zkML: compromiso duplicado rechazado; prueba para modelo no comprometido falla.

## Estructura del proyecto

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

## Reportar bugs

Abrir un issue con:
- Versión de Zig.
- Pasos para reproducir.
- Output de `zig build test`.

Para vulnerabilidades de seguridad, ver [SECURITY.md](../SECURITY.md).

## Licencia

Este proyecto está licenciado bajo la **Licencia OPEN BSV**.
