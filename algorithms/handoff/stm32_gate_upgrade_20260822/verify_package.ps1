$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Root = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$ManifestPath = Join-Path $Root "PACKAGE_MANIFEST.json"
$Manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 |
    ConvertFrom-Json

if ($Manifest.schema_version -ne 1 -or
    $Manifest.package_id -ne "steadyhope-stm32-gate-upgrade-20260822") {
    throw "Unexpected package manifest identity."
}
if ($Manifest.authorization.actuation_authority -ne "none" -or
    $Manifest.authorization.motor_power_connected -ne $false -or
    $Manifest.authorization.powered_human_use -ne $false) {
    throw "Package authority must remain fail-closed."
}

$Expected = @{}
foreach ($Entry in $Manifest.files) {
    $Relative = [string]$Entry.path
    if ($Expected.ContainsKey($Relative)) {
        throw "Duplicate manifest path: $Relative"
    }
    $Expected[$Relative] = $Entry
    $Path = Join-Path $Root $Relative
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing package file: $Relative"
    }
    $Item = Get-Item -LiteralPath $Path
    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($Item.Length -ne [int64]$Entry.bytes) {
        throw "Size mismatch: $Relative"
    }
    if ($Hash -ne ([string]$Entry.sha256).ToLowerInvariant()) {
        throw "SHA-256 mismatch: $Relative"
    }
}

$Actual = Get-ChildItem -LiteralPath $Root -Recurse -File |
    ForEach-Object {
        $_.FullName.Substring($Root.Length + 1).Replace('\', '/')
    } |
    Where-Object { $_ -ne "PACKAGE_MANIFEST.json" }

$Extra = @($Actual | Where-Object { -not $Expected.ContainsKey($_) })
if ($Extra.Count -ne 0) {
    throw "Unlisted package files: $($Extra -join ', ')"
}

Write-Host "PACKAGE VERIFICATION: PASS"
Write-Host "Files verified: $($Expected.Count)"
Write-Host "Actuation authority: none"
