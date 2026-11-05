param(
    [string]$AddonRoot = 'C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns',
    [Parameter(Mandatory = $true)]
    [string]$AccountRoot,
    [string]$BackupParent = (Join-Path $env:USERPROFILE 'addon-backups')
)
$ErrorActionPreference = 'Stop'
if (Get-Process -Name Wow -ErrorAction SilentlyContinue) { throw 'Exit WoW normally before installing.' }
$project = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$addons = (Resolve-Path -LiteralPath $AddonRoot).Path.TrimEnd('\')
$account = (Resolve-Path -LiteralPath $AccountRoot).Path
$scope = @('Peddler','Gearwise','Wayfinder','XPCounter')
$unrelatedBefore = @(Get-ChildItem -LiteralPath $addons -Directory | Where-Object { $_.Name -ne 'MiniQoL' -and $scope -notcontains $_.Name } | Select-Object -ExpandProperty Name)
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$build = Join-Path $project ('build\personal-' + $stamp)
& python (Join-Path $PSScriptRoot 'build.py') --account $account --output $build
if ($LASTEXITCODE -ne 0) { throw 'The four-component build failed.' }
& python (Join-Path $project 'tests\run.py') (Join-Path $build 'MiniQoL')
if ($LASTEXITCODE -ne 0) { throw 'The four-component checks failed.' }
$report = Get-Content -LiteralPath (Join-Path $build 'build-report.json') -Raw | ConvertFrom-Json
if ($report.modules -ne 4 -or @($report.order | Where-Object {$scope -notcontains $_}).Count) { throw 'The build contains an unrelated addon.' }
$backup = Join-Path $BackupParent ('MiniQoL-four-component-install-' + $stamp)
New-Item -ItemType Directory -Path $backup | Out-Null
$backup = (Resolve-Path -LiteralPath $backup).Path
Copy-Item -LiteralPath $account -Destination (Join-Path $backup 'Account') -Recurse
$staging = Join-Path $backup 'StagedMiniQoL'
Copy-Item -LiteralPath (Join-Path $build 'MiniQoL') -Destination $staging -Recurse
if (Get-Process -Name Wow -ErrorAction SilentlyContinue) { throw 'WoW was opened during staging. Original addon folders are unchanged.' }
$retired = @()
foreach ($name in @('MiniQoL') + $scope) {
    $source = [IO.Path]::GetFullPath((Join-Path $addons $name))
    $destination = [IO.Path]::GetFullPath((Join-Path $backup $name))
    if ([IO.Path]::GetDirectoryName($source) -ne $addons -or [IO.Path]::GetDirectoryName($destination) -ne $backup) { throw 'Unsafe component retirement path.' }
    if (Test-Path -LiteralPath $source) { Move-Item -LiteralPath $source -Destination $destination; $retired += $name }
}
$installed = [IO.Path]::GetFullPath((Join-Path $addons 'MiniQoL'))
if ([IO.Path]::GetDirectoryName($installed) -ne $addons -or [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($staging)) -ne $backup) { throw 'Unsafe install path.' }
Move-Item -LiteralPath $staging -Destination $installed
foreach ($file in Get-ChildItem -LiteralPath $account -Filter AddOns.txt -File -Recurse) {
    $lines = @(Get-Content -LiteralPath $file.FullName | Where-Object {
        if ($_ -match '^([^:]+):') { $scope -notcontains $Matches[1] -and $Matches[1] -ne 'MiniQoL' } else { $true }
    })
    foreach ($name in $scope) { $lines += "${name}: disabled" }
    $lines += 'MiniQoL: enabled'
    [IO.File]::WriteAllLines($file.FullName, $lines, [Text.UTF8Encoding]::new($false))
}
$unrelatedAfter = @(Get-ChildItem -LiteralPath $addons -Directory | Where-Object { $_.Name -ne 'MiniQoL' -and $scope -notcontains $_.Name } | Select-Object -ExpandProperty Name)
if (@(Compare-Object $unrelatedBefore $unrelatedAfter).Count) { throw 'An unrelated addon folder changed.' }
@{ scope=$scope; retired=$retired; unrelated=$unrelatedAfter; addonRoot=$addons; accountRoot=$account; backup=$backup } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backup 'install.json') -Encoding UTF8
Write-Host "Installed Mini QoL with exactly four components. Preserved $($unrelatedAfter.Count) other addon folders. Backup: $backup"
