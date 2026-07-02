<#
.SYNOPSIS
  Windows task runner for devops-toolkit-5 — mirror of the Makefile.
.DESCRIPTION
  Same target names as `make`. Python tools run via `python -m` (the launcher is
  more reliably on PATH than the pytest/ruff shims). Tools absent on Windows
  (shellcheck, bats) or an unusable bash are skipped with a warning rather than
  failing the run.
.EXAMPLE
  .\tasks.ps1 test
  .\tasks.ps1 lint
#>
param([string]$Task = 'help')

$ErrorActionPreference = 'Stop'
$PyTargets = @('04-network-ssh/ssh_toolkit', '05-docker-devops/ec2-deploy.py')

function Have($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function Get-Python {
    foreach ($c in 'python', 'python3', 'py') { if (Have $c) { return $c } }
    return $null
}

function Test-Bash {
    # `bash` on Windows PATH is often the WSL stub with no distro installed.
    if (-not (Have bash)) { return $false }
    try { bash -c 'exit 0' 2>$null; return ($LASTEXITCODE -eq 0) } catch { return $false }
}

function Get-ShFiles {
    Get-ChildItem -Path . -Recurse -Filter *.sh -File |
        Where-Object { $_.FullName -notmatch '[\\/]\.venv[\\/]' -and $_.FullName -notmatch '[\\/]\.git[\\/]' } |
        ForEach-Object { $_.FullName }
}

function Invoke-Syntax {
    if (-not (Test-Bash)) { Write-Warning 'usable bash not found (install Git Bash / a WSL distro); skipping syntax'; return }
    $files = Get-ShFiles
    foreach ($f in $files) { bash -n $f; if ($LASTEXITCODE -ne 0) { throw "syntax error: $f" } }
    Write-Host "syntax ok ($($files.Count) scripts)"
}

function Invoke-Shellcheck {
    if (-not (Have shellcheck)) { Write-Warning 'shellcheck not installed; skipping (runs in CI)'; return }
    shellcheck -e SC1091 -S warning @(Get-ShFiles)
    if ($LASTEXITCODE -ne 0) { throw 'shellcheck failed' }
}

function Invoke-Ruff {
    $py = Get-Python
    if (-not $py) { Write-Warning 'python not found; skipping ruff'; return }
    & $py -m ruff --version *> $null
    if ($LASTEXITCODE -ne 0) { Write-Warning 'ruff not installed (pip install ruff); skipping'; return }
    & $py -m ruff check --select E9,F63,F7,F82 @PyTargets
    if ($LASTEXITCODE -ne 0) { throw 'ruff failed' }
}

function Invoke-Bats {
    if (-not (Have bats)) { Write-Warning 'bats not installed (needs WSL/Git Bash); skipping (runs in CI)'; return }
    bats tests/bats
    if ($LASTEXITCODE -ne 0) { throw 'bats failed' }
}

function Invoke-Pytest {
    $py = Get-Python
    if (-not $py) { throw 'python not found; cannot run pytest' }
    & $py -m pytest 04-network-ssh/tests -q
    if ($LASTEXITCODE -ne 0) { throw 'pytest failed' }
}

function Show-Help {
    Write-Host 'Usage: .\tasks.ps1 <target>'
    Write-Host ''
    Write-Host '  help        Show this help'
    Write-Host '  syntax      bash -n over every shell script'
    Write-Host '  shellcheck  shellcheck all shell scripts (CI)'
    Write-Host '  ruff        ruff real-error lint on the Python code'
    Write-Host '  lint        syntax + shellcheck + ruff'
    Write-Host '  bats        bats shell tests (CI)'
    Write-Host '  pytest      pytest suite'
    Write-Host '  test        bats + pytest'
    Write-Host '  all         lint + test'
}

switch ($Task) {
    'help'       { Show-Help }
    'syntax'     { Invoke-Syntax }
    'shellcheck' { Invoke-Shellcheck }
    'ruff'       { Invoke-Ruff }
    'lint'       { Invoke-Syntax; Invoke-Shellcheck; Invoke-Ruff }
    'bats'       { Invoke-Bats }
    'pytest'     { Invoke-Pytest }
    'test'       { Invoke-Bats; Invoke-Pytest }
    'all'        { Invoke-Syntax; Invoke-Shellcheck; Invoke-Ruff; Invoke-Bats; Invoke-Pytest }
    default      { Write-Warning "unknown target: '$Task'"; Show-Help; exit 1 }
}
