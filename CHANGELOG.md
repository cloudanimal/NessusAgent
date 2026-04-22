# Changelog

## 2026-04-14

- Fixed Tenable agent export group mapping for large groups in `Public/Export-TIOAgents.ps1`.
- Added pagination for scanner group member retrieval using `limit`/`offset`.
- Ensured the group-members lookup receives the configured `-Limit` value.
- Added regression coverage in `Tests/Export-TIOAgents.Tests.ps1` for agents appearing on later pages.
- Verified export output now correctly resolves an agent's group membership when the agent appears on a later pagination page.
