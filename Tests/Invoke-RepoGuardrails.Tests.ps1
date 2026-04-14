Describe 'Invoke-RepoGuardrails' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..\Scripts\Invoke-RepoGuardrails.ps1'
        . $scriptPath
    }

    It 'returns 0 when there are no staged files' {
        Mock -CommandName Invoke-RepoGit -MockWith {
            param([string[]]$Arguments)
            if (($Arguments -join ' ') -eq 'diff --cached --name-only --diff-filter=ACMR') {
                return @()
            }
            return @()
        }

        $code = Invoke-RepoGuardrails
        $code | Should -Be 0
    }

    It 'returns 1 when added lines contain a key assignment pattern' {
        Mock -CommandName Invoke-RepoGit -MockWith {
            param([string[]]$Arguments)
            $command = $Arguments -join ' '

            if ($command -like 'diff --cached --name-only --diff-filter=ACMR*') {
                return @('foo.ps1')
            }

            if ($command -like 'diff --cached --unified=0 -- foo.ps1*') {
                return @(
                    'diff --git a/foo.ps1 b/foo.ps1',
                    'index 123..456 100644',
                    '--- a/foo.ps1',
                    '+++ b/foo.ps1',
                    '@@ -1,0 +1,1 @@',
                    ('+access' + 'Key=ABCDEFGHIJKLMNOP')
                )
            }

            return @()
        }

        $code = Invoke-RepoGuardrails
        $code | Should -Be 1
    }

    It 'returns 0 when sensitive-looking text exists only in unchanged lines' {
        Mock -CommandName Invoke-RepoGit -MockWith {
            param([string[]]$Arguments)
            $command = $Arguments -join ' '

            if ($command -like 'diff --cached --name-only --diff-filter=ACMR*') {
                return @('bar.ps1')
            }

            if ($command -like 'diff --cached --unified=0 -- bar.ps1*') {
                return @(
                    'diff --git a/bar.ps1 b/bar.ps1',
                    'index 111..222 100644',
                    '--- a/bar.ps1',
                    '+++ b/bar.ps1',
                    '@@ -20,0 +21 @@',
                    '+$status = "ok"'
                )
            }

            return @()
        }

        $code = Invoke-RepoGuardrails
        $code | Should -Be 0
    }
}
