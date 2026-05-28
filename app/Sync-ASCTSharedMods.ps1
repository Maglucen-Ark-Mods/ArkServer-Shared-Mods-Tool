param(
    [switch]$ApplyOnly
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $PSCommandPath
$localConfigPath = Join-Path $scriptDir 'ArkServerCreationToolSharedMods.local.json'

function Resolve-ASCTRoot {
    $candidates = @()

    if (Test-Path -LiteralPath $localConfigPath) {
        try {
            $localConfig = Get-Content -LiteralPath $localConfigPath -Raw | ConvertFrom-Json
            if ($localConfig.asctRoot) {
                $candidates += [string]$localConfig.asctRoot
            }
        }
        catch {
            throw "Could not read local config ${localConfigPath}: $($_.Exception.Message)"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:ASCT_ROOT)) {
        $candidates += $env:ASCT_ROOT
    }

    $candidates += @(
        'C:\Ark\ASCT',
        (Join-Path $scriptDir 'ASCT')
    )

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return 'C:\Ark\ASCT'
}

function Join-ASCTPath {
    param([string]$RelativePath)
    Join-Path $script:AsctRoot $RelativePath
}

$script:AsctRoot = Resolve-ASCTRoot
$configPath = Join-ASCTPath 'ASCTGlobalConfig.json'
$sharedModsPath = Join-ASCTPath 'Shared\SharedModIDs.txt'
$backupDir = Join-ASCTPath 'Shared\Backups\ASCTGlobalConfig'
$libraryPath = Join-ASCTPath 'Shared\ModsUserData\83374\library.json'
$curseForgeApiKeyPath = Join-ASCTPath 'Shared\CurseForgeApiKey.txt'
$curseForgeApiKeyExamplePath = Join-ASCTPath 'Shared\CurseForgeApiKey.txt.example'
$curseForgeApiBase = 'https://api.curseforge.com/v1'
$curseForgeGameId = 83374

$defaultCategoryOrder = @(
    'Quality of Life'
    'Breeding and Taming'
    'Building and Decoration'
    'Creatures and Spawns'
    'Storage and Management'
    'Content and Progression'
    'Cosmetics'
)

$defaultCategoryMap = @{
    '928539'  = 'Quality of Life'
    '953154'  = 'Quality of Life'
    '931047'  = 'Quality of Life'
    '928597'  = 'Quality of Life'
    '947033'  = 'Quality of Life'
    '950914'  = 'Quality of Life'
    '930389'  = 'Quality of Life'
    '1163881' = 'Quality of Life'
    '1010722' = 'Quality of Life'
    '935408'  = 'Quality of Life'
    '930684'  = 'Quality of Life'
    '930025'  = 'Quality of Life'
    '1027633' = 'Quality of Life'
    '932225'  = 'Quality of Life'
    '930851'  = 'Quality of Life'
    '932365'  = 'Quality of Life'
    '928501'  = 'Quality of Life'
    '1487708' = 'Quality of Life'
    '928621'  = 'Quality of Life'
    '947899'  = 'Quality of Life'
    '941697'  = 'Breeding and Taming'
    '1008361' = 'Breeding and Taming'
    '1017722' = 'Breeding and Taming'
    '1485386' = 'Breeding and Taming'
    '928818'  = 'Breeding and Taming'
    '1221524' = 'Breeding and Taming'
    '933447'  = 'Building and Decoration'
    '940975'  = 'Building and Decoration'
    '937184'  = 'Building and Decoration'
    '946694'  = 'Building and Decoration'
    '1067961' = 'Creatures and Spawns'
    '928548'  = 'Creatures and Spawns'
    '1188679' = 'Creatures and Spawns'
    '942024'  = 'Storage and Management'
    '933099'  = 'Storage and Management'
    '1054976' = 'Content and Progression'
    '983782'  = 'Content and Progression'
    '1165229' = 'Content and Progression'
    '1051646' = 'Cosmetics'
    '949521'  = 'Cosmetics'
}

$legacyCategoryMap = @{
    'Calidad de vida' = 'Quality of Life'
    'Cria y domesticacion' = 'Breeding and Taming'
    'Construccion y decoracion' = 'Building and Decoration'
    'Criaturas y spawns' = 'Creatures and Spawns'
    'Almacenamiento y gestion' = 'Storage and Management'
    'Contenido y progresion' = 'Content and Progression'
    'Cosmeticos' = 'Cosmetics'
    'Sin categoria' = 'Uncategorized'
}

function Assert-PathExists {
    param(
        [string]$Path,
        [string]$Label
    )

    if (-not (Test-Path $Path)) {
        throw "No existe ${Label}: $Path"
    }
}

function Load-LibraryMods {
    Assert-PathExists -Path $libraryPath -Label 'la biblioteca de mods'

    $json = Get-Content -LiteralPath $libraryPath -Raw | ConvertFrom-Json
    $mods = @()

    foreach ($item in @($json.installedMods)) {
        if ($null -eq $item.details -or $null -eq $item.details.id -or [string]::IsNullOrWhiteSpace($item.details.name)) {
            continue
        }

        $mods += [pscustomobject]@{
            Id = [string]$item.details.id
            Name = [string]$item.details.name
        }
    }

    $mods |
        Sort-Object Name, Id -Unique
}

function Get-CurseForgeApiKey {
    if (-not [string]::IsNullOrWhiteSpace($env:CURSEFORGE_API_KEY)) {
        return $env:CURSEFORGE_API_KEY.Trim()
    }

    if (Test-Path $curseForgeApiKeyPath) {
        $value = (Get-Content -LiteralPath $curseForgeApiKeyPath -Raw).Trim()
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    if (Test-Path $curseForgeApiKeyExamplePath) {
        $value = (Get-Content -LiteralPath $curseForgeApiKeyExamplePath -Raw).Trim()
        $lines = @($value -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object {
            $_ -and -not $_.StartsWith('#') -and $_ -ne 'YOUR_CURSEFORGE_API_KEY_HERE'
        })
        if ($lines.Count -gt 0) {
            return $lines[0]
        }
    }

    return $null
}

function Invoke-CurseForgeApi {
    param(
        [string]$RelativePath,
        [hashtable]$Query = @{}
    )

    $apiKey = Get-CurseForgeApiKey
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        throw "No hay API key de CurseForge. Define CURSEFORGE_API_KEY o guarda la clave en $curseForgeApiKeyPath"
    }

    $queryString = ''
    if ($Query.Count -gt 0) {
        $pairs = foreach ($key in $Query.Keys) {
            '{0}={1}' -f [System.Uri]::EscapeDataString([string]$key), [System.Uri]::EscapeDataString([string]$Query[$key])
        }
        $queryString = '?' + ($pairs -join '&')
    }

    $uri = '{0}/{1}{2}' -f $curseForgeApiBase.TrimEnd('/'), $RelativePath.TrimStart('/'), $queryString

    Invoke-RestMethod -Method Get -Uri $uri -Headers @{
        'Accept' = 'application/json'
        'x-api-key' = $apiKey
    }
}

function Get-CurseForgeModById {
    param(
        [string]$Id
    )

    $normalizedId = Normalize-ModId -Id $Id
    $baseId = Get-ModBaseId -Id $normalizedId
    $response = Invoke-CurseForgeApi -RelativePath ("mods/{0}" -f $baseId)
    if ($null -eq $response -or $null -eq $response.data) {
        return $null
    }

    [pscustomobject]@{
        Id = $normalizedId
        Name = [string]$response.data.name
        Summary = [string]$response.data.summary
        DownloadCount = [int64]$response.data.downloadCount
    }
}

function Search-CurseForgeMods {
    param(
        [string]$Query
    )

    $response = Invoke-CurseForgeApi -RelativePath 'mods/search' -Query @{
        gameId = $curseForgeGameId
        searchFilter = $Query
        pageSize = 15
    }

    if ($null -eq $response -or $null -eq $response.data) {
        return @()
    }

    @($response.data | ForEach-Object {
        [pscustomobject]@{
            Id = [string]$_.id
            Name = [string]$_.name
            Summary = [string]$_.summary
            DownloadCount = [int64]$_.downloadCount
        }
    })
}

function Get-ModName {
    param(
        [string]$Id
    )

    $resolvedId = Resolve-ModNameMapId -Id $Id
    if ($script:ModNameMap.ContainsKey($resolvedId)) {
        return $script:ModNameMap[$resolvedId]
    }

    return '(Unknown mod)'
}

function Get-ModCategory {
    param(
        [string]$Id
    )

    $normalizedId = Normalize-ModId -Id $Id
    if ($script:ModCategoryMap.ContainsKey($normalizedId) -and -not [string]::IsNullOrWhiteSpace($script:ModCategoryMap[$normalizedId])) {
        return $script:ModCategoryMap[$normalizedId]
    }

    $baseId = Get-ModBaseId -Id $normalizedId
    if ($script:ModCategoryMap.ContainsKey($baseId) -and -not [string]::IsNullOrWhiteSpace($script:ModCategoryMap[$baseId])) {
        return $script:ModCategoryMap[$baseId]
    }

    return 'Uncategorized'
}

function Normalize-ModId {
    param(
        [string]$Id
    )

    $trimmed = [string]$Id
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw 'ID de mod vacio.'
    }

    $trimmed = $trimmed.Trim()
    $match = [regex]::Match($trimmed, '^(?<base>\d+)(?<dev>-dev)?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        throw "ID de mod no valido: $Id"
    }

    $baseId = [string]$match.Groups['base'].Value
    $suffix = if ($match.Groups['dev'].Success) { '-dev' } else { '' }
    return ('{0}{1}' -f $baseId, $suffix)
}

function Get-ModBaseId {
    param(
        [string]$Id
    )

    $normalized = Normalize-ModId -Id $Id
    return ([regex]::Match($normalized, '^\d+')).Value
}

function Test-IsDevModId {
    param(
        [string]$Id
    )

    return (Normalize-ModId -Id $Id).EndsWith('-dev')
}

function Resolve-ModNameMapId {
    param(
        [string]$Id
    )

    $normalized = Normalize-ModId -Id $Id
    if ($script:ModNameMap.ContainsKey($normalized)) {
        return $normalized
    }

    $baseId = Get-ModBaseId -Id $normalized
    if ($script:ModNameMap.ContainsKey($baseId)) {
        return $baseId
    }

    return $normalized
}

function Get-ModSortBase {
    param(
        [string]$Id
    )

    return [int64](Get-ModBaseId -Id $Id)
}

function Get-ModSortVariant {
    param(
        [string]$Id
    )

    if (Test-IsDevModId -Id $Id) {
        return 1
    }

    return 0
}

function Normalize-Category {
    param(
        [string]$Category
    )

    if ([string]::IsNullOrWhiteSpace($Category)) {
        return 'Uncategorized'
    }

    $trimmed = $Category.Trim()
    if ($legacyCategoryMap.ContainsKey($trimmed)) {
        return [string]$legacyCategoryMap[$trimmed]
    }

    return $trimmed
}

function Initialize-CategoryState {
    $script:ModCategoryMap = @{}
    $script:CategoryOrder = @()

    foreach ($category in $defaultCategoryOrder) {
        if ($script:CategoryOrder -notcontains $category) {
            $script:CategoryOrder += $category
        }
    }

    foreach ($id in $defaultCategoryMap.Keys) {
        $script:ModCategoryMap[[string]$id] = [string]$defaultCategoryMap[$id]
    }
}

function Parse-ModIdsFromLines {
    param(
        [string[]]$Lines,
        [string]$SourceLabel
    )

    $ids = @()
    $seen = @{}

    foreach ($rawLine in $Lines) {
        $line = $rawLine.Trim()

        if (-not $line -or $line.StartsWith('#')) {
            continue
        }

        $line = [regex]::Replace($line, '\s+#.*$', '').Trim()

        $id = Normalize-ModId -Id $line
        $baseId = Get-ModBaseId -Id $id

        if ($seen.ContainsKey($id)) {
            throw "ID de mod duplicado en ${SourceLabel}: $id"
        }

        if ($seen.ContainsKey($baseId)) {
            throw "El mod base ${baseId} aparece mas de una vez en ${SourceLabel}: $($seen[$baseId]) y $id"
        }

        $seen[$id] = $true
        $seen[$baseId] = $id
        $ids += [string]$id
    }

    return @($ids)
}

function Parse-SharedModEntries {
    param(
        [string[]]$Lines,
        [string]$SourceLabel
    )

    $entries = @()
    $seen = @{}
    $currentCategory = 'Uncategorized'

    foreach ($rawLine in $Lines) {
        $line = $rawLine.Trim()

        if (-not $line) {
            continue
        }

        if ($line.StartsWith('#')) {
            $comment = $line.TrimStart('#').Trim()
            if (
                $comment -and
                $comment -notlike 'Shared mod list*' -and
                $comment -notlike 'Format:*' -and
                $comment -notlike 'This file is managed*'
            ) {
                $currentCategory = Normalize-Category -Category $comment
            }
            continue
        }

        $match = [regex]::Match($line, '^\s*(\d+(?:-dev)?)\s*(?:#\s*(.+?)\s*)?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $match.Success) {
            throw "Linea no valida en ${SourceLabel}: $rawLine"
        }

        $id = Normalize-ModId -Id $match.Groups[1].Value
        $name = [string]$match.Groups[2].Value
        $baseId = Get-ModBaseId -Id $id

        if ($seen.ContainsKey($id)) {
            throw "ID de mod duplicado en ${SourceLabel}: $id"
        }

        if ($seen.ContainsKey($baseId)) {
            throw "El mod base ${baseId} aparece mas de una vez en ${SourceLabel}: $($seen[$baseId]) y $id"
        }

        $seen[$id] = $true
        $seen[$baseId] = $id
        $entries += [pscustomobject]@{
            Id = $id
            Name = $name
            Category = (Normalize-Category -Category $currentCategory)
        }
    }

    return @($entries)
}

function Get-SharedModIds {
    Assert-PathExists -Path $sharedModsPath -Label 'la lista compartida de mods'
    $lines = Get-Content -LiteralPath $sharedModsPath
    return @(Parse-ModIdsFromLines -Lines $lines -SourceLabel $sharedModsPath)
}

function Merge-SharedModNamesIntoMap {
    Assert-PathExists -Path $sharedModsPath -Label 'la lista compartida de mods'
    $entries = Parse-SharedModEntries -Lines (Get-Content -LiteralPath $sharedModsPath) -SourceLabel $sharedModsPath

    foreach ($entry in $entries) {
        if (-not [string]::IsNullOrWhiteSpace($entry.Name) -and -not $script:ModNameMap.ContainsKey($entry.Id)) {
            $script:ModNameMap[$entry.Id] = $entry.Name.Trim()
        }
        if (-not [string]::IsNullOrWhiteSpace($entry.Category)) {
            $normalizedCategory = Normalize-Category -Category $entry.Category
            $script:ModCategoryMap[$entry.Id] = $normalizedCategory
            if ($script:CategoryOrder -notcontains $normalizedCategory) {
                $script:CategoryOrder += $normalizedCategory
            }
        }
    }
}

function Save-SharedModIds {
    param(
        [string[]]$Ids
    )

    $normalized = @(
        $Ids |
        ForEach-Object { Normalize-ModId -Id $_ } |
        Sort-Object { Get-ModCategory $_ }, { Get-ModName $_ }, { Get-ModSortBase $_ }, { Get-ModSortVariant $_ }
    )
    $lines = @(
        '# Shared mod list for ARK Server Creation Tool'
        '# Format: ID # Mod Name'
        '# This file is managed by Sync-ASCTSharedMods.ps1'
        ''
    )

    $categoriesInUse = @(
        $normalized |
        ForEach-Object { Get-ModCategory $_ } |
        Select-Object -Unique
    )

    $categories = @(
        $script:CategoryOrder |
        Where-Object { $categoriesInUse -contains $_ } |
        Select-Object -Unique
    )

    $extraCategories = @(
        $categoriesInUse |
        Where-Object { $categories -notcontains $_ } |
        Sort-Object -Unique
    )

    foreach ($category in @($categories + $extraCategories)) {
        $lines += ('# {0}' -f $category)
        foreach ($id in @($normalized | Where-Object { (Get-ModCategory $_) -eq $category })) {
            $lines += ('{0}   # {1}' -f $id, (Get-ModName $id))
        }
        $lines += ''
    }

    [System.IO.File]::WriteAllLines($sharedModsPath, $lines, [System.Text.UTF8Encoding]::new($false))
}

function Compare-IdLists {
    param(
        [string[]]$Left,
        [string[]]$Right
    )

    $leftArr = @($Left)
    $rightArr = @($Right)

    if ($leftArr.Count -ne $rightArr.Count) {
        return $false
    }

    for ($i = 0; $i -lt $leftArr.Count; $i++) {
        if ([string]$leftArr[$i] -ne [string]$rightArr[$i]) {
            return $false
        }
    }

    return $true
}

function Get-ModStringFromLaunchArgs {
    param(
        [string]$LaunchArgs
    )

    if ([string]::IsNullOrWhiteSpace($LaunchArgs)) {
        return $null
    }

    $quoted = [regex]::Match($LaunchArgs, '"-mods=([^"]*)"')
    if ($quoted.Success) {
        return $quoted.Groups[1].Value
    }

    $plain = [regex]::Match($LaunchArgs, '\s-mods=([^\s"]+)')
    if ($plain.Success) {
        return $plain.Groups[1].Value
    }

    return $null
}

function Test-ConfigInSync {
    param(
        [string[]]$Ids
    )

    Assert-PathExists -Path $configPath -Label 'el archivo de configuracion de ARK Server Creation Tool'
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $expected = @($Ids | ForEach-Object { Normalize-ModId -Id $_ })
    $expectedBase = @($expected | ForEach-Object { Get-ModBaseId -Id $_ })
    $modsString = ($expected -join ',')

    foreach ($server in @($config.Servers)) {
        $serverIds = @($server.modIDs | ForEach-Object { [string]$_ })
        if (-not (Compare-IdLists -Left $expectedBase -Right $serverIds)) {
            return $false
        }

        if ($server.useCustomLaunchArgs -and $server.customLaunchArgs) {
            $modsInArgs = Get-ModStringFromLaunchArgs -LaunchArgs $server.customLaunchArgs
            if ($null -eq $modsInArgs -or $modsInArgs -ne $modsString) {
                return $false
            }
        }
    }

    return $true
}

function Apply-SharedModsToConfig {
    param(
        [string[]]$Ids
    )

    Assert-PathExists -Path $configPath -Label 'el archivo de configuracion de ARK Server Creation Tool'

    $normalizedIds = @($Ids | ForEach-Object { Normalize-ModId -Id $_ })
    $modIds = @($normalizedIds | ForEach-Object { [int64](Get-ModBaseId -Id $_) })
    if ($modIds.Count -eq 0) {
        throw 'La lista compartida de mods esta vacia.'
    }

    Save-SharedModIds -Ids @($normalizedIds)

    $modsString = ($normalizedIds -join ',')
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

    if (-not $config.Servers) {
        throw 'ASCTGlobalConfig.json no contiene la coleccion Servers.'
    }

    foreach ($server in @($config.Servers)) {
        $server.modIDs = @($modIds)

        if ($server.useCustomLaunchArgs -and $server.customLaunchArgs) {
            if ($server.customLaunchArgs -match '"-mods=[^"]*"') {
                $server.customLaunchArgs = [regex]::Replace(
                    $server.customLaunchArgs,
                    '"-mods=[^"]*"',
                    ('"-mods={0}"' -f $modsString),
                    1
                )
            }
            elseif ($server.customLaunchArgs -match '\s-mods=\S+') {
                $server.customLaunchArgs = [regex]::Replace(
                    $server.customLaunchArgs,
                    '\s-mods=\S+',
                    (' -mods={0}' -f $modsString),
                    1
                )
            }
            else {
                Write-Warning "No se encontro bloque -mods en customLaunchArgs para $($server.Name). modIDs si fue actualizado."
            }
        }
    }

    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupPath = Join-Path $backupDir "ASCTGlobalConfig.$timestamp.json"
    Copy-Item -LiteralPath $configPath -Destination $backupPath -Force

    $json = $config | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($configPath, $json, [System.Text.UTF8Encoding]::new($false))

    return [pscustomobject]@{
        ConfigPath = $configPath
        BackupPath = $backupPath
        ServerCount = @($config.Servers).Count
        ModCount = @($Ids).Count
    }
}

function Pause-ForUser {
    Write-Host ''
    [void](Read-Host 'Pulsa Enter para continuar')
}

function Write-SubtleSeparator {
    param(
        [int]$Width,
        [int]$LeftPadding = 0
    )

    $safeWidth = [Math]::Max(12, $Width)
    Write-Host ((' ' * [Math]::Max(0, $LeftPadding)) + ('-' * $safeWidth)) -ForegroundColor DarkGray
}

function Get-CategoryLayout {
    param(
        [object[]]$Records,
        [int]$Width,
        [int]$Gutter = 4
    )

    $count = @($Records).Count
    if ($count -eq 0) {
        return [pscustomobject]@{
            ColumnCount = 1
            RowCount = 0
            ColumnWidths = @(12)
            TotalWidth = 12
            Gutter = $Gutter
        }
    }

    $minCellWidth = 18
    $maxColumns = [Math]::Max(1, [Math]::Min($count, [Math]::Floor($Width / $minCellWidth)))

    for ($columnCount = $maxColumns; $columnCount -ge 1; $columnCount--) {
        $rowCount = [Math]::Ceiling($count / [double]$columnCount)
        $columnWidths = @()

        for ($col = 0; $col -lt $columnCount; $col++) {
            $maxLength = 0
            for ($row = 0; $row -lt $rowCount; $row++) {
                $idx = $row + ($col * $rowCount)
                if ($idx -ge $count) {
                    continue
                }

                $record = $Records[$idx]
                $cellLength = 9 + $record.Name.Length
                if ($cellLength -gt $maxLength) {
                    $maxLength = $cellLength
                }
            }

            if ($maxLength -gt 0) {
                $columnWidths += $maxLength
            }
        }

        $totalWidth = ($columnWidths | Measure-Object -Sum).Sum
        if ($columnWidths.Count -gt 1) {
            $totalWidth += ($Gutter * ($columnWidths.Count - 1))
        }

        if ($totalWidth -le $Width) {
            return [pscustomobject]@{
                ColumnCount = $columnWidths.Count
                RowCount = $rowCount
                ColumnWidths = @($columnWidths)
                TotalWidth = $totalWidth
                Gutter = $Gutter
            }
        }
    }

    $fallbackWidth = 12
    foreach ($record in @($Records)) {
        $cellLength = 9 + $record.Name.Length
        if ($cellLength -gt $fallbackWidth) {
            $fallbackWidth = $cellLength
        }
    }

    return [pscustomobject]@{
        ColumnCount = 1
        RowCount = $count
        ColumnWidths = @($fallbackWidth)
        TotalWidth = $fallbackWidth
        Gutter = $Gutter
    }
}

function Show-ModList {
    param(
        [string[]]$Ids
    )

    $records = @($Ids | ForEach-Object {
        [pscustomobject]@{
            Id = $_
            Name = Get-ModName $_
            Category = Get-ModCategory $_
        }
    })

    $width = 120
    try {
        $width = [Math]::Max(80, $Host.UI.RawUI.WindowSize.Width - 2)
    }
    catch {
        $width = 120
    }

    Write-Host ''
    $orderedCategories = @(
        $script:CategoryOrder |
        Where-Object { $records.Category -contains $_ } |
        Select-Object -Unique
    )
    $extraCategories = @(
        $records.Category |
        Where-Object { $orderedCategories -notcontains $_ } |
        Sort-Object -Unique
    )

    $allCategories = @($orderedCategories + $extraCategories)

    for ($categoryIndex = 0; $categoryIndex -lt $allCategories.Count; $categoryIndex++) {
        $category = $allCategories[$categoryIndex]
        $categoryRecords = @($records | Where-Object { $_.Category -eq $category })
        if ($categoryRecords.Count -eq 0) {
            continue
        }

        $layout = Get-CategoryLayout -Records $categoryRecords -Width $width
        $leftPadding = [Math]::Max(0, [Math]::Floor(($width - $layout.TotalWidth) / 2))

        Write-Host ((' ' * $leftPadding) + ('[{0}]' -f $category)) -ForegroundColor Cyan

        for ($row = 0; $row -lt $layout.RowCount; $row++) {
            $usedColumns = @()
            for ($col = 0; $col -lt $layout.ColumnCount; $col++) {
                $idx = $row + ($col * $layout.RowCount)
                if ($idx -lt $categoryRecords.Count) {
                    $usedColumns += $col
                }
            }

            Write-Host (' ' * $leftPadding) -NoNewline

            foreach ($col in $usedColumns) {
                $idx = $row + ($col * $layout.RowCount)
                $record = $categoryRecords[$idx]
                $cellLength = 9 + $record.Name.Length
                $padding = [Math]::Max(0, $layout.ColumnWidths[$col] - $cellLength)

                Write-Host ('{0,-8}' -f $record.Id) -NoNewline -ForegroundColor DarkYellow
                Write-Host ' ' -NoNewline
                Write-Host $record.Name -NoNewline -ForegroundColor Gray

                if ($col -ne $usedColumns[-1]) {
                    Write-Host (' ' * ($padding + $layout.Gutter)) -NoNewline
                }
            }

            Write-Host ''
        }

        Write-Host ''

        if ($categoryIndex -lt ($allCategories.Count - 1)) {
            Write-SubtleSeparator -Width $layout.TotalWidth -LeftPadding $leftPadding
            Write-Host ''
        }
    }
}

function Parse-CommaSeparatedIds {
    param(
        [string]$InputText
    )

    $parts = $InputText.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    if ($parts.Count -eq 0) {
        return @()
    }

    $ids = @()
    $seen = @{}
    foreach ($part in $parts) {
        $id = Normalize-ModId -Id $part
        $baseId = Get-ModBaseId -Id $id

        if ($seen.ContainsKey($id)) {
            continue
        }

        if ($seen.ContainsKey($baseId)) {
            throw "El mod base ${baseId} aparece varias veces en la misma lista: $($seen[$baseId]) y $id"
        }

        $seen[$id] = $true
        $seen[$baseId] = $id
        $ids += [string]$id
    }

    return @($ids)
}

function Parse-CommaSeparatedIndexes {
    param(
        [string]$InputText,
        [int]$MaxIndex
    )

    $parts = $InputText.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    if ($parts.Count -eq 0) {
        return @()
    }

    $indexes = @()
    $seen = @{}
    foreach ($part in $parts) {
        if ($part -notmatch '^\d+$') {
            throw "Indice no valido: $part"
        }

        $number = [int]$part
        if ($number -lt 1 -or $number -gt $MaxIndex) {
            throw "Indice fuera de rango: $number"
        }

        if (-not $seen.ContainsKey($number)) {
            $seen[$number] = $true
            $indexes += $number
        }
    }

    return @($indexes)
}

function Confirm-Selection {
    param(
        [string[]]$Ids,
        [string]$Verb
    )

    if (@($Ids).Count -eq 0) {
        Write-Host 'No hay mods seleccionados.'
        Pause-ForUser
        return $false
    }

    Write-Host ''
    Write-Host "Se van a $Verb estos mods:"
    Write-Host ''

    foreach ($id in @($Ids)) {
        Write-Host ('- {0}  {1}' -f $id, (Get-ModName $id))
    }

    Write-Host ''
    $answer = Read-Host 'Confirmar (S/N)'
    return $answer -match '^(s|si|y|yes)$'
}

function Add-Ids {
    param(
        [string[]]$WorkingIds,
        [string[]]$IdsToAdd
    )

    $result = @($WorkingIds | ForEach-Object { Normalize-ModId -Id $_ })
    foreach ($id in @($IdsToAdd | ForEach-Object { Normalize-ModId -Id $_ })) {
        $baseId = Get-ModBaseId -Id $id
        $existingVariant = @(
            $result |
            Where-Object { (Get-ModBaseId -Id $_) -eq $baseId -and $_ -ne $id } |
            Select-Object -First 1
        )

        if ($existingVariant.Count -gt 0) {
            $previousId = [string]$existingVariant[0]
            $previousCategory = Get-ModCategory -Id $previousId
            $result = @($result | Where-Object { (Get-ModBaseId -Id $_) -ne $baseId })
            if (-not $script:ModCategoryMap.ContainsKey($id) -and -not [string]::IsNullOrWhiteSpace($previousCategory)) {
                $script:ModCategoryMap[$id] = $previousCategory
            }
        }

        if ($result -notcontains $id) {
            if (-not $script:ModCategoryMap.ContainsKey($id)) {
                $script:ModCategoryMap[$id] = Get-ModCategory -Id $id
            }
            $result += $id
        }
    }

    return @($result)
}

function Remove-Ids {
    param(
        [string[]]$WorkingIds,
        [string[]]$IdsToRemove
    )

    return @($WorkingIds | Where-Object { $IdsToRemove -notcontains $_ })
}

function Search-LibraryMods {
    param(
        [string]$Query
    )

    @($script:LibraryMods | Where-Object {
        $_.Name -like ('*{0}*' -f $Query) -or $_.Id -like ('*{0}*' -f $Query)
    } | Sort-Object Name, Id)
}

function Ensure-ModNamesForIds {
    param(
        [string[]]$Ids
    )

    foreach ($id in @($Ids)) {
        if ($script:ModNameMap.ContainsKey($id) -and -not [string]::IsNullOrWhiteSpace($script:ModNameMap[$id])) {
            continue
        }

        try {
            $mod = Get-CurseForgeModById -Id $id
            if ($null -ne $mod -and -not [string]::IsNullOrWhiteSpace($mod.Name)) {
                $script:ModNameMap[$id] = $mod.Name
            }
        }
        catch {
            # Leave the mod as unknown if CurseForge lookup is unavailable.
        }
    }
}

function Get-CurrentModRecords {
    param(
        [string[]]$Ids
    )

    @($Ids | ForEach-Object {
        [pscustomobject]@{
            Id = $_
            Name = Get-ModName $_
        }
    })
}

function Add-ModsById {
    param(
        [string[]]$WorkingIds
    )

    $raw = Read-Host 'Introduce uno o varios IDs de CurseForge separados por comas'
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @($WorkingIds)
    }

    try {
        $ids = Parse-CommaSeparatedIds -InputText $raw
    }
    catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        Pause-ForUser
        return @($WorkingIds)
    }

    Ensure-ModNamesForIds -Ids $ids

    Write-Host ''
    foreach ($id in $ids) {
        $status = if ($WorkingIds -contains $id) { '[YA EN LISTA]' } else { '[NUEVO]' }
        Write-Host ('- {0}  {1} {2}' -f $id, (Get-ModName $id), $status)
    }

    $newIds = @($ids | Where-Object { $WorkingIds -notcontains $_ })
    if ($newIds.Count -eq 0) {
        Write-Host ''
        Write-Host 'No hay mods nuevos que anadir.' -ForegroundColor Yellow
        Pause-ForUser
        return @($WorkingIds)
    }

    if (-not (Confirm-Selection -Ids $newIds -Verb 'anadir')) {
        return @($WorkingIds)
    }

    return @(Add-Ids -WorkingIds $WorkingIds -IdsToAdd $newIds)
}

function Add-ModsByCurseForgeName {
    param(
        [string[]]$WorkingIds
    )

    try {
        [void](Get-CurseForgeApiKey)
    }
    catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        Pause-ForUser
        return @($WorkingIds)
    }

    $query = Read-Host 'Texto a buscar en CurseForge'
    if ([string]::IsNullOrWhiteSpace($query)) {
        return @($WorkingIds)
    }

    try {
        $matches = @(Search-CurseForgeMods -Query $query)
    }
    catch {
        Write-Host ("Error buscando en CurseForge: {0}" -f $_.Exception.Message) -ForegroundColor Red
        Pause-ForUser
        return @($WorkingIds)
    }

    if ($matches.Count -eq 0) {
        Write-Host 'No se encontraron mods en CurseForge con ese texto.' -ForegroundColor Yellow
        Pause-ForUser
        return @($WorkingIds)
    }

    Write-Host ''
    for ($i = 0; $i -lt $matches.Count; $i++) {
        $mod = $matches[$i]
        $status = if ($WorkingIds -contains $mod.Id) { '[YA EN LISTA]' } else { '' }
        $summary = if ([string]::IsNullOrWhiteSpace($mod.Summary)) { '' } else { $mod.Summary.Trim() }
        if ($summary.Length -gt 90) {
            $summary = $summary.Substring(0, 90) + '...'
        }
        Write-Host ('{0,2}. {1,-8} {2} {3}' -f ($i + 1), $mod.Id, $mod.Name, $status)
        if ($summary) {
            Write-Host ('    {0}' -f $summary)
        }
    }

    Write-Host ''
    $selection = Read-Host 'Elige uno o varios numeros separados por comas'
    if ([string]::IsNullOrWhiteSpace($selection)) {
        return @($WorkingIds)
    }

    try {
        $indexes = Parse-CommaSeparatedIndexes -InputText $selection -MaxIndex $matches.Count
    }
    catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        Pause-ForUser
        return @($WorkingIds)
    }

    $selectedMods = @($indexes | ForEach-Object { $matches[$_ - 1] })
    foreach ($mod in $selectedMods) {
        $script:ModNameMap[$mod.Id] = $mod.Name
    }

    $newIds = @($selectedMods | ForEach-Object { $_.Id } | Where-Object { $WorkingIds -notcontains $_ })

    if ($newIds.Count -eq 0) {
        Write-Host ''
        Write-Host 'Los mods seleccionados ya estaban en la lista.' -ForegroundColor Yellow
        Pause-ForUser
        return @($WorkingIds)
    }

    if (-not (Confirm-Selection -Ids $newIds -Verb 'anadir')) {
        return @($WorkingIds)
    }

    return @(Add-Ids -WorkingIds $WorkingIds -IdsToAdd $newIds)
}

function Add-ModsByName {
    param(
        [string[]]$WorkingIds
    )

    $query = Read-Host 'Texto a buscar en el nombre del mod ya instalado'
    if ([string]::IsNullOrWhiteSpace($query)) {
        return @($WorkingIds)
    }

    $matches = @(Search-LibraryMods -Query $query)
    if ($matches.Count -eq 0) {
        Write-Host 'No se encontraron mods con ese texto.' -ForegroundColor Yellow
        Pause-ForUser
        return @($WorkingIds)
    }

    Write-Host ''
    for ($i = 0; $i -lt $matches.Count; $i++) {
        $mod = $matches[$i]
        $status = if ($WorkingIds -contains $mod.Id) { '[YA EN LISTA]' } else { '' }
        Write-Host ('{0,2}. {1,-8} {2} {3}' -f ($i + 1), $mod.Id, $mod.Name, $status)
    }

    Write-Host ''
    $selection = Read-Host 'Elige uno o varios numeros separados por comas'
    if ([string]::IsNullOrWhiteSpace($selection)) {
        return @($WorkingIds)
    }

    try {
        $indexes = Parse-CommaSeparatedIndexes -InputText $selection -MaxIndex $matches.Count
    }
    catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        Pause-ForUser
        return @($WorkingIds)
    }

    $ids = @($indexes | ForEach-Object { $matches[$_ - 1].Id })
    $newIds = @($ids | Where-Object { $WorkingIds -notcontains $_ })

    if ($newIds.Count -eq 0) {
        Write-Host ''
        Write-Host 'Los mods seleccionados ya estaban en la lista.' -ForegroundColor Yellow
        Pause-ForUser
        return @($WorkingIds)
    }

    if (-not (Confirm-Selection -Ids $newIds -Verb 'anadir')) {
        return @($WorkingIds)
    }

    return @(Add-Ids -WorkingIds $WorkingIds -IdsToAdd $newIds)
}

function Remove-ModsById {
    param(
        [string[]]$WorkingIds
    )

    $raw = Read-Host 'Introduce uno o varios IDs separados por comas'
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @($WorkingIds)
    }

    try {
        $ids = Parse-CommaSeparatedIds -InputText $raw
    }
    catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        Pause-ForUser
        return @($WorkingIds)
    }

    $selected = @($ids | Where-Object { $WorkingIds -contains $_ })
    $missing = @($ids | Where-Object { $WorkingIds -notcontains $_ })

    Write-Host ''
    foreach ($id in $selected) {
        Write-Host ('- {0}  {1}' -f $id, (Get-ModName $id))
    }

    foreach ($id in $missing) {
        Write-Host ('- {0}  {1} [NO ESTABA EN LA LISTA]' -f $id, (Get-ModName $id))
    }

    if ($selected.Count -eq 0) {
        Write-Host ''
        Write-Host 'No hay mods validos para quitar.' -ForegroundColor Yellow
        Pause-ForUser
        return @($WorkingIds)
    }

    if (-not (Confirm-Selection -Ids $selected -Verb 'quitar')) {
        return @($WorkingIds)
    }

    return @(Remove-Ids -WorkingIds $WorkingIds -IdsToRemove $selected)
}

function Remove-ModsByName {
    param(
        [string[]]$WorkingIds
    )

    $query = Read-Host 'Texto a buscar en la lista actual'
    if ([string]::IsNullOrWhiteSpace($query)) {
        return @($WorkingIds)
    }

    $matches = @(Get-CurrentModRecords -Ids $WorkingIds | Where-Object {
        $_.Name -like ('*{0}*' -f $query) -or $_.Id -like ('*{0}*' -f $query)
    } | Sort-Object Name, Id)

    if ($matches.Count -eq 0) {
        Write-Host 'No se encontraron mods en la lista actual con ese texto.' -ForegroundColor Yellow
        Pause-ForUser
        return @($WorkingIds)
    }

    Write-Host ''
    for ($i = 0; $i -lt $matches.Count; $i++) {
        $mod = $matches[$i]
        Write-Host ('{0,2}. {1,-8} {2}' -f ($i + 1), $mod.Id, $mod.Name)
    }

    Write-Host ''
    $selection = Read-Host 'Elige uno o varios numeros separados por comas'
    if ([string]::IsNullOrWhiteSpace($selection)) {
        return @($WorkingIds)
    }

    try {
        $indexes = Parse-CommaSeparatedIndexes -InputText $selection -MaxIndex $matches.Count
    }
    catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        Pause-ForUser
        return @($WorkingIds)
    }

    $ids = @($indexes | ForEach-Object { $matches[$_ - 1].Id })

    if (-not (Confirm-Selection -Ids $ids -Verb 'quitar')) {
        return @($WorkingIds)
    }

    return @(Remove-Ids -WorkingIds $WorkingIds -IdsToRemove $ids)
}

function Show-Header {
    param(
        [string[]]$WorkingIds,
        [bool]$Dirty
    )

    $configPending = $Dirty -or -not (Test-ConfigInSync -Ids $WorkingIds)

    Clear-Host
    Write-Host 'ARK Server Creation Tool Shared Mods Manager'
    Write-Host '============================================'
    Write-Host ('Mods en lista:            {0}' -f @($WorkingIds).Count)
    Write-Host ('Cambios sin aplicar:      {0}' -f ($(if ($Dirty) { 'SI' } else { 'NO' })))
    Write-Host ('Pendiente actualizar herramienta de servidor:{0}' -f ($(if ($configPending) { ' SI' } else { ' NO' })))
    Write-Host ''
    Show-ModList -Ids $WorkingIds
    Write-SubtleSeparator -Width 72
    Write-Host ''
}

function Show-AddMenu {
    param(
        [string[]]$WorkingIds
    )

    Clear-Host
    Write-Host 'Anadir Mods'
    Write-Host '==========='
    Write-Host '1. Anadir por ID de CurseForge'
    Write-Host '2. Buscar mod en CurseForge por nombre'
    Write-Host '3. Activar mod ya instalado por nombre'
    Write-Host '4. Volver'
    Write-Host ''

    $choice = Read-Host 'Elige una opcion'
    switch ($choice) {
        '1' { return @(Add-ModsById -WorkingIds $WorkingIds) }
        '2' { return @(Add-ModsByCurseForgeName -WorkingIds $WorkingIds) }
        '3' { return @(Add-ModsByName -WorkingIds $WorkingIds) }
        default { return @($WorkingIds) }
    }
}

function Show-RemoveMenu {
    param(
        [string[]]$WorkingIds
    )

    Clear-Host
    Write-Host 'Quitar Mods'
    Write-Host '==========='
    Write-Host '1. Quitar por ID'
    Write-Host '2. Quitar por nombre'
    Write-Host '3. Volver'
    Write-Host ''

    $choice = Read-Host 'Elige una opcion'
    switch ($choice) {
        '1' { return @(Remove-ModsById -WorkingIds $WorkingIds) }
        '2' { return @(Remove-ModsByName -WorkingIds $WorkingIds) }
        default { return @($WorkingIds) }
    }
}

function Show-ExitMenu {
    param(
        [string[]]$WorkingIds,
        [bool]$Dirty
    )

    if (-not $Dirty) {
        return 'exit'
    }

    Write-Host ''
    Write-Host 'Hay cambios sin aplicar.'
    Write-Host '1. Aplicar y salir'
    Write-Host '2. Salir sin aplicar'
    Write-Host '3. Cancelar'
    Write-Host ''

    $choice = Read-Host 'Elige una opcion'
    switch ($choice) {
        '1' {
            $result = Apply-SharedModsToConfig -Ids $WorkingIds
            Write-Host ''
            Write-Host "Aplicado. Backup: $($result.BackupPath)" -ForegroundColor Green
            Pause-ForUser
            return 'exit'
        }
        '2' { return 'exit' }
        default { return 'cancel' }
    }
}

Assert-PathExists -Path $configPath -Label 'el archivo de configuracion de ARK Server Creation Tool'
Assert-PathExists -Path $sharedModsPath -Label 'la lista compartida de mods'
Assert-PathExists -Path $libraryPath -Label 'la biblioteca de mods'

$script:LibraryMods = @(Load-LibraryMods)
$script:ModNameMap = @{}
$script:ModCategoryMap = @{}
$script:CategoryOrder = @()
foreach ($item in $script:LibraryMods) {
    $script:ModNameMap[$item.Id] = $item.Name
}
Initialize-CategoryState
Merge-SharedModNamesIntoMap

$workingIds = @(Get-SharedModIds)

if ($ApplyOnly) {
    Apply-SharedModsToConfig -Ids $workingIds | ConvertTo-Json -Compress
    exit 0
}

$dirty = $false

while ($true) {
    Show-Header -WorkingIds $workingIds -Dirty $dirty

    Write-Host 'Menu principal'
    Write-Host '1. Anadir mods'
    Write-Host '2. Quitar mods'
    Write-Host '3. Aplicar / actualizar lista'
    Write-Host '4. Recargar desde archivo'
    Write-Host '5. Salir'
    Write-Host ''

    $choice = Read-Host 'Elige una opcion'
    switch ($choice) {
        '1' {
            $updated = @(Show-AddMenu -WorkingIds $workingIds)
            if (-not (Compare-IdLists -Left $workingIds -Right $updated)) {
                $workingIds = @($updated)
                $dirty = $true
            }
        }
        '2' {
            $updated = @(Show-RemoveMenu -WorkingIds $workingIds)
            if (-not (Compare-IdLists -Left $workingIds -Right $updated)) {
                $workingIds = @($updated)
                $dirty = $true
            }
        }
        '3' {
            $result = Apply-SharedModsToConfig -Ids $workingIds
            $dirty = $false
            Write-Host ''
            Write-Host "Lista aplicada correctamente. Backup: $($result.BackupPath)" -ForegroundColor Green
            Pause-ForUser
        }
        '4' {
            $workingIds = @(Get-SharedModIds)
            $dirty = $false
        }
        '5' {
            $exitAction = Show-ExitMenu -WorkingIds $workingIds -Dirty $dirty
            if ($exitAction -eq 'exit') {
                break
            }
        }
        default {
            Write-Host ''
            Write-Host 'Opcion no valida.' -ForegroundColor Yellow
            Pause-ForUser
        }
    }
}
