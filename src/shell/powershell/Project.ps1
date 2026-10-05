# Project name resolution — Windows-native counterpart of src/lib/project.sh.
# Rule (identical to WSL): project name = basename of the current directory.
# UNTESTED on this machine (no pwsh available in the dev environment).

function Get-ActProjectName {
    [CmdletBinding()]
    param(
        # Override for tests; defaults to the current location.
        [string]$Path = (Get-Location).Path
    )

    try {
        $trimmed = $Path.TrimEnd('\', '/')
        if ([string]::IsNullOrEmpty($trimmed)) {
            return [Environment]::MachineName
        }
        $name = Split-Path -Leaf $trimmed
        if ([string]::IsNullOrWhiteSpace($name)) {
            return [Environment]::MachineName
        }
        return $name
    }
    catch {
        return [Environment]::MachineName
    }
}
