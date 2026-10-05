# Title emission — Windows-native counterpart of src/lib/title.sh.
# Emits OSC 0 (escape + BEL) with the same sanitization rules:
# strip ESC/BEL/CR/LF/TAB/VT/FF, keep UTF-8 text. The separator is
# "<space>·<space>" (U+00B7 MIDDLE DOT) — same constant in both shells.
# UNTESTED on this machine (no pwsh available in the dev environment).

$script:ActTitleSeparator = " · "

function Get-ActTitle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectName,
        [Parameter(Mandatory)][string]$CliName
    )
    return ("{0}{1}{2}" -f $ProjectName, $script:ActTitleSeparator, $CliName)
}

function ConvertTo-ActTitleText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    # Same control-character set as bash: ESC BEL CR LF TAB VT FF.
    return ($Text -replace "[`u{0000}`u{0007}`u{0009}`u{000A}`u{000B}`u{000C}`u{000D}`u{001B}]", '')
}

function Set-ActTabTitle {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Title)

    $clean = ConvertTo-ActTitleText -Text $Title
    if ([string]::IsNullOrEmpty($clean)) { return }

    if ($env:ACT_TITLE_SINK) {
        # Test/diagnostic hook: bytes only, never touching the console.
        [Console]::Out.Write([char]0x1B + ']0;' + $clean + [char]0x07)
        return
    }
    try {
        # Native title path: Windows console API (Windows Terminal picks it up
        # unless the profile sets suppressApplicationTitle).
        $Host.UI.RawUI.WindowTitle = $clean
    }
    catch {
        # Fall back to a raw OSC 0 write.
        [Console]::Out.Write([char]0x1B + ']0;' + $clean + [char]0x07)
    }
}
