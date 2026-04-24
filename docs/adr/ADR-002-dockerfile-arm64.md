# ADR-002: goreleaser handles multi-arch builds

## Status: Accepted

## Decision
Dockerfile.arm64 is not added per-service.
All services use goreleaser for multi-arch builds
including linux/arm64 natively.

## Evidence
- ingestion: .goreleaser/connect.yaml → goarch: [amd64, arm64]
- realtime: .goreleaser.yml → arm64v8 platform
- analytics: Makefile → vmutils-linux-arm64
- billing: .goreleaser.yml present
- search/notifications: goreleaser confirmed

## Consequences
- CI/CD uses goreleaser for image builds ✅
- No per-service Dockerfile.arm64 needed ✅
