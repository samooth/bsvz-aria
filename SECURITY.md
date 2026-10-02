# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |

## Reporting a Vulnerability

Please report security vulnerabilities by email to the maintainers. Do not open public issues for security vulnerabilities.

## Audit Records

- All audit records are hashed with SHA-256 before inclusion in the Merkle tree.
- Epoch roots are computed over the canonical JSON serialization of all records.
- Merkle proofs are RFC 6962 compliant: domain-separated leaf (`0x00`) and internal (`0x01`) hashes, with odd nodes promoted.

## Cryptographic Assumptions

- SHA-256 is used as the hash function throughout.
- The empty tree root is `SHA256("")`.
- Hash representations use the `sha256:<64hex>` prefix format.

## Dependencies

- `bsvz`: Bitcoin SV transaction library
- `zig-zkml`: Zero-knowledge ML proofs

## Known Limitations

- `spv.verifySpvProof` performs structural validation only (non-empty proof, multiple of 32 bytes). Full header-chain verification against `bsvz` primitives is a follow-up; do not rely on it for consensus-critical verification yet.
- `zkml_bridge.generateProof` returns a deterministic commitment placeholder, not a zero-knowledge proof.
- On-chain broadcast of `EPOCH_OPEN`/`EPOCH_CLOSE` transactions is not implemented; payloads are built locally via `opreturn.buildOpReturnPayload`.
