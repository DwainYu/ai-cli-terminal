#Requires -Version 5.1
<#
.SYNOPSIS
  ai-cli-terminal — Windows validation harness (manual layer).

.DESCRIPTION
  Run on a real Windows machine from a checkout:

      .\scripts\test-windows.ps1

  Read-only by contract:
    * never runs install/uninstall (no --apply equivalent, no rc edits),
    * never installs an AI CLI — availability is reported as NOT AVAILABLE,
    * never touches Windows Terminal settings.json,
    * the only observable side effect is a window-title round trip that
      restores the original title afterwards.

  Checks (AC-P2-05):
    1. the PowerShell modules load (syntax smoke),
    2. project name from the real fixture project
       D:\ghq\github.com\DwainYu\TFTAutoRecorder  ->  TFTAutoRecorder,
    3. title formula "<project> · <CLI>",
    4. sanitization (ESC/BEL/CR/LF/TAB stripped, UTF-8 kept),
    5. window-title round trip via Set-ActTabTitle,
    6. AI CLI availability on Windows (informational).

  The four-tab Windows Terminal procedure lives in
  tests/manual/windows/README.md (AC-P2-07).
#>
param(
    [string]$FixtureProject = 'D:\ghq\github.com\DwainYu\TFTAutoRecorder'
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptRoot

# --- 1. modules load ---------------------------------------------------------
try {
    . (Join-Path $repoRoot 'src/shell/powershell/Project.ps1')
    . (Join-Path $repoRoot 'src/shell/powershell/Title.ps1')
    . (Join-Path $repoRoot 'src/shell/powershell/Wrappers.ps1')
    Write-Output 'ok 1 - PowerShell modules load (Project/Title/Wrappers)'
}
catch {
    Write-Output "not ok 1 - PowerShell modules load: $_"
    Write-Output '1..1'
    exit 1
}

$script:n = 1
$script:pass = 1
$script:fail = 0

function Check {
    param([string]$Name, [string]$Expected, [string]$Actual)
    $script:n++
    if ($Expected -eq $Actual) {
        $script:pass++
        Write-Output ("ok {0} - {1}" -f $script:n, $Name)
    }
    else {
        $script:fail++
        Write-Output ("not ok {0} - {1}" -f $script:n, $Name)
        Write-Output ("#   expected: {0}" -f $Expected)
        Write-Output ("#   actual:   {0}" -f $Actual)
    }
}

# --- 2. real Windows project fixture (AC-P2-12) ------------------------------
if (Test-Path -LiteralPath $FixtureProject) {
    $name = Get-ActProjectName -Path $FixtureProject
    Check 'project name of TFTAutoRecorder fixture' 'TFTAutoRecorder' $name
}
else {
    $script:n++
    $script:fail++
    Write-Output ("not ok {0} - fixture missing: {1}" -f $script:n, $FixtureProject)
    Write-Output '#   pass -FixtureProject <path> to point somewhere else'
}

# --- 3. title formula --------------------------------------------------------
Check 'title formula' 'TFTAutoRecorder · PI' `
    (Get-ActTitle -ProjectName 'TFTAutoRecorder' -CliName 'PI')

# --- 4. sanitization ---------------------------------------------------------
$esc = [char]27
$bel = [char]7
$cr = [char]13
$dirty = "b$([char]27)ad$bel`tt$cr itle$([char]27)"
Check 'sanitize strips ESC/BEL/TAB/CR' 'badt itle' `
    (ConvertTo-ActTitleText -Text $dirty)
Check 'sanitize keeps UTF-8' '项目 · PI' `
    (ConvertTo-ActTitleText -Text '项目 · PI')

# --- 5. window-title round trip (restores afterwards) ------------------------
$original = $null
try { $original = $Host.UI.RawUI.WindowTitle } catch { $original = $null }
try {
    $sink = Join-Path ([IO.Path]::GetTempPath()) ("act-sink-" + [guid]::NewGuid().ToString() + '.bin')
    $env:ACT_TITLE_SINK = $sink
    Set-ActTabTitle -Title 'ai-cli-terminal smoke · TEST'
    if (Test-Path -LiteralPath $sink) {
        $bytes = [IO.File]::ReadAllText($sink)
        Check 'sink receives an OSC 0 sequence' 'True' ($bytes.StartsWith([char]27 + ']0;').ToString())
        Check 'sink payload is the title' 'True' ($bytes.Contains('ai-cli-terminal smoke · TEST').ToString())
        Remove-Item -LiteralPath $sink
    }
    else {
        Check 'sink receives an OSC 0 sequence' 'True' 'sink file missing'
    }
}
catch {
    Check 'sink receives an OSC 0 sequence' 'True' "exception: $_"
}
finally {
    Remove-Item Env:ACT_TITLE_SINK -ErrorAction SilentlyContinue
    if ($null -ne $original) {
        try { $Host.UI.RawUI.WindowTitle = $original } catch { }
    }
}

# --- 6. AI CLI availability on Windows (informational, never installed) ------
foreach ($cli in @('pi', 'opencode', 'codebuddy', 'qoder')) {
    $cmd = Get-Command $cli -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Output ("#   {0}: AVAILABLE ({1})" -f $cli, $cmd.Source)
    }
    else {
        Write-Output ("#   {0}: NOT AVAILABLE (not installed on Windows - not installed by this harness)" -f $cli)
    }
}

# --- summary -----------------------------------------------------------------
Write-Output ("1..{0}" -f $script:n)
if ($script:fail -gt 0) {
    Write-Output ("# FAILED {0} of {1}" -f $script:fail, $script:n)
    exit 1
}
Write-Output ("# PASS {0}" -f $script:pass)
exit 0
