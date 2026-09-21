# Contexto

Estoy construyendo `bsvz-aria`, una implementación en Zig del estándar BRC-122 
(Auditable Real-time Inference Architecture) para el ecosistema BSV.

## Stack existente del que dependo

- `bsvz` (github.com/samooth/bsvz): librería fundacional BSV en Zig. Provee:
  - `bsvz.transaction`: builder de transacciones, BEEF V1/V2/Atomic, sighash
  - `bsvz.transaction.beef`: parse/serialize BEEF
  - `bsvz.script`: engine, templates (P2PKH, OP_RETURN, PushDrop)
  - `bsvz.spv`: MerklePath, BRC-9 verify, BRC-61 compound paths, BRC-74 BUMP
  - `bsvz.crypto`: SHA-256, secp256k1, Schnorr
  - `bsvz.primitives`: hex, varint, chainhash (display-order)

- `zig-zkml` (github.com/samooth/zig-zkml): zkML sobre ktransformers-zig. 
  Provee F0 weights attestation:
  - `kt_weights_merkle_root`: raíz Blake3+Merkle de los pesos al cargar (ya funciona)
  - `zkml_transcript_seed`: sampling determinístico (ya funciona)
  - F2+ (gadgets, prover MoE) están en progreso

- `zig-ai` (github.com/samooth/zig-ai, en desarrollo): inferencia IA nativa en Zig.

- `zig-wallet-toolbox` (github.com/samooth/zig-wallet-toolbox): wallet BRC-100 
  con storage pluggable (SQLite/remote/memory) y auth BRC-104.

## Estándar BRC-122

BRC-122 especifica ARIA: protocolo de capa de aplicación BSV para responsabilidad 
criptográfica de inferencia de IA en producción. Usa un esquema de pre-compromiso:

1. **EPOCH_OPEN** (OP_RETURN): compromete model_hashes + state_hash ANTES de inferir
2. **AuditRecord**: registro local de cada inferencia (input_hash, output_hash, 
   model_id, confidence, latency_ms, metadata). NO va on-chain individualmente.
3. **EPOCH_CLOSE** (OP_RETURN): sella el epoch con records_merkle_root (RFC 6962) 
   + prev_txid apuntando al OPEN

Formato OP_RETURN: `OP_FALSE OP_RETURN PUSH4(0x41524941) PUSHDATA(<json_bytes>)`
- 0x41524941 = "ARIA" en ASCII
- JSON sin whitespace fuera de strings
- Árbol Merkle RFC 6962: leaf=SHA-256(0x00||data), internal=SHA-256(0x01||l||r)

Referencia Python: github.com/JuanmPalencia/aria-bsv

# Tu tarea

Crear la librería `bsvz-aria` en Zig 0.16+ que implemente BRC-122 de forma completa 
y de producción. Debe seguir el estilo de `bsvz` (estructura de módulos, naming 
snake_case para archivos, CamelCase para tipos, allocator-aware, error sets Zig-nativos).

## Estructura de módulos a generar


bsvz-aria/
├── build.zig # Zig build con tests + ejemplo mínimo
├── build.zig.zon # dependencias: bsvz, zig-zkml (opcionales)
├── README.md # uso, ejemplos, threat model
├── SECURITY.md # qué prueba, qué NO prueba (ver BRC-122 §"What a certificate proves")
├── src/
│ ├── aria.zig # módulo raíz que re-exporta todo
│ ├── types.zig # Epoch, AuditRecord, EPOCH_OPEN, EPOCH_CLOSE structs
│ ├── epoch.zig # open()/close()/verify() de epochs
│ ├── record.zig # AuditRecord creation + hash
│ ├── merkle.zig # RFC 6962 Merkle tree (con separación 0x00/0x01)
│ ├── opreturn.zig # serialización OP_RETURN con PUSH4(0x41524941)
│ ├── spv.zig # verificación SPV del CLOSE contra headers
│ └── zkml_bridge.zig # integración opcional: weights_root desde zig-zkml F0
├── examples/
│ ├── basic_epoch.zig # epoch simple con 3 records fake
│ ├── with_zkml.zig # epoch usando kt_weights_merkle_root de F0
│ └── verify_spv.zig # verificación SPV de un CLOSE real
└── tests/
├── merkle_test.zig # test vectors RFC 6962
├── epoch_test.zig # open→records→close→verify happy path
├── tamper_test.zig # detección de CLOSE con prev_txid alterado
└── json_test.zig # estabilidad byte-a-byte del JSON canónico



## API principal a implementar

```zig
const aria = @import("bsvz-aria");

// === Epoch lifecycle ===
var epoch = try aria.Epoch.open(allocator, .{
    .system_id = "my-inference-service",
    .model_hashes = .{
        .{ .id = "qwen3-next", .sha256 = "abc..." },
        .{ .id = "embeddings-v2", .sha256 = "def..." },
    },
    .state_hash = sha256_of_config,
    .wallet = &wallet, // zig-wallet-toolbox Wallet
});

// Añadir records durante la ejecución
try epoch.addRecord(.{
    .model_id = "qwen3-next",
    .input = input_bytes,  // se hashea localmente
    .output = output_bytes, // se hashea localmente
    .confidence = 0.95,
    .latency_ms = 47,
    .metadata = .{ .decision_class = "triage_priority_1" },
});

// Integración opcional con zig-zkml (F0)
const weights_root = try aria.zkml_bridge.weightsMerkleRoot(model);
// ...usar como model_hashes entry

// Cerrar epoch (emite EPOCH_CLOSE on-chain)
const close_result = try epoch.close(.{
    .wallet = &wallet,
    .broadcast = true,
});
// close_result contiene: txid, records_count, records_merkle_root

// === Verificación ===
const verified = try aria.verifyEpoch(allocator, .{
    .open_txid = "abc...",
    .header_source = my_header_source, // implementa aria.HeaderSource
});
// Retorna error si TAMPERED

const record_valid = try aria.verifyRecord(allocator, .{
    .epoch = verified,
    .record = the_audit_record,
    .merkle_proof = proof_from_stored_records,
});

Decisiones de diseño que debés tomar y documentar
JSON canónico: ¿usar std.json.stringify con opciones determinísticas, o escribir serializer propio que garantice orden de keys y sin whitespace? El estándar BRC-220 usa codificación binaria propia; ARIA permite JSON pero exige estabilidad. Recomendación: serializer propio.
Almacenamiento de AuditRecords: ¿en memoria con flush a archivo/SQLite, o siempre en disco? Recomendación: trait RecordStore pluggable con implementación memory (testing) y sqlite (producción), similar a WalletStorageManager de zig-wallet-toolbox.
HeaderSource para SPV: interfaz que provee block headers por height. Recomendación: trait que pueda implementarse con go-chaintracks, WhatsOnChain, o header local de Teranode.
zkml_bridge.zig: ¿hard-dependency o optional? Recomendación: optional via build flag -Dwith_zkml=true. Sin flag, el módulo es un stub que expone la interfaz weightsMerkleRoot pero el usuario la provee manualmente.
Thread safety: epochs con muchos records concurrentes. Recomendación: addRecord usa mutex interno; close es atómico.
Tests obligatorios
Merkle RFC 6962: test vectors conocidos (1 hoja, 2 hojas, 4 hojas, 7 hojas — impar).
JSON determinismo: 100 iteraciones del mismo epoch → mismo JSON byte-a-byte.
Tamper detection: modificar 1 bit de prev_txid en CLOSE → verify retorna error PrevTxidMismatch.
Tamper detection: cambiar 1 AuditRecord → Merkle proof falla.
Empty epoch: open sin records, close con records_count=0.
SPV round-trip: construir CLOSE fake con txid válido, verificar contra header fake.
Deliverables
Código Zig compilable con zig build --summary all test (todos los tests pasan, sin memory leaks).
README.md con:
Qué es ARIA y qué problema resuelve
Qué prueba (compromiso temporal + integridad de lote) y qué NO prueba (integridad computacional — eso es zkML)
Ejemplo mínimo completo
Integración con zig-zkml para pruebas computacionales
SECURITY.md explicando: threat model, limitaciones, qué ataques NO previene.
Ejemplo end-to-end que corra con zig build run --example basic_epoch.
Estilo
Comentarios en inglés (consistencia con bsvz).
Documentación pública en cada tipo/función exportada.
Error sets específicos: EpochError{ InvalidModelId, MerkleMismatch, PrevTxidMismatch, SpvVerificationFailed, JsonSerializationFailed }.
Naming: camelCase funciones, PascalCase tipos, snake_case archivos.
Allocator-aware: todas las funciones que allocan reciben std.mem.Allocator.

