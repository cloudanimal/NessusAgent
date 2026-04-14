# Restore-NessusAgent

PowerShell module and operator script for checking, repairing, reinstalling, and relinking the Tenable Nessus Agent.

## What It Does

- Inspects current Nessus Agent health and link target.
- Reinstalls the agent when it is missing.
- Relinks agents that point to the wrong Tenable cloud target.
- Resolves group assignment from a CSV file or a direct override.
- Supports guarded uninstall workflows for Nessus Agent only.
- Exports Tenable agent inventory to CSV/JSONL for group-driven relink workflows.
- Emits flat output formats that work well with deployment tools and reporting pipelines.

## Repository Layout

- `Public/`: exported PowerShell functions.
- `Private/`: internal helper functions.
- `Scripts/Invoke-RestoreNessusAgent.ps1`: operator entrypoint for deployments and runbooks.
- `Tests/`: harness and Pester coverage.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Tenable Nessus Agent CLI available at the default path, or passed with `-NessusCliPath`, unless you are using the install flow to lay the agent down first
- A valid Nessus linking key when using relink flows

## Configuration

Use either environment variables or a local config file.

Environment variables:

- `REPAIR_NESSUS_AGENT_KEY`
- `REPAIR_NESSUS_AGENT_CUSTOMER_UUID`
- `REPAIR_NESSUS_AGENT_SERVER`
- `REPAIR_NESSUS_AGENT_WORKDIR`
- `REPAIR_NESSUS_AGENT_LOG_PATH`
- `REPAIR_NESSUS_AGENT_INSTALLER_SEARCH_PATHS`

Local config file:

1. Copy `Restore-NessusAgent.local.psd1.example` to `Restore-NessusAgent.local.psd1`
2. Fill in your environment-specific values

Environment variables take precedence over the local config file.

## Usage

Import the module directly:

```powershell
Import-Module .\Restore-NessusAgent.psd1 -Force
Restore-NessusAgent -Relink -CsvPath .\Tests\agents.csv
```

That example assumes the Nessus linking key is already configured through `REPAIR_NESSUS_AGENT_KEY` or `Restore-NessusAgent.local.psd1`.

Run the operator script:

```powershell
pwsh -File .\Scripts\Invoke-RestoreNessusAgent.ps1 -CsvPath .\agents.csv -Key '<manageengine-passed-key>'
```

Pass the destination group directly when your deployment system already knows it:

```powershell
pwsh -File .\Scripts\Invoke-RestoreNessusAgent.ps1 -Key '<manageengine-passed-key>' -Group 'Windows Servers'
```

ManageEngine-style JSON output:

```powershell
pwsh -File .\Scripts\Invoke-RestoreNessusAgent.ps1 -Key '<manageengine-passed-key>' -Group 'Windows Servers' -Json
```

Optional post-link convergence retry knobs:

```powershell
Restore-NessusAgent -Relink -CsvPath .\Tests\agents.csv -LinkStatusRetryCount 6 -LinkStatusRetryDelaySeconds 10
```

Use these when a freshly linked agent reports `connection has not been attempted` for a short period after relink.

Other flat output formats:

```powershell
pwsh -File .\Scripts\Invoke-RestoreNessusAgent.ps1 -Key '<manageengine-passed-key>' -Group 'Windows Servers' -Csv
pwsh -File .\Scripts\Invoke-RestoreNessusAgent.ps1 -Key '<manageengine-passed-key>' -Group 'Windows Servers' -Tab
```

The flat output includes:

- `Outcome`
- `ActionTaken`
- `Summary`
- `BeforeStatus`
- `AfterStatus`
- `LinkedHost`
- `ExpectedHost`
- `Group`
- `GroupSource`
- `LocalLogPath`
- `RemoteLogPath`

## Validate Configuration

```powershell
Import-Module .\Restore-NessusAgent.psd1 -Force
Get-NessusAgentConfiguration
```

## Uninstall Workflow

Preflight safety checks only (no uninstall):

```powershell
Import-Module .\Restore-NessusAgent.psd1 -Force
Uninstall-NessusAgent -AllowUninstall -PreflightOnly -Confirm:$false
```

Actual uninstall (Nessus Agent only, guarded by product identity checks):

```powershell
Import-Module .\Restore-NessusAgent.psd1 -Force
Uninstall-NessusAgent -AllowUninstall -Confirm:$false
```

The command validates product code format, uninstall registry identity, and running process state before calling `msiexec`.

## Export-TIOAgents Workflow

Fast inventory export (CSV with group column):

```powershell
pwsh -File .\Public\Export-TIOAgents.ps1 -ScannerId 1 -OutDir C:\Temp\Tenable -Mode Fast
```

Detail export with full-fidelity JSONL:

```powershell
pwsh -File .\Public\Export-TIOAgents.ps1 -ScannerId 1 -OutDir C:\Temp\Tenable -Mode Detail
```

Detail test sample run:

```powershell
pwsh -File .\Public\Export-TIOAgents.ps1 -ScannerId 1 -OutDir C:\Temp\Tenable -DetailTest -SampleSize 10
```

Then run repair using exported CSV:

```powershell
pwsh -File .\Scripts\Invoke-RestoreNessusAgent.ps1 -CsvPath C:\Temp\Tenable\TioAgentInventory_Fast_Scanner1.csv -Confirm:$false
```

If a matched row has an empty `Groups` value, CSV group resolution will fail by design. In that case pass `-Group` explicitly or use `-GroupOverride`.

## Testing

Run the harness:

```powershell
pwsh -File .\Tests\Invoke-RestoreNessusAgentHarness.ps1
```

Run the Pester suite:

```powershell
pwsh -File .\Tests\Invoke-RestoreNessusAgentPester.ps1
```

Run all validations directly:

```powershell
Invoke-Pester -Path .\Tests -PassThru
.\Tests\Invoke-RestoreNessusAgentHarness.ps1
.\Tests\Invoke-RestoreNessusAgentTagHarness.ps1
```

GitHub Actions is configured to run the Pester suite on pushes to `main` and on pull requests.

## License

This project is licensed under the MIT License. See `LICENSE` for details.
