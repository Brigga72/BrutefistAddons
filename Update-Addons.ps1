[CmdletBinding()]
param([switch]$Local, [switch]$Preview, [string]$Profile)
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
    if (!$addons.Count) { throw 'No addons found.' }
    foreach ($addon in $addons) {
        if ($addon.Name -notmatch '^[A-Za-z0-9_-]+$') { throw 'Invalid addon folder name.' }
        if (!(Test-Path -LiteralPath (Join-Path $addon.FullName ($addon.Name + '.toc')))) { throw "Missing TOC: $($addon.Name)" }
        if (Get-ChildItem -LiteralPath $addon.FullName -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw 'Linked source files are not supported.' }
    }
    $backup = Join-Path $PSScriptRoot ('backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    foreach ($addon in $addons) {
        $target = Join-Path $destination $addon.Name
        if (Test-Path -LiteralPath $target) {
            if ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked target not supported: $target" }
            if (Get-ChildItem -LiteralPath $target -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw "Linked target content not supported: $target" }
        }
        Write-Host "$(if ($Preview) {'Would install'} else {'Installing'}) $($addon.Name) -> $target"
        if (!$Preview) {
            if (Test-Path -LiteralPath $target) {
                New-Item -ItemType Directory -Path $backup -Force | Out-Null
                Copy-Item -LiteralPath $target -Destination $backup -Recurse
            }
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            Get-ChildItem -LiteralPath $addon.FullName -Force | Copy-Item -Destination $target -Recurse -Force
        }
    }
    if (!$Preview) { Write-Host "Done. Type /reload in game. Backups (when needed): $backup" }
} finally {
    if ($temporary) { Write-Verbose "Download staging retained at $temporary" }
}
