# Contributing

Helios is open-source under GPL 3.0. Contributions are welcome -- whether it is a bug fix, new feature, documentation improvement, or test coverage.

---

## Getting Started

1. Fork the repository on GitHub.
2. Clone your fork and set up the development environment (see [Building from Source](building-from-source.md)).
3. Create a feature branch from `dev`:

```bash
git checkout dev
git pull origin dev
git checkout -b feature/your-feature-name
```

4. Make your changes.
5. Run checks before committing:

```bash
make check
```

6. Commit with a descriptive message and push your branch.
7. Open a pull request targeting the `dev` branch.

---

## Branch Strategy

| Branch | Purpose |
|---|---|
| `main` | Stable releases. Only receives merges from `dev` when a release is cut. |
| `dev` | Active development. All feature branches are based on and merged into `dev`. |
| `feature/*` | Short-lived branches for individual features or fixes. |

Always base your work on `dev`, not `main`.

---

## Code Standards

### Analysis

All code must pass the Dart analyzer with zero warnings:

```bash
dart analyze --fatal-warnings lib/ test/ packages/dart_mavlink/
```

### Testing

- Write tests for all new models, services, and state notifiers.
- Tests live in `test/` and mirror the `lib/` directory structure.
- Run the full test suite before submitting:

```bash
flutter test
```

- For focused testing during development:

```bash
flutter test test/path/to/specific_test.dart
```

### Architecture

Helios follows a strict 4-layer pattern. See [Architecture](architecture.md) for details.

- **Presentation** (`lib/features/`) -- Flutter widgets. Never call services directly; read state from Riverpod providers.
- **State** (`lib/shared/providers/`) -- Riverpod providers and state notifiers.
- **Service** (`lib/core/`) -- Plain Dart classes with no Flutter dependency.
- **Data** (`lib/core/*/`, `packages/`) -- Raw bytes, file I/O, database access.

### Style

- Follow existing patterns in neighbouring code.
- Use `context.hc` theme tokens for colours -- never hardcode colour values.
- Support both light and dark mode in all new UI.
- Keep files under 500 lines where practical.
- Use `ConsumerWidget` or `ConsumerStatefulWidget` for Riverpod-connected widgets.

---

## Adding MAVLink Features

1. Check the message definition in `scripts/mavlink_xml/common.xml` or `ardupilotmega.xml`.
2. Add the message class to `packages/dart_mavlink/lib/src/messages.dart`.
3. Add the deserializer case to `packages/dart_mavlink/lib/src/mavlink_parser.dart`.
4. Add a frame builder if we need to send this message type.
5. Run `make gen-crc` if you added a new XML or suspect CRC issues.
6. The CRC extras are auto-generated -- never hand-edit `generated_crc_extras.dart`.

---

## Adding UI Features

1. Create the service or model in `lib/core/` or `lib/shared/models/`.
2. Wire it through Riverpod in `lib/shared/providers/`.
3. Build the UI in `lib/features/<tab>/`.
4. Follow existing widget patterns.

---

## Modifying VehicleState

The `VehicleState` model is the central telemetry data structure. When adding new fields:

1. Add the field with a default value to the `VehicleState` constructor.
2. Add it to the `copyWith()` method.
3. Add it to the `props` list (Equatable).
4. Handle the source message in `VehicleStateNotifier` (write to `_pending`, set `_dirty = true`).
5. State is batched at 30Hz -- never call `state =` directly; use the pending buffer.

---

## Documentation

When adding or changing user-facing features, update the relevant documentation in `website/docs/`. If the change is substantial (new feature, new view, new workflow), add a new documentation page and register it in the sidebar navigation in `website/js/docs.js`.

Technical changes to architecture, services, or internal APIs should be documented in the Development section of the docs.

---

## Pull Request Checklist

Before submitting a PR, verify:

- `make check` passes (analysis + tests).
- New functionality has test coverage.
- Documentation is updated for user-facing changes.
- No hardcoded colours, API keys, or secrets.
- Code follows the 4-layer architecture.
- Commit messages are descriptive.

---

## License

By contributing to Helios, you agree that your contributions will be licensed under the GPL 3.0 license.
