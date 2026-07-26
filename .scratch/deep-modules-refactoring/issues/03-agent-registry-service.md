# 03 — Deep AgentRegistryService Module & List Sessions Simplification

**What to build:**
Create `AgentRegistryService` in `server/src/agent-registry-service.mts` encapsulating agent discovery, custom command resolution, multi-agent query concurrency, path normalization (`path.resolve(cwd).toLowerCase()`), and 12-second timeout protection. Simplify `list-sessions.mts` to a thin adapter.

**Blocked by:** 01 — Deep SessionManager Core Module & Process Pool

**Status:** ready-for-agent

- [ ] Create `AgentRegistryService` class with `listInstalledAgents()`, `queryAggregateSessions(cwd)`, `installAgent()`, `uninstallAgent()`
- [ ] Encapsulate concurrent temp-client querying, 12-second timeout race, and Windows path normalization
- [ ] Simplify `list-sessions.mts` and `list-models.mts` to call `agentRegistry` methods directly
- [ ] Write unit tests for `AgentRegistryService` aggregation and path normalization
