[CmdletBinding()]
param(
    [string]$CubeIdeHeadless = 'C:\ST\STM32CubeIDE_2.2.0\STM32CubeIDE\headless-build.bat',
    [string]$Workspace = ''
)

$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $projectRoot '..\..')).Path
if (-not (Test-Path -LiteralPath $CubeIdeHeadless -PathType Leaf)) {
    throw "STM32CubeIDE headless builder not found: $CubeIdeHeadless"
}

if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = Join-Path $repoRoot `
        ('.cubeide-workspaces\headless-' +
         [System.Guid]::NewGuid().ToString('N'))
}
$Workspace = [System.IO.Path]::GetFullPath($Workspace)
New-Item -ItemType Directory -Path $Workspace -Force | Out-Null

$failurePattern = '(?im)(Cannot run program|Launching failed|Build Failed|' +
    'Errors occurred during the build|fatal error:|undefined reference|' +
    'make(?:\.exe)?: \*\*\*|:\s*warning:)'

function Invoke-CubeIde {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    Write-Host "`n== $Label =="
    $lines = @(& $CubeIdeHeadless @Arguments 2>&1 | ForEach-Object {
        $line = $_.ToString()
        Write-Host $line
        $line
    })
    $exitCode = $LASTEXITCODE
    $joined = $lines -join "`n"
    if (($exitCode -ne 0) -or ($joined -match $failurePattern)) {
        throw "$Label failed (exit=$exitCode)."
    }
}

$buildStart = Get-Date
Invoke-CubeIde -Label 'Import CubeIDE projects' -Arguments @(
    '-data', $Workspace, '-importAll', $projectRoot
)

$targets = @(
    [pscustomobject]@{
        Name = 'algo_CM7/Debug'
        Elf = Join-Path $projectRoot 'CM7\Debug\algo_CM7.elf'
        Map = Join-Path $projectRoot 'CM7\Debug\algo_CM7.map'
    },
    [pscustomobject]@{
        Name = 'algo_CM4/Debug'
        Elf = Join-Path $projectRoot 'CM4\Debug\algo_CM4.elf'
        Map = Join-Path $projectRoot 'CM4\Debug\algo_CM4.map'
    },
    [pscustomobject]@{
        Name = 'algo_CM7/Release'
        Elf = Join-Path $projectRoot 'CM7\Release\algo_CM7.elf'
        Map = Join-Path $projectRoot 'CM7\Release\algo_CM7.map'
    },
    [pscustomobject]@{
        Name = 'algo_CM4/Release'
        Elf = Join-Path $projectRoot 'CM4\Release\algo_CM4.elf'
        Map = Join-Path $projectRoot 'CM4\Release\algo_CM4.map'
    }
)

foreach ($target in $targets) {
    Invoke-CubeIde -Label "Clean build $($target.Name)" -Arguments @(
        '-data', $Workspace, '-cleanBuild', $target.Name
    )
}

$oldestAcceptedWrite = $buildStart.AddSeconds(-2)
foreach ($target in $targets) {
    foreach ($artifactPath in @($target.Elf, $target.Map)) {
        if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
            throw "Missing build artifact: $artifactPath"
        }
        $artifact = Get-Item -LiteralPath $artifactPath
        if (($artifact.Length -le 0) -or
            ($artifact.LastWriteTime -lt $oldestAcceptedWrite)) {
            throw "Artifact was not produced by this run: $artifactPath"
        }
    }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $target.Elf).Hash
    Write-Host ("PASS {0}: {1} bytes, SHA256={2}" -f `
        $target.Name, (Get-Item -LiteralPath $target.Elf).Length, $hash)
}

$cm7ReleaseMap = Join-Path $projectRoot 'CM7\Release\algo_CM7.map'
$requiredSymbols = @(
    'SuppressionControl_Update',
    'MotorCommandMapper_Update',
    'MotorPositionGuard_Update',
    'TB6612Driver_Update',
    'QuadratureEncoder_OnEdge',
    'STM32_TB6612_HAL_Apply'
)
$mapText = Get-Content -LiteralPath $cm7ReleaseMap -Raw
foreach ($symbol in $requiredSymbols) {
    if ($mapText -notmatch [regex]::Escape($symbol)) {
        throw "CM7 Release map is missing required symbol: $symbol"
    }
}

Write-Host "`nAll four CubeIDE configurations passed."
Write-Host "Workspace retained for diagnostics: $Workspace"
