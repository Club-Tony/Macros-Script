# Validate-Tooltips.ps1
#
# Validates MacrosApp tooltip wiring by parsing the source files that define
# the tooltip assignments. This is intentionally deterministic: external hover
# automation against Win32 tooltip windows proved flaky and produced false
# negatives even when the app wiring was correct.
#
# Run from any cwd:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\Validate-Tooltips.ps1
#
# No build is required. The script reads:
# - MacrosApp/MainForm.cs
# - MacrosApp/Controls/SlotListControl.cs
# - MacrosApp/Controls/ControllerStatePanel.cs

$ErrorActionPreference = 'Stop'

function Read-FileText {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required file not found: $Path"
    }

    return [System.IO.File]::ReadAllText($Path)
}

function Unescape-CSharpString {
    param([string]$Value)

    return [regex]::Unescape($Value)
}

function Get-CSharpStringMap {
    param(
        [string]$Text,
        [string]$Pattern
    )

    $map = @{}
    foreach ($match in [regex]::Matches($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $name = $match.Groups['name'].Value
        $value = Unescape-CSharpString $match.Groups['value'].Value
        $map[$name] = $value
    }

    return $map
}

function Merge-Maps {
    param(
        [hashtable]$Destination,
        [hashtable]$Source
    )

    foreach ($key in $Source.Keys) {
        $Destination[$key] = $Source[$key]
    }
}

function Test-Contains {
    param(
        [string]$Text,
        [string]$Expected
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    return $Text.IndexOf($Expected, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Get-PreviewText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $singleLine = ($Text -replace '\s+', ' ').Trim()
    if ($singleLine.Length -le 100) {
        return $singleLine
    }

    return $singleLine.Substring(0, 97) + '...'
}

function New-Result {
    param(
        [string]$Target,
        [string]$Source,
        [string]$Expected,
        [string]$Status,
        [string]$Captured
    )

    return [pscustomobject]@{
        Target   = $Target
        Source   = $Source
        Expected = $Expected
        Status   = $Status
        Captured = Get-PreviewText $Captured
    }
}

$appRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $appRoot 'MacrosApp'

$mainFormPath = Join-Path $sourceRoot 'MainForm.cs'
$slotListPath = Join-Path $sourceRoot 'Controls\SlotListControl.cs'
$controllerPath = Join-Path $sourceRoot 'Controls\ControllerStatePanel.cs'

$mainFormText = Read-FileText $mainFormPath
$slotListText = Read-FileText $slotListPath
$controllerText = Read-FileText $controllerPath

$tooltips = @{}

Merge-Maps $tooltips (Get-CSharpStringMap -Text $mainFormText -Pattern '(?s)_hoverHelp\.SetToolTip\(\s*(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*,\s*"(?<value>(?:\\.|[^"\\])*)"\s*\)\s*;')
Merge-Maps $tooltips (Get-CSharpStringMap -Text $mainFormText -Pattern '(?s)(?<name>[A-Za-z_][A-Za-z0-9_]*)\.ApplyToolTip\(\s*_hoverHelp\s*,\s*"(?<value>(?:\\.|[^"\\])*)"\s*\)\s*;')
Merge-Maps $tooltips (Get-CSharpStringMap -Text $mainFormText -Pattern '(?s)(?<name>[A-Za-z_][A-Za-z0-9_]*)\.ToolTipText\s*=\s*"(?<value>(?:\\.|[^"\\])*)"\s*;')

$targets = @(
    @{ Label = '/ Macro';           Source = 'btnSlashMacro';      Expect = 'Slash Macro' }
    @{ Label = 'Autoclicker';       Source = 'btnAutoclicker';     Expect = 'autoclicker' }
    @{ Label = 'Turbo Hold';        Source = 'btnTurboHold';       Expect = 'Turbo Hold' }
    @{ Label = 'Pure Hold';         Source = 'btnPureHold';        Expect = 'Pure Hold' }
    @{ Label = 'Recorder';          Source = 'btnRecorder';        Expect = 'recording' }
    @{ Label = 'Saved Recordings';  Source = 'slotHeaderLabel';    Expect = 'macros.ini' }
    @{ Label = 'Saved Recordings';  Source = 'slotList';           Expect = 'Double-click a slot to play it' }
    @{ Label = 'Settings';          Source = 'settingsHeaderLabel';Expect = 'Playback' }
    @{ Label = 'Controller';        Source = 'controllerHeaderLabel'; Expect = 'XInput' }
    @{ Label = 'Controller';        Source = 'controllerState';    Expect = 'read-only' }
    @{ Label = 'Engine Status';     Source = 'engineStatusLabel';  Expect = 'MacrosEngine DLL' }
    @{ Label = 'Profile Status';    Source = 'profileStatusLabel'; Expect = 'foreground app' }
)

$results = New-Object System.Collections.Generic.List[object]

foreach ($target in $targets) {
    $sourceName = $target.Source
    $captured = $tooltips[$sourceName]

    if ($null -eq $captured) {
        $results.Add((New-Result -Target $target.Label -Source $sourceName -Expected $target.Expect -Status 'MISSING_ASSIGNMENT' -Captured ''))
        continue
    }

    if (Test-Contains -Text $captured -Expected $target.Expect) {
        $status = 'PASS'
    }
    else {
        $status = 'TEXT_MISMATCH'
    }

    $results.Add((New-Result -Target $target.Label -Source $sourceName -Expected $target.Expect -Status $status -Captured $captured))
}

# Structural checks for the custom controls that proxy tooltip text.
$slotListApplyOk =
    $slotListText -match 'toolTip\.SetToolTip\(this,\s*text\)' -and
    $slotListText -match 'toolTip\.SetToolTip\(_listBox,\s*text\)'

$controllerApplyOk =
    $controllerText -match 'toolTip\.SetToolTip\(this,\s*text\)'

$results.Add((New-Result -Target 'SlotList ApplyToolTip' -Source 'SlotListControl.ApplyToolTip' -Expected 'Attach tooltip to both control and list box' -Status ($(if ($slotListApplyOk) { 'PASS' } else { 'PLUMBING_MISSING' })) -Captured ($(if ($slotListApplyOk) { 'toolTip.SetToolTip(this, text); toolTip.SetToolTip(_listBox, text);' } else { '' }))))
$results.Add((New-Result -Target 'Controller ApplyToolTip' -Source 'ControllerStatePanel.ApplyToolTip' -Expected 'Attach tooltip to control' -Status ($(if ($controllerApplyOk) { 'PASS' } else { 'PLUMBING_MISSING' })) -Captured ($(if ($controllerApplyOk) { 'toolTip.SetToolTip(this, text);' } else { '' }))))

Write-Host ''
Write-Host '=== Tooltip validation results ==='
$results | Format-Table -AutoSize -Wrap

$passCount = ($results | Where-Object Status -eq 'PASS').Count
$total = $results.Count

Write-Host ''
Write-Host "Summary: $passCount / $total tooltip checks passed."
Write-Host 'Mode: source validation only. This checks tooltip assignments and custom-control plumbing, not transient OS hover windows.'

if ($passCount -lt $total) {
    exit 1
}

exit 0
