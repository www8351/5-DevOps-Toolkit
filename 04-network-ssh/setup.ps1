# setup.ps1 — bootstrap ssh_toolkit on Windows (PowerShell 5.1+)
#
# Usage:
#   .\setup.ps1 --help
#   .\setup.ps1 all --host 193.168.1.1 --user refael
#
[CmdletBinding(PositionalBinding=$false)]
param([Parameter(ValueFromRemainingArguments=$true)] $Rest)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$VenvDir   = Join-Path $ScriptDir ".venv"
$ReqFile   = Join-Path $ScriptDir "requirements.txt"

# ── find Python 3.8+ ──────────────────────────────────────────────────────────
$Py = $null
foreach ($candidate in @("py", "python", "python3")) {
    try {
        $ver = & $candidate -c "import sys; print(sys.version_info >= (3,8))" 2>$null
        if ($ver -eq "True") { $Py = $candidate; break }
    } catch {}
}

if (-not $Py) {
    Write-Error "[x] Python 3.8+ not found. Install from https://python.org and retry."
    exit 1
}

$pyVer = & $Py --version
Write-Host "[i] Using: $pyVer"

# ── create venv ───────────────────────────────────────────────────────────────
if (-not (Test-Path $VenvDir)) {
    Write-Host "[i] Creating virtual environment at .venv ..."
    & $Py -m venv $VenvDir
}

$VenvPy = Join-Path $VenvDir "Scripts\python.exe"

# ── install dependencies ───────────────────────────────────────────────────────
Write-Host "[i] Installing dependencies ..."
& $VenvPy -m pip install --quiet --upgrade pip
& $VenvPy -m pip install --quiet -r $ReqFile

Write-Host "[OK] Environment ready."

# ── copy example config if missing ────────────────────────────────────────────
$CfgPath    = Join-Path $ScriptDir "config.toml"
$CfgExample = Join-Path $ScriptDir "config.example.toml"
if (-not (Test-Path $CfgPath) -and (Test-Path $CfgExample)) {
    Copy-Item $CfgExample $CfgPath
    Write-Host "[!] config.toml created from example — edit it before running."
}

# ── launch toolkit ────────────────────────────────────────────────────────────
& $VenvPy -m ssh_toolkit @Rest
exit $LASTEXITCODE
