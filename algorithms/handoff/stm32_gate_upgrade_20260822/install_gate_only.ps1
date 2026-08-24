[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [switch]$Apply
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedCommit = "9e51e56bfcaf70ca1c140b3f37e1977935c534e5"
$ExpectedOldCBlob = "b170b7f0a8aa2c100f7699fbf967b8f4c250cf31"
$ExpectedOldHBlob = "2756f76bbd7276bbd9eb12ce56def267de4fa7bb"
$ExpectedNewCSha256 = "2AE990DCAFE06DB927E9607FC7070EECC9479ED03888C0C28052DAF6FDCCAC81"
$ExpectedNewHSha256 = "F9E10ED377B8E640D3D249614A1A71D7623E295E11F57FDE134E6DA476AE22C5"

$Root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$SourceC = Join-Path $PSScriptRoot "src\gating\tremor_gate.c"
$SourceH = Join-Path $PSScriptRoot "src\gating\tremor_gate.h"
$TargetC = Join-Path $Root "firmware\algo\CM7\Core\Src\tremor_gate.c"
$TargetH = Join-Path $Root "firmware\algo\CM7\Core\Inc\tremor_gate.h"

foreach ($Path in @($SourceC, $SourceH, $TargetC, $TargetH)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file is missing: $Path"
    }
}

$Head = (& git -C $Root rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $Head -ne $ExpectedCommit) {
    throw "Expected Ryan 2026-08-18 commit $ExpectedCommit, found $Head"
}

$RelativeC = "firmware/algo/CM7/Core/Src/tremor_gate.c"
$RelativeH = "firmware/algo/CM7/Core/Inc/tremor_gate.h"
$Dirty = & git -C $Root status --porcelain -- $RelativeC $RelativeH
if ($LASTEXITCODE -ne 0 -or $Dirty) {
    throw "Target gate files have local changes; review them manually before replacing."
}

$OldCBlob = (& git -C $Root hash-object -- $TargetC).Trim()
$OldHBlob = (& git -C $Root hash-object -- $TargetH).Trim()
if ($OldCBlob -ne $ExpectedOldCBlob -or $OldHBlob -ne $ExpectedOldHBlob) {
    throw "Target gate files do not match the audited Ryan 8/18 pair."
}

$SourceCSha256 = (Get-FileHash -LiteralPath $SourceC -Algorithm SHA256).Hash
$SourceHSha256 = (Get-FileHash -LiteralPath $SourceH -Algorithm SHA256).Hash
if ($SourceCSha256 -ne $ExpectedNewCSha256 -or
    $SourceHSha256 -ne $ExpectedNewHSha256) {
    throw "Package source hash mismatch; do not install this copy."
}

if (-not $Apply) {
    Write-Host "CHECK PASSED. No files changed."
    Write-Host "Re-run with -Apply to replace tremor_gate.c and tremor_gate.h together."
    exit 0
}

Copy-Item -LiteralPath $SourceC -Destination $TargetC
Copy-Item -LiteralPath $SourceH -Destination $TargetH

$InstalledCSha256 = (Get-FileHash -LiteralPath $TargetC -Algorithm SHA256).Hash
$InstalledHSha256 = (Get-FileHash -LiteralPath $TargetH -Algorithm SHA256).Hash
if ($InstalledCSha256 -ne $ExpectedNewCSha256 -or
    $InstalledHSha256 -ne $ExpectedNewHSha256) {
    throw "Installed files failed the SHA-256 verification."
}

Write-Host "Latest hardened 4-6 Hz gate pair installed."
Write-Host "NEXT: apply ryan_9e51_shadow_only.patch, CubeIDE Clean, then full rebuild."
Write-Host "Motor/H-bridge power must remain physically disconnected."
