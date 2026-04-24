# ADR-001: Linkerd mTLS as NetworkPolicy substitute

## Status: Accepted

## Decision
NetworkPolicy manifests are not added per-service.
Linkerd mTLS provides stronger L7 mutual authentication
between all services. Gatekeeper enforces admission policy.
vCluster provides namespace isolation.

## Consequences
- All services must have linkerd.io/inject: enabled ✅
- Gatekeeper ConstraintTemplates enforce traffic policy ✅
