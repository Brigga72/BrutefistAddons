param([Parameter(Mandatory=$true)][string]$WorkRoot)
$ErrorActionPreference = 'Stop'
$fixtureRoot = Join-Path $WorkRoot ('updater-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\Update-Addons.ps1') -Destination $fixtureRoot
$betaRoot = Join-Path $fixtureRoot 'beta'
$eraRoot = Join-Path $fixtureRoot 'era'
New-Item -ItemType Directory -Path $betaRoot,$eraRoot | Out-Null
foreach ($name in @('BrutefistDeathReview','DoesItDie','BrutefistGear')) {
    $sourceFolder = Join-Path $fixtureRoot ('addons\' + $name)
    New-Item -ItemType Directory -Path $sourceFolder -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $sourceFolder ($name + '.toc')) -Value '## Interface: 11509'
    Set-Content -LiteralPath (Join-Path $sourceFolder 'Core.lua') -Value '-- version one'
}
$config = @{
    activeProfile='beta'
    profiles=@{beta=$betaRoot;era=$eraRoot}
    profileAddons=@{era=@('BrutefistDeathReview','DoesItDie')}
    addonProfiles=@{DoesItDie=@('era')}
}
$config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $fixtureRoot 'config.json')
$updater = Join-Path $fixtureRoot 'Update-Addons.ps1'
& $updater -Local -Profile beta
if (Test-Path -LiteralPath (Join-Path $betaRoot 'DoesItDie')) {throw 'Era port leaked into beta'}
& $updater -Local -Profile era -Addon DoesItDie
if (Test-Path -LiteralPath (Join-Path $eraRoot 'BrutefistDeathReview')) {throw 'Single-addon filter installed an unselected addon'}
& $updater -Local -Profile era
if (Test-Path -LiteralPath (Join-Path $eraRoot 'BrutefistGear')) {throw 'Forever addon leaked into Era'}
if (!(Test-Path -LiteralPath (Join-Path $eraRoot 'BrutefistDeathReview\Core.lua'))) {throw 'Era addon missing'}
$backups = @(Get-ChildItem -LiteralPath (Join-Path $fixtureRoot 'backups') -Filter Core.lua -Recurse)
if (!$backups.Count) {throw 'Existing installation was not backed up'}
$rejected=$false
try { & $updater -Local -Profile beta -Addon DoesItDie } catch { $rejected=$true }
if (!$rejected) {throw 'Explicit incompatible addon selection was allowed'}
Write-Output 'PASS: profile isolation, single-addon selection, installation, backups and incompatible selection rejection'
