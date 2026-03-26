# Restore-NessusAgent

PowerShell module and operator script for checking, repairing, reinstalling, and relinking the Tenable Nessus Agent.

## What It Does

- Inspects current Nessus Agent health and link target.
- Reinstalls the agent when it is missing.
- Relinks agents that point to the wrong Tenable cloud target.
- Resolves group assignment from a CSV file or a direct override.
- Emits flat output formats that work well with deployment tools and reporting pipelines.

## Repository Layout

- `Public/`: exported PowerShell functions.
- `Private/`: internal helper functions.
- `Scripts/Invoke-RestoreNessusAgent.ps1`: operator entrypoint for deployments and runbooks.
- `Tests/`: harness and Pester coverage.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Tenable Nessus Agent CLI available at the default path, or passed with `-NessusCliPath`
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
Invoke-NessusAgentDeployment -Relink -CsvPath .\Tests\agents.csv
```

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

## Testing

Run the harness:

```powershell
pwsh -File .\Tests\Invoke-RestoreNessusAgentHarness.ps1
```

Run the Pester suite:

```powershell
pwsh -File .\Tests\Invoke-RestoreNessusAgentPester.ps1
```

GitHub Actions is configured to run the Pester suite on pushes to `main` and on pull requests.

## License

This project is licensed under the MIT License. See `LICENSE` for details.
