# Development tests

Run `bash scripts/Test-Container.sh /absolute/path/to/fresh-output` to build, package and test inside the pinned local Docker image. The runner uses Linux arm64, PowerShell 7.6.8 and .NET 10.0.14; acquire its declared MCR image before running the offline checks.

The suite checks generated command consistency, package provenance, isolated module import (including literal file loading under a module root whose name is a wildcard pattern), typed runtime behavior, HTTP/TLS traffic, cancellation, pipeline privacy, Unicode and locale handling, and runs the homologation example against a loopback fixture. Inputs are synthetic and require no real API credentials. Windows and macOS require separate verification.

The bundled SDK and runtime bridge DLLs are required module dependencies. Their exact hashes and build inputs are documented in `module/Webmania/dependency.lock.json`; retain the accompanying licenses and nuspec. Updating a DLL requires regeneration and complete module verification.

Generated archives, logs and receipts belong in the output directory, outside the repository. Source or documentation cleanup requires a freshly built archive and a new checksum.

## Testes a partir da fonte

```sh
bash scripts/Test-Container.sh /caminho/absoluto/saida-nova
```

O script constrói, empacota e testa o módulo em uma imagem Docker local fixada, com entradas sintéticas e sem credenciais reais. Detalhes em [docs/TESTING.md](TESTING.md).
