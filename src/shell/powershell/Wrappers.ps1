# Wrapper runtime — Windows-native counterpart of src/run/act-wrap.sh.
# Strategy B on Windows: set the tab title, run the CLI in the FOREGROUND,
# restore the project-only title afterwards. No background jobs, no polling.
# UNTESTED on this machine (no pwsh available in the dev environment).

. "$PSScriptRoot/Project.ps1"
. "$PSScriptRoot/Title.ps1"

function Invoke-ActCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CliName,
        [Parameter(Mandatory)][string]$RealCli,
        [string[]]$CliArgs = @()
    )

    $project = Get-ActProjectName
    $title = Get-ActTitle -ProjectName $project -CliName $CliName

    # -n/--name supplied by the user wins — respect it (AC3):
    # emit the final title ourselves, but leave the CLI's own flag to do the work.
    $userNamed = $false
    for ($i = 0; $i -lt $CliArgs.Count; $i++) {
        if ($CliArgs[$i] -eq '-n' -or $CliArgs[$i] -eq '--name' -or
            $CliArgs[$i] -like '-n=*' -or $CliArgs[$i] -like '--name=*') {
            $userNamed = $true
            break
        }
    }
    if (-not $userNamed) {
        Set-ActTabTitle -Title $title
    }

    # Foreground launch — child receives the title as its own console title.
    if ($CliArgs.Count -gt 0) {
        & $RealCli @CliArgs
    }
    else {
        & $RealCli
    }
    $code = $LASTEXITCODE

    # Restore: project-only title survives the CLI's exit (AC8).
    Set-ActTabTitle -Title $project
    return $code
}
