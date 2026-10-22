[CmdletBinding()]
param([switch]$Local, [switch]$Preview, [string]$Profile, [string[]]$Addon)
$ErrorActionPreference = 'Stop'
$config = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Raw | ConvertFrom-Json
if (!$Profile) { $Profile = $config.activeProfile }
$destination = $config.profiles.$Profile
if (!$destination) { throw "Unknown profile: $Profile" }
$destination = [IO.Path]::GetFullPath($destination)
if (!(Test-Path -LiteralPath $destination -PathType Container)) { throw "Addon folder not found: $destination. Verify config.json before installing." }
$temporary = $null
try {
    $source = Join-Path $PSScriptRoot 'addons'
    if (!$Local) {
        $temporary = Join-Path ([IO.Path]::GetTempPath()) ('Brutefist-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $temporary | Out-Null
        $archive = Join-Path $temporary 'source.zip'
        $url = 'https://codeload.github.com/{0}/zip/refs/heads/{1}' -f $config.repository, $config.branch
        Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
        Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $temporary 'extracted')
        $roots = @(Get-ChildItem -LiteralPath (Join-Path $temporary 'extracted') -Directory)
        if ($roots.Count -ne 1) { throw 'Unexpected repository archive layout.' }
        $source = Join-Path $roots[0].FullName 'addons'
    }
    $addons = @(Get-ChildItem -LiteralPath $source -Directory)
    $addons = @($addons | Where-Object {
        $supportedProfiles = $config.addonProfiles.($_.Name)
        !$supportedProfiles -or $Profile -in @($supportedProfiles)
    })
    if ($Profile -eq 'era') {
        $selection = @($config.profileAddons.era)
        if (!$selection.Count -or !$selection[0]) { throw 'Era requires an explicit profileAddons.era list in config.json.' }
        foreach ($name in $selection) {
            if ($name -notin $addons.Name) { throw "Configured Era addon not found: $name" }
        }
        $addons = @($addons | Where-Object { $_.Name -in $selection })
    }
    if ($Addon) {
        foreach ($name in $Addon) {
            if ($name -notin $addons.Name) { throw "Addon unavailable for profile ${Profile}: $name" }
        }
        $addons = @($addons | Where-Object { $_.Name -in $Addon })
    }
    if (!$addons.Count) { throw 'No addons found.' }
    foreach ($addonDirectory in $addons) {
        if ($addonDirectory.Name -notmatch '^[A-Za-z0-9_-]+$') { throw 'Invalid addon folder name.' }
        if (!(Test-Path -LiteralPath (Join-Path $addonDirectory.FullName ($addonDirectory.Name + '.toc')))) { throw "Missing TOC: $($addonDirectory.Name)" }
        if (Get-ChildItem -LiteralPath $addonDirectory.FullName -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw 'Linked source files are not supported.' }
    }
    $backup = Join-Path $PSScriptRoot ('backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    foreach ($addonDirectory in $addons) {
        $target = Join-Path $destination $addonDirectory.Name
        if (Test-Path -LiteralPath $target) {
            if ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked target not supported: $target" }
            if (Get-ChildItem -LiteralPath $target -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw "Linked target content not supported: $target" }
        }
        Write-Host "$(if ($Preview) {'Would install'} else {'Installing'}) $($addonDirectory.Name) -> $target"
        if (!$Preview) {
            if (Test-Path -LiteralPath $target) {
                New-Item -ItemType Directory -Path $backup -Force | Out-Null
                Copy-Item -LiteralPath $target -Destination $backup -Recurse
            }
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            Get-ChildItem -LiteralPath $addonDirectory.FullName -Force | Copy-Item -Destination $target -Recurse -Force
        }
    }
    if (!$Preview) { Write-Host "Done. Type /reload in game. Backups (when needed): $backup" }
} finally {
    if ($temporary) { Write-Verbose "Download staging retained at $temporary" }
}
