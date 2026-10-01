# Contributing

Use macOS 14+ and a current Swift toolchain (Swift 5.9 or later). Runtime hosting requires Apple Silicon. Unit tests use temporary fixtures and do not download game files.

```sh
swift test
swift build
ESM_HOME="$PWD/.build/manual-test" .build/debug/EnshroudedManager
```

Always use an isolated `ESM_HOME` for development. Use disposable worlds and separate ports. Do not enable login startup from a development instance. `ESM_RESOURCES` can point to an isolated resource directory for fixture testing.

## Structure

- `Sources/EnshroudedCore`: runtime lifecycle, server configuration, monitoring, backups, schedules, and app replacement.
- `Sources/EnshroudedManager`: native interface, menu, setup, and automation coordination.
- `Runtime`: provisioning and clean shutdown inside the private Linux environment.
- `Tests/EnshroudedManagerTests`: native menu, editor, log and lifecycle regressions.
- `Tests/EnshroudedCoreTests`: preservation, schedules, workflows, parsing, and installation checks.
- `scripts`: packaging, signing, notarization, dependency checks and release-note rendering.

Keep changes focused and user messages short. Explain the behavior and verification in pull requests. Lifecycle, settings, backup, and update changes need relevant regression coverage.

Never commit world saves, server binaries, runtime images, logs, credentials, or signing material. Do not test against a hosted world. See [Releasing](docs/RELEASING.md) for distribution.

Run the shell/Python checks in `.github/workflows/ci.yml` as well as Swift tests before releasing. The packaging gate rejects external macOS libraries and binaries requiring a newer OS than advertised. See [Installation Dependencies](docs/INSTALLATION-DEPENDENCIES.md) for the distinction between end-user and build-machine requirements.
