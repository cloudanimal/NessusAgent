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
- Tenable Nessus Agent CLI available at the default path, or passed with `-NessusCliPath`, unless you are using the install flow to lay the agent down first
- A valid Nessus linking key when using relink flows

## Configuration

Use either environment variables or a local config file.

Recommended for secrets on Windows: use the encrypted local secret store (DPAPI via `Export-Clixml`) so keys are never embedded in scripts.

Environment variables:

- `REPAIR_NESSUS_AGENT_KEY`
- `REPAIR_NESSUS_AGENT_CUSTOMER_UUID`
- `REPAIR_NESSUS_AGENT_SERVER`
- `REPAIR_NESSUS_AGENT_WORKDIR`
- `REPAIR_NESSUS_AGENT_LOG_PATH`
- `REPAIR_NESSUS_AGENT_INSTALLER_SEARCH_PATHS`
- `TENABLE_ACCESS_KEY`
- `TENABLE_SECRET_KEY`

Local config file:

1. Copy `Restore-NessusAgent.local.psd1.example` to `Restore-NessusAgent.local.psd1`
2. Fill in your environment-specific values

Secure secret store (recommended):

```powershell
Import-Module .\Restore-NessusAgent.psd1 -Force

# Prompts securely; value is stored encrypted for your current Windows user profile.
Set-NessusAgentSecret -NessusKey (Read-Host 'Nessus linking key' -AsSecureString)

# Optional second secret in the same encrypted file.
Set-NessusAgentSecret -CustomerUuid (Read-Host 'Customer UUID' -AsSecureString)
Set-NessusAgentSecret -TenableAccessKey (Read-Host 'Tenable access key' -AsSecureString)
Set-NessusAgentSecret -TenableSecretKey (Read-Host 'Tenable secret key' -AsSecureString)

# Remove one secret or all secrets.
Remove-NessusAgentSecret -NessusKey
Remove-NessusAgentSecret -TenableAccessKey -TenableSecretKey
Remove-NessusAgentSecret -All
```

Configuration precedence is:

1. Environment variables
2. Encrypted secret store
3. `Restore-NessusAgent.local.psd1`
4. Built-in defaults

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

The configuration output includes:

- `SecretStorePath`
- `SecretStorePresent`
- `HasNessusKey`
- `HasCustomerUuid`
- `HasTenableAccessKey`
- `HasTenableSecretKey`

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

## Workflow Validation

Use these steps to validate the operator workflow on a real endpoint.

### 1. Read-only healthcheck

This verifies current health without changing anything:

```powershell
$result = .\Scripts\Invoke-RestoreNessusAgent.ps1 -Json -Relink:$false | ConvertFrom-Json
"EXIT=$LASTEXITCODE"
"OUTCOME=$($result.outcome)"
"AFTER=$($result.afterStatus)"
$result.summary
$result.errors
$result.warnings
```

Expected healthy result:

- `EXIT=0`
- `AFTER=OK`
- summary similar to `healthy agent: no change`

### 2. Full live workflow

This is the destructive end-to-end test: uninstall, download or stage install media, reinstall, relink, then verify health.

#### 2a. Uninstall the agent

```powershell
Import-Module .\Restore-NessusAgent.psd1 -Force
Uninstall-NessusAgent -AllowUninstall -Reason LiveWorkflowTest -Confirm:$false
```

Expected result:

- `Uninstalled = True`
- `DetailedResult = uninstall completed successfully`

#### 2b. Download the installer if needed

```powershell
Import-Module .\Restore-NessusAgent.psd1 -Force
$installer = Get-NessusAgentInstaller -ForceDownload
$installer | Format-List
```

Expected result:

- installer path is returned
- download source is populated when a fresh download occurs

#### 2c. Install the agent

```powershell
Import-Module .\Restore-NessusAgent.psd1 -Force
Install-NessusAgent -Path $installer.Path
```

Expected result:

- `Installed = True`
- `DetailedResult = install completed successfully`

#### 2d. Relink the agent

Set the linking key in the current terminal only, then run the operator script with an explicit group:

```powershell
$env:REPAIR_NESSUS_AGENT_KEY = 'YOUR_LINKING_KEY'
$result = .\Scripts\Invoke-RestoreNessusAgent.ps1 -Json -Group 'SCPM' | ConvertFrom-Json
"EXIT=$LASTEXITCODE"
"OUTCOME=$($result.outcome)"
"AFTER=$($result.afterStatus)"
$result.errors
$result.warnings
Remove-Item Env:REPAIR_NESSUS_AGENT_KEY -ErrorAction SilentlyContinue
```

Expected successful relink result:

- `EXIT=0`
- `OUTCOME=Changed`
- `AFTER=OK`

Notes:

- Passing `-Group 'SCPM'` avoids dependence on CSV group resolution during live validation.
- A remote log share warning such as `Failed to upload log ... The network name cannot be found.` is non-fatal if the final status is still `AFTER=OK`.
- If relink fails with `empty response from controller`, verify the linking key is current.

#### 2e. Confirm steady-state health after relink

```powershell
$health = .\Scripts\Invoke-RestoreNessusAgent.ps1 -Json -Relink:$false | ConvertFrom-Json
"EXIT=$LASTEXITCODE"
"AFTER=$($health.afterStatus)"
"SUMMARY=$($health.summary)"
$health.before | ConvertTo-Json -Depth 5
$health.after | ConvertTo-Json -Depth 5
```

Expected result:

- `EXIT=0`
- `AFTER=OK`
- summary similar to `healthy agent: no change`
- both `before` and `after` health snapshots are present in JSON output

### 3. Verified live result

This workflow was validated successfully on 2026-04-14:

- uninstall succeeded
- installer download succeeded
- install succeeded
- relink succeeded after using a current linking key
- post-relink healthcheck succeeded with `EXIT=0` and `AFTER=OK`

## License

This project is licensed under the MIT License. See `LICENSE` for details.
