# Restore-NessusAgent

PowerShell module and runbook script for checking, repairing, reinstalling, and relinking the Tenable Nessus Agent.

## Configure it

Use one of these approaches:

1. Set environment variables before running:
   - `REPAIR_NESSUS_AGENT_KEY`
   - `REPAIR_NESSUS_AGENT_CUSTOMER_UUID`
   - `REPAIR_NESSUS_AGENT_SERVER`
   - `REPAIR_NESSUS_AGENT_WORKDIR`
   - `REPAIR_NESSUS_AGENT_LOG_PATH`
   - `REPAIR_NESSUS_AGENT_INSTALLER_SEARCH_PATHS`
2. Copy [`Restore-NessusAgent.local.psd1.example`](/Users/joe/Documents/Tenable/Restore-NessusAgent/Restore-NessusAgent.local.psd1.example) to `Restore-NessusAgent.local.psd1` and fill in the real values.

Environment variables override the local config file.

## Run it

Import the module directly:

```powershell
Import-Module .\Restore-NessusAgent.psd1 -Force
Invoke-NessusAgentDeployment -Relink -AcceptEula -CsvPath .\Tests\agents.csv
```

Or use the operator entry script:

```powershell
pwsh -File .\Scripts\Invoke-RestoreNessusAgent.ps1 -CsvPath .\agents.csv -AcceptEula -Key '<manageengine-passed-key>'
```

ManageEngine-style example:

```powershell
pwsh -File .\Scripts\Invoke-RestoreNessusAgent.ps1 -AcceptEula -Key '<manageengine-passed-key>' -Group 'Windows Servers' -Json
```

Expected machine identity example:

```text
MEDS-PWCTEST001
```

If your deployment tool already knows the destination group, you can pass it directly and skip CSV-based group lookup:

```powershell
pwsh -File .\Scripts\Invoke-RestoreNessusAgent.ps1 -AcceptEula -Key '<manageengine-passed-key>' -Group 'Windows Servers'
```

If you want stdout in a text format that Excel or another tool can parse easily, use one of:

```powershell
pwsh -File .\Scripts\Invoke-RestoreNessusAgent.ps1 -AcceptEula -Key '<manageengine-passed-key>' -Group 'Windows Servers' -Csv
pwsh -File .\Scripts\Invoke-RestoreNessusAgent.ps1 -AcceptEula -Key '<manageengine-passed-key>' -Group 'Windows Servers' -Json
pwsh -File .\Scripts\Invoke-RestoreNessusAgent.ps1 -AcceptEula -Key '<manageengine-passed-key>' -Group 'Windows Servers' -Tab
```

The flat stdout formats now include:
- `Outcome`
- `ActionTaken`
- `LogCopied`
- `RemoteLogPath`

## Validate config

```powershell
Import-Module .\Restore-NessusAgent.psd1 -Force
Get-NessusAgentConfiguration
```

## Test it

Harness:

```powershell
pwsh -File .\Tests\Invoke-RestoreNessusAgentHarness.ps1
```

Pester:

```powershell
pwsh -File .\Tests\Invoke-RestoreNessusAgentPester.ps1
```
