# Helios GCS — Project Specification Index

**Version**: 1.0.0 | **Date**: 2026-03-24 | **Licence**: Apache 2.0

Helios GCS is an open-source ground control station for MAVLink-enabled UAVs, part of the Argus Platform.

---

## Specification Documents

| # | Document | Scope |
|---|----------|-------|
| 01 | [Vision & Architecture](01-vision-and-architecture.md) | System architecture, technology stack, platform support, NFRs |
| 02 | [Data Model & Schema](02-data-model-and-schema.md) | DuckDB schema, analytics templates, Parquet export format |
| 03 | [MAVLink Integration](03-mavlink-integration.md) | Transport layer, message parsing, commands, protocols |
| 04 | [UI/UX Specification](04-ui-ux-specification.md) | Design system, layouts, views, instruments, interactions |
| 05 | [State Management](05-state-management.md) | Riverpod providers, state models, update flows |
| 06 | [Service Interfaces](06-service-interfaces.md) | Typed Dart interfaces, error handling, logging |
| 07 | [Testing Strategy](07-testing-strategy.md) | Test pyramid, unit/widget/integration/performance tests, CI |
| 08 | [Security & Deployment](08-security-and-deployment.md) | Threat model, deployment, project structure, dependencies |
| 09 | [Development Phases](09-development-phases.md) | 5 phases, 80+ tasks, risk register |
| 10 | [Argus Integration & Gaps](10-argus-integration-and-gaps.md) | Argus sync, gap analysis, decisions made |

## Source Specification

- [helios-inital-spec.md](../../helios-inital-spec.md) — Original architecture & product specification

## Quick Facts

- **Tech Stack**: Flutter 3.x, Dart 3.x, Riverpod, DuckDB, MAVLink v2
- **Platforms**: Linux, macOS, Windows (P0), Android (P1), iOS (P2)
- **Autopilots**: ArduPilot (primary), PX4 (secondary)
- **Timeline**: 20 weeks, ~334 hours across 5 phases
- **Key Differentiator**: Embedded DuckDB analytics — every flight is a queryable database
