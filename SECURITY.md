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
- Merkle proofs are RFC 6962 compliant with leaf duplication for odd nodes.

## Cryptographic Assumptions

- SHA-256 is used as the hash function throughout.
- The empty tree root is `SHA256("")`.
- Hash representations use the `sha256:<64hex>` prefix format.

## Dependencies

- `bsvz`: Bitcoin SV transaction library
- `zig-wallet-toolbox`: Wallet and signing utilities (optional)
- `zig-zkml`: Zero-knowledge ML proofs (optional, enabled with `-Dwith_zkml`)
