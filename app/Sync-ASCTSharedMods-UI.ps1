param(
    [switch]$SmokeTest
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$scriptDir = Split-Path -Parent $PSCommandPath
$localConfigPath = Join-Path $scriptDir 'ArkServerCreationToolSharedMods.local.json'
$windowSettingsPath = Join-Path $scriptDir 'ArkServerCreationToolSharedMods.settings.json'

$singleInstanceMutex = $null
if (-not $SmokeTest) {
    $createdNew = $false
    $singleInstanceMutex = [System.Threading.Mutex]::new($true, 'Local\Maglucen.ArkServerCreationToolSharedModsManager', [ref]$createdNew)
    if (-not $createdNew) {
        $singleInstanceMutex.Dispose()
        exit 0
    }
}

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
$backendScriptPath = Join-Path $scriptDir 'Sync-ASCTSharedMods.ps1'
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
    param([string]$Path,[string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) { throw "${Label} not found: $Path" }
}

function Load-LibraryMods {
    Assert-PathExists -Path $libraryPath -Label 'Mod library'
    $json = Get-Content -LiteralPath $libraryPath -Raw | ConvertFrom-Json
    $mods = foreach ($item in @($json.installedMods)) {
        if ($item.details -and $item.details.id -and -not [string]::IsNullOrWhiteSpace($item.details.name)) {
            [pscustomobject]@{ Id = [string]$item.details.id; Name = [string]$item.details.name }
        }
    }
    @($mods | Sort-Object Name, Id -Unique)
}

function Get-CurseForgeApiKey {
    if (-not [string]::IsNullOrWhiteSpace($env:CURSEFORGE_API_KEY)) { return $env:CURSEFORGE_API_KEY.Trim() }
    if (Test-Path -LiteralPath $curseForgeApiKeyPath) {
        $value = (Get-Content -LiteralPath $curseForgeApiKeyPath -Raw).Trim()
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }
    if (Test-Path -LiteralPath $curseForgeApiKeyExamplePath) {
        $lines = @((Get-Content -LiteralPath $curseForgeApiKeyExamplePath -Raw) -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object {
            $_ -and -not $_.StartsWith('#') -and $_ -ne 'YOUR_CURSEFORGE_API_KEY_HERE'
        })
        if ($lines.Count -gt 0) { return $lines[0] }
    }
    return $null
}

function Invoke-CurseForgeApi {
    param([string]$RelativePath,[hashtable]$Query = @{})
    $apiKey = Get-CurseForgeApiKey
    if ([string]::IsNullOrWhiteSpace($apiKey)) { throw "No CurseForge API key found. Save it in $curseForgeApiKeyPath" }
    $queryString = ''
    if ($Query.Count -gt 0) {
        $pairs = foreach ($key in $Query.Keys) {
            '{0}={1}' -f [System.Uri]::EscapeDataString([string]$key), [System.Uri]::EscapeDataString([string]$Query[$key])
        }
        $queryString = '?' + ($pairs -join '&')
    }
    $uri = '{0}/{1}{2}' -f $curseForgeApiBase.TrimEnd('/'), $RelativePath.TrimStart('/'), $queryString
    Invoke-RestMethod -Method Get -Uri $uri -Headers @{ 'Accept'='application/json'; 'x-api-key'=$apiKey }
}

function Get-CurseForgeModById {
    param([string]$Id)
    $normalizedId = Normalize-ModId -Id $Id
    $baseId = Get-ModBaseId -Id $normalizedId
    $response = Invoke-CurseForgeApi -RelativePath ("mods/{0}" -f $baseId)
    if ($null -eq $response.data) { return $null }
    [pscustomobject]@{
        Id = $normalizedId
        Name = [string]$response.data.name
        Summary = [string]$response.data.summary
    }
}

function Search-CurseForgeMods {
    param([string]$Query)
    $response = Invoke-CurseForgeApi -RelativePath 'mods/search' -Query @{ gameId = $curseForgeGameId; searchFilter = $Query; pageSize = 20 }
    if ($null -eq $response.data) { return @() }
    @($response.data | ForEach-Object { [pscustomobject]@{ Id = [string]$_.id; Name = [string]$_.name; Summary = [string]$_.summary } })
}

function Normalize-ModId {
    param([string]$Id)
    $trimmed = [string]$Id
    if ([string]::IsNullOrWhiteSpace($trimmed)) { throw 'ID de mod vacio.' }
    $trimmed = $trimmed.Trim()
    $match = [regex]::Match($trimmed, '^(?<base>\d+)(?<dev>-dev)?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { throw "ID no valido: $Id" }
    $baseId = [string]$match.Groups['base'].Value
    $suffix = if ($match.Groups['dev'].Success) { '-dev' } else { '' }
    ('{0}{1}' -f $baseId, $suffix)
}

function Get-ModBaseId {
    param([string]$Id)
    $normalized = Normalize-ModId -Id $Id
    ([regex]::Match($normalized, '^\d+')).Value
}

function Test-IsDevModId {
    param([string]$Id)
    (Normalize-ModId -Id $Id).EndsWith('-dev')
}

function Get-ModSortBase {
    param([string]$Id)
    [int64](Get-ModBaseId -Id $Id)
}

function Get-ModSortVariant {
    param([string]$Id)
    if (Test-IsDevModId -Id $Id) { 1 } else { 0 }
}

function Parse-SharedModEntries {
    param([string[]]$Lines)
    $entries = @()
    $seen = @{}
    $currentCategory = 'Uncategorized'
    foreach ($rawLine in $Lines) {
        $line = $rawLine.Trim()
        if (-not $line) { continue }
        if ($line.StartsWith('#')) {
            $comment = $line.TrimStart('#').Trim()
            if ($comment -and $comment -notlike 'Shared mod list*' -and $comment -notlike 'Format:*' -and $comment -notlike 'This file is managed*') {
                $currentCategory = Normalize-Category -Category $comment
            }
            continue
        }
        $match = [regex]::Match($line, '^\s*(\d+(?:-dev)?)\s*(?:#\s*(.+?)\s*)?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $match.Success) { throw "Linea no valida en ${sharedModsPath}: $rawLine" }
        $id = Normalize-ModId -Id $match.Groups[1].Value
        $baseId = Get-ModBaseId -Id $id
        if ($seen.ContainsKey($id)) { throw "ID de mod duplicado en ${sharedModsPath}: $id" }
        if ($seen.ContainsKey($baseId)) { throw "El mod base ${baseId} aparece mas de una vez en ${sharedModsPath}: $($seen[$baseId]) y $id" }
        $seen[$id] = $true
        $seen[$baseId] = $id
        $entries += [pscustomobject]@{ Id = $id; Name = [string]$match.Groups[2].Value; Category = (Normalize-Category -Category $currentCategory) }
    }
    @($entries)
}

function Normalize-Category {
    param([string]$Category)
    if ([string]::IsNullOrWhiteSpace($Category)) { return 'Uncategorized' }
    $trimmed = $Category.Trim()
    if ($legacyCategoryMap.ContainsKey($trimmed)) { return [string]$legacyCategoryMap[$trimmed] }
    return $trimmed
}

function Get-DefaultCategoryForId {
    param([string]$Id)
    $baseId = Get-ModBaseId -Id $Id
    if ($defaultCategoryMap.ContainsKey($baseId)) { return [string]$defaultCategoryMap[$baseId] }
    'Uncategorized'
}

function Get-OrderedCategoryList {
    param([object[]]$Entries)
    $categories = @($Entries | ForEach-Object { $_.Category } | Where-Object { $_ } | Select-Object -Unique)
    $ordered = @($defaultCategoryOrder | Where-Object { $categories -contains $_ })
    $extras = @($categories | Where-Object { $ordered -notcontains $_ } | Sort-Object)
    $all = @($ordered + $extras)
    if ($all -notcontains 'Uncategorized') { $all += 'Uncategorized' }
    @($all)
}

function Get-OrderedEntries {
    param([object[]]$Entries)
    $categoryOrder = Get-OrderedCategoryList -Entries $Entries
    @($Entries | Sort-Object @{
        Expression = {
            $idx = [Array]::IndexOf($categoryOrder, $_.Category)
            if ($idx -lt 0) { 999 } else { $idx }
        }
    }, @{ Expression = { $_.Name } }, @{ Expression = { Get-ModSortBase $_.Id } }, @{ Expression = { Get-ModSortVariant $_.Id } })
}

function Save-SharedModEntries {
    param([object[]]$Entries)
    $orderedEntries = Get-OrderedEntries -Entries $Entries
    $categoryOrder = Get-OrderedCategoryList -Entries $orderedEntries
    $lines = @('# Shared mod list for ARK Server Creation Tool','# Format: ID # Mod Name','# This file is managed by Sync-ASCTSharedMods.ps1','')
    foreach ($category in $categoryOrder) {
        $categoryEntries = @($orderedEntries | Where-Object { $_.Category -eq $category })
        if ($categoryEntries.Count -eq 0) { continue }
        $lines += ('# {0}' -f $category)
        foreach ($entry in $categoryEntries) { $lines += ('{0}   # {1}' -f $entry.Id, $entry.Name) }
        $lines += ''
    }
    [System.IO.File]::WriteAllLines($sharedModsPath, $lines, [System.Text.UTF8Encoding]::new($false))
}

function Parse-CommaSeparatedIds {
    param([string]$InputText)
    $parts = $InputText.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    $ids = @()
    $seen = @{}
    foreach ($part in $parts) {
        $id = Normalize-ModId -Id $part
        $baseId = Get-ModBaseId -Id $id
        if ($seen.ContainsKey($id)) { continue }
        if ($seen.ContainsKey($baseId)) { throw "El mod base ${baseId} aparece varias veces en la misma lista: $($seen[$baseId]) y $id" }
        $seen[$id] = $true
        $seen[$baseId] = $id
        $ids += [string]$id
    }
    @($ids)
}

function Compare-IdLists {
    param([string[]]$Left,[string[]]$Right)
    if (@($Left).Count -ne @($Right).Count) { return $false }
    for ($i = 0; $i -lt @($Left).Count; $i++) {
        if ([string]$Left[$i] -ne [string]$Right[$i]) { return $false }
    }
    $true
}

function Get-ModStringFromLaunchArgs {
    param([string]$LaunchArgs)
    if ([string]::IsNullOrWhiteSpace($LaunchArgs)) { return $null }
    $quoted = [regex]::Match($LaunchArgs, '"-mods=([^"]*)"')
    if ($quoted.Success) { return $quoted.Groups[1].Value }
    $plain = [regex]::Match($LaunchArgs, '\s-mods=([^\s"]+)')
    if ($plain.Success) { return $plain.Groups[1].Value }
    $null
}

function Test-ConfigInSync {
    param([object[]]$Entries)
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $expected = @((Get-OrderedEntries -Entries $Entries) | ForEach-Object { [string]$_.Id })
    $expectedBase = @($expected | ForEach-Object { Get-ModBaseId -Id $_ })
    $modsString = ($expected -join ',')
    foreach ($server in @($config.Servers)) {
        $serverIds = @($server.modIDs | ForEach-Object { [string]$_ })
        if (-not (Compare-IdLists -Left $expectedBase -Right $serverIds)) { return $false }
        if ($server.useCustomLaunchArgs -and $server.customLaunchArgs) {
            if ((Get-ModStringFromLaunchArgs -LaunchArgs $server.customLaunchArgs) -ne $modsString) { return $false }
        }
    }
    $true
}

function Invoke-BackendApply {
    $raw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $backendScriptPath -ApplyOnly 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw ($raw.Trim()) }
    $trimmed = $raw.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return $null }
    $trimmed | ConvertFrom-Json
}

function Test-WindowBoundsVisible {
    param(
        [double]$Left,
        [double]$Top,
        [double]$Width,
        [double]$Height
    )

    $virtualLeft = [System.Windows.SystemParameters]::VirtualScreenLeft
    $virtualTop = [System.Windows.SystemParameters]::VirtualScreenTop
    $virtualRight = $virtualLeft + [System.Windows.SystemParameters]::VirtualScreenWidth
    $virtualBottom = $virtualTop + [System.Windows.SystemParameters]::VirtualScreenHeight

    $right = $Left + [Math]::Max(120, $Width)
    $bottom = $Top + [Math]::Max(120, $Height)

    return (
        $right -gt $virtualLeft -and
        $bottom -gt $virtualTop -and
        $Left -lt $virtualRight -and
        $Top -lt $virtualBottom
    )
}

function Restore-WindowPlacement {
    param([System.Windows.Window]$Window)

    if (-not (Test-Path -LiteralPath $windowSettingsPath)) {
        return
    }

    try {
        $settings = Get-Content -LiteralPath $windowSettingsPath -Raw | ConvertFrom-Json
        if (
            $null -eq $settings.left -or
            $null -eq $settings.top -or
            $null -eq $settings.width -or
            $null -eq $settings.height
        ) {
            return
        }

        $left = [double]$settings.left
        $top = [double]$settings.top
        $width = [Math]::Max([double]$settings.width, $Window.MinWidth)
        $height = [Math]::Max([double]$settings.height, $Window.MinHeight)

        if (-not (Test-WindowBoundsVisible -Left $left -Top $top -Width $width -Height $height)) {
            return
        }

        $Window.WindowStartupLocation = 'Manual'
        $Window.Left = $left
        $Window.Top = $top
        $Window.Width = $width
        $Window.Height = $height

        if ([string]$settings.windowState -eq 'Maximized') {
            $Window.WindowState = 'Maximized'
        }
    }
    catch {
        Add-Log ("Could not restore window placement: {0}" -f $_.Exception.Message)
    }
}

function Save-WindowPlacement {
    param([System.Windows.Window]$Window)

    try {
        $bounds = if ($Window.WindowState -eq 'Normal') { $Window } else { $Window.RestoreBounds }
        $settings = [ordered]@{
            left = [double]$bounds.Left
            top = [double]$bounds.Top
            width = [double]$bounds.Width
            height = [double]$bounds.Height
            windowState = [string]$Window.WindowState
        }

        $settings |
            ConvertTo-Json -Depth 3 |
            Set-Content -LiteralPath $windowSettingsPath -Encoding UTF8
    }
    catch {
        Add-Log ("Could not save window placement: {0}" -f $_.Exception.Message)
    }
}

$libraryMods = @(Load-LibraryMods)
$libraryModNameMap = @{}
foreach ($mod in $libraryMods) { $libraryModNameMap[$mod.Id] = $mod.Name }

$entries = @(Parse-SharedModEntries -Lines (Get-Content -LiteralPath $sharedModsPath))
foreach ($entry in $entries) {
    $baseId = Get-ModBaseId -Id $entry.Id
    if ([string]::IsNullOrWhiteSpace($entry.Name) -and $libraryModNameMap.ContainsKey($baseId)) { $entry.Name = $libraryModNameMap[$baseId] }
    if ([string]::IsNullOrWhiteSpace($entry.Category)) { $entry.Category = Get-DefaultCategoryForId -Id $entry.Id }
}

$state = [ordered]@{
    Entries = @($entries)
    SearchResults = @()
    LibraryMods = @($libraryMods)
    Dirty = $false
    Log = @()
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="ARK Server Creation Tool Shared Mods Manager" Width="1520" Height="940" MinWidth="1240" MinHeight="800" Background="#0F1117" Foreground="#E6EAF2" WindowStartupLocation="CenterScreen" FontFamily="Segoe UI" UseLayoutRounding="True" SnapsToDevicePixels="True">
  <Window.Resources>
    <SolidColorBrush x:Key="PanelBrush" Color="#171A22"/>
    <SolidColorBrush x:Key="PanelAltBrush" Color="#11141B"/>
    <SolidColorBrush x:Key="AccentBrush" Color="#33D1C6"/>
    <SolidColorBrush x:Key="BorderBrushDark" Color="#2A3242"/>
    <SolidColorBrush x:Key="MutedTextBrush" Color="#9CA7BA"/>
    <SolidColorBrush x:Key="ControlBrush" Color="#10151D"/>
    <SolidColorBrush x:Key="ControlAltBrush" Color="#141B26"/>
    <SolidColorBrush x:Key="SelectionBrush" Color="#214D56"/>
    <Style TargetType="Border"><Setter Property="CornerRadius" Value="14"/><Setter Property="BorderBrush" Value="{StaticResource BorderBrushDark}"/><Setter Property="BorderThickness" Value="1"/></Style>
    <Style TargetType="TextBlock"><Setter Property="Foreground" Value="#E6EAF2"/></Style>
    <Style TargetType="Button"><Setter Property="Margin" Value="0,0,10,0"/><Setter Property="Padding" Value="14,10"/><Setter Property="Background" Value="#1E2430"/><Setter Property="Foreground" Value="#EDF2F7"/><Setter Property="BorderBrush" Value="{StaticResource BorderBrushDark}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Cursor" Value="Hand"/></Style>
    <Style x:Key="AccentButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}"><Setter Property="Background" Value="{StaticResource AccentBrush}"/><Setter Property="Foreground" Value="#07161A"/><Setter Property="BorderBrush" Value="#52E6DB"/></Style>
    <Style TargetType="TextBox"><Setter Property="Background" Value="{StaticResource ControlBrush}"/><Setter Property="Foreground" Value="#E6EAF2"/><Setter Property="CaretBrush" Value="#E6EAF2"/><Setter Property="BorderBrush" Value="{StaticResource BorderBrushDark}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="10,8"/><Setter Property="Margin" Value="0,0,10,0"/><Setter Property="FontSize" Value="14"/></Style>
    <Style x:Key="DarkComboToggleButton" TargetType="ToggleButton"><Setter Property="OverridesDefaultStyle" Value="True"/><Setter Property="Focusable" Value="False"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ToggleButton"><Border x:Name="ToggleRoot" Background="Transparent"><ContentPresenter/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ToggleRoot" Property="Opacity" Value="0.98"/></Trigger><Trigger Property="IsChecked" Value="True"><Setter TargetName="ToggleRoot" Property="Opacity" Value="1"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
    <Style x:Key="DarkComboBoxItemStyle" TargetType="ComboBoxItem"><Setter Property="Background" Value="{StaticResource ControlAltBrush}"/><Setter Property="Foreground" Value="#EEF3FB"/><Setter Property="TextElement.Foreground" Value="#EEF3FB"/><Setter Property="Padding" Value="14,10"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="VerticalContentAlignment" Value="Center"/><Setter Property="SnapsToDevicePixels" Value="True"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBoxItem"><Border x:Name="ItemBorder" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}" CornerRadius="8" Margin="6,3"><ContentPresenter VerticalAlignment="Center" HorizontalAlignment="Left" TextElement.Foreground="{TemplateBinding Foreground}"/></Border><ControlTemplate.Triggers><Trigger Property="IsHighlighted" Value="True"><Setter TargetName="ItemBorder" Property="Background" Value="#1D2B3A"/></Trigger><Trigger Property="IsSelected" Value="True"><Setter TargetName="ItemBorder" Property="Background" Value="{StaticResource SelectionBrush}"/><Setter Property="Foreground" Value="#F8FCFF"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.55"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
    <Style TargetType="ComboBox"><Setter Property="Background" Value="{StaticResource ControlBrush}"/><Setter Property="Foreground" Value="#EEF3FB"/><Setter Property="TextElement.Foreground" Value="#EEF3FB"/><Setter Property="BorderBrush" Value="{StaticResource BorderBrushDark}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="10,8"/><Setter Property="Margin" Value="0,0,10,0"/><Setter Property="FontSize" Value="14"/><Setter Property="MinHeight" Value="42"/><Setter Property="ScrollViewer.HorizontalScrollBarVisibility" Value="Disabled"/><Setter Property="ItemContainerStyle" Value="{StaticResource DarkComboBoxItemStyle}"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBox"><Grid><ToggleButton x:Name="DropDownToggle" Style="{StaticResource DarkComboToggleButton}" Focusable="False" IsChecked="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"><Border x:Name="OuterBorder" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="10"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="42"/></Grid.ColumnDefinitions><ContentPresenter Margin="14,7,10,7" VerticalAlignment="Center" HorizontalAlignment="Left" Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}" TextElement.Foreground="{TemplateBinding Foreground}"/><Border x:Name="ArrowHost" Grid.Column="1" Background="#151D28" BorderBrush="#263244" BorderThickness="1,0,0,0" CornerRadius="0,10,10,0"><Path x:Name="ArrowIcon" Data="M 0 0 L 5 5 L 10 0 Z" Fill="#C8D2E3" Stretch="None" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border></Grid></Border></ToggleButton><Popup x:Name="PART_Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Fade"><Border x:Name="PopupBorder" Margin="0,6,0,0" MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}" Background="{StaticResource ControlBrush}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="10" Padding="4"><ScrollViewer MaxHeight="280" Background="{StaticResource ControlBrush}" CanContentScroll="True"><ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained"/></ScrollViewer></Border></Popup></Grid><ControlTemplate.Triggers><Trigger Property="IsKeyboardFocusWithin" Value="True"><Setter TargetName="OuterBorder" Property="BorderBrush" Value="#52E6DB"/></Trigger><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="OuterBorder" Property="BorderBrush" Value="#3E536D"/></Trigger><Trigger Property="IsDropDownOpen" Value="True"><Setter TargetName="OuterBorder" Property="BorderBrush" Value="#52E6DB"/><Setter TargetName="OuterBorder" Property="Background" Value="#151B25"/><Setter TargetName="ArrowHost" Property="Background" Value="#192231"/><Setter TargetName="PopupBorder" Property="BorderBrush" Value="#52E6DB"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.6"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
    <Style TargetType="DataGrid"><Setter Property="Background" Value="#11161F"/><Setter Property="Foreground" Value="#E6EAF2"/><Setter Property="BorderBrush" Value="{StaticResource BorderBrushDark}"/><Setter Property="BorderThickness" Value="0"/><Setter Property="GridLinesVisibility" Value="Horizontal"/><Setter Property="HorizontalGridLinesBrush" Value="#222A38"/><Setter Property="VerticalGridLinesBrush" Value="#11161F"/><Setter Property="CanUserAddRows" Value="False"/><Setter Property="CanUserDeleteRows" Value="False"/><Setter Property="CanUserResizeRows" Value="False"/><Setter Property="SelectionMode" Value="Extended"/><Setter Property="SelectionUnit" Value="FullRow"/></Style>
    <Style TargetType="DataGridColumnHeader"><Setter Property="Background" Value="#1B2230"/><Setter Property="Foreground" Value="#9CA7BA"/><Setter Property="BorderBrush" Value="#1B2230"/><Setter Property="Padding" Value="10,8"/><Setter Property="FontWeight" Value="SemiBold"/></Style>
    <Style TargetType="DataGridRow"><Setter Property="Background" Value="{StaticResource ControlBrush}"/><Setter Property="Foreground" Value="#E6EAF2"/><Setter Property="BorderBrush" Value="#222A38"/><Setter Property="BorderThickness" Value="0"/><Style.Triggers><Trigger Property="IsSelected" Value="True"><Setter Property="Background" Value="{StaticResource SelectionBrush}"/><Setter Property="Foreground" Value="#F6FBFF"/></Trigger></Style.Triggers></Style>
    <Style TargetType="DataGridCell"><Setter Property="Background" Value="{StaticResource ControlBrush}"/><Setter Property="Foreground" Value="#E6EAF2"/><Setter Property="BorderBrush" Value="#222A38"/><Setter Property="BorderThickness" Value="0,0,0,1"/><Setter Property="Padding" Value="8,6"/><Style.Triggers><Trigger Property="IsSelected" Value="True"><Setter Property="Background" Value="{StaticResource SelectionBrush}"/><Setter Property="Foreground" Value="#F6FBFF"/></Trigger></Style.Triggers></Style>
  </Window.Resources>
  <Grid Margin="20">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <Grid Grid.Row="0" Margin="0,0,0,18"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel><TextBlock Text="ARK Server Creation Tool Shared Mods Manager" FontSize="30" FontWeight="Bold"/><TextBlock Text="Visual manager for the cluster's shared mod list" Foreground="{StaticResource MutedTextBrush}" Margin="0,6,0,0"/></StackPanel><Button x:Name="OpenSharedButton" Grid.Column="1" Style="{StaticResource AccentButton}" Content="Open SharedModIDs.txt" Margin="20,0,0,0"/></Grid>
    <Grid Grid.Row="1" Margin="0,0,0,18"><Grid.ColumnDefinitions><ColumnDefinition Width="1*"/><ColumnDefinition Width="1*"/><ColumnDefinition Width="1*"/></Grid.ColumnDefinitions><Border Grid.Column="0" Background="{StaticResource PanelBrush}" Margin="0,0,14,0" Padding="18"><StackPanel><TextBlock Text="Mods in list" Foreground="{StaticResource MutedTextBrush}"/><TextBlock x:Name="ModsCountText" FontSize="28" FontWeight="Bold" Margin="0,6,0,0"/></StackPanel></Border><Border Grid.Column="1" Background="{StaticResource PanelBrush}" Margin="0,0,14,0" Padding="18"><StackPanel><TextBlock Text="Unapplied changes" Foreground="{StaticResource MutedTextBrush}"/><TextBlock x:Name="DirtyStateText" FontSize="28" FontWeight="Bold" Margin="0,6,0,0"/></StackPanel></Border><Border Grid.Column="2" Background="{StaticResource PanelBrush}" Padding="18"><StackPanel><TextBlock Text="Server tool synced" Foreground="{StaticResource MutedTextBrush}"/><TextBlock x:Name="SyncStateText" FontSize="28" FontWeight="Bold" Margin="0,6,0,0"/></StackPanel></Border></Grid>
    <Grid Grid.Row="2"><Grid.ColumnDefinitions><ColumnDefinition Width="1.85*"/><ColumnDefinition Width="1.4*"/></Grid.ColumnDefinitions>
      <Border Grid.Column="0" Background="{StaticResource PanelBrush}" Padding="18" Margin="0,0,16,0"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><StackPanel Grid.Row="0" Margin="0,0,0,14"><TextBlock Text="Shared list" FontSize="20" FontWeight="Bold"/><TextBlock Text="Active mods across all servers" Foreground="{StaticResource MutedTextBrush}" Margin="0,6,0,0"/></StackPanel><DockPanel Grid.Row="1" Margin="0,0,0,14"><TextBox x:Name="CurrentFilterTextBox" Width="260"/><Button x:Name="ReloadButton" Content="Reload from file" DockPanel.Dock="Right"/></DockPanel><DataGrid x:Name="CurrentModsGrid" Grid.Row="2" AutoGenerateColumns="False" Margin="0,0,0,14"><DataGrid.Columns><DataGridTextColumn Header="Category" Binding="{Binding Category}" Width="200"/><DataGridTextColumn Header="ID" Binding="{Binding Id}" Width="110"/><DataGridTextColumn Header="Name" Binding="{Binding Name}" Width="*"/></DataGrid.Columns></DataGrid><StackPanel Grid.Row="3" Orientation="Horizontal"><ComboBox x:Name="MoveCategoryCombo" Width="220"/><Button x:Name="MoveCategoryButton" Content="Change category"/><Button x:Name="RemoveSelectedButton" Content="Remove selected"/></StackPanel></Grid></Border>
      <Grid Grid.Column="1"><Grid.RowDefinitions><RowDefinition Height="1.7*"/><RowDefinition Height="10"/><RowDefinition Height="0.95*"/></Grid.RowDefinitions>
        <Border Grid.Row="0" Background="{StaticResource PanelBrush}" Padding="18" Margin="0,0,0,0" MinHeight="360"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><StackPanel Grid.Row="0" Margin="0,0,0,14"><TextBlock Text="Search and add" FontSize="20" FontWeight="Bold"/><TextBlock Text="Search in CurseForge or your local library" Foreground="{StaticResource MutedTextBrush}" Margin="0,6,0,0"/></StackPanel><Grid Grid.Row="1" Margin="0,0,0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="160"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><ComboBox x:Name="SearchSourceCombo" Grid.Column="0"/><TextBox x:Name="SearchTextBox" Grid.Column="1"/><Button x:Name="SearchButton" Grid.Column="2" Content="Search" Style="{StaticResource AccentButton}" Margin="0"/></Grid><Grid Grid.Row="2" Margin="0,0,0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="170"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBox x:Name="AddByIdTextBox" Grid.Column="0"/><ComboBox x:Name="AddCategoryCombo" Grid.Column="1"/><Button x:Name="AddByIdButton" Grid.Column="2" Content="Add by ID" Margin="0"/></Grid><DataGrid x:Name="SearchResultsGrid" Grid.Row="3" AutoGenerateColumns="False" Margin="0,0,0,12" MinHeight="220" RowHeight="30"><DataGrid.Columns><DataGridTextColumn Header="ID" Binding="{Binding Id}" Width="90"/><DataGridTextColumn Header="Name" Binding="{Binding Name}" Width="200"/><DataGridTextColumn Header="Summary" Binding="{Binding Summary}" Width="*"/></DataGrid.Columns></DataGrid><Button x:Name="AddSelectedButton" Grid.Row="4" Content="Add selected" Style="{StaticResource AccentButton}"/></Grid></Border>
        <GridSplitter Grid.Row="1" Height="10" HorizontalAlignment="Stretch" VerticalAlignment="Center" ResizeDirection="Rows" ResizeBehavior="PreviousAndNext" Background="#1F2734"/>
        <Border Grid.Row="2" Background="{StaticResource PanelAltBrush}" Padding="18" MinHeight="180"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions><StackPanel Grid.Row="0" Margin="0,0,0,14"><TextBlock Text="Apply changes" FontSize="20" FontWeight="Bold"/><TextBlock Text="Save the shared list and sync ARK Server Creation Tool" Foreground="{StaticResource MutedTextBrush}" Margin="0,6,0,0"/></StackPanel><Button x:Name="ApplyButton" Grid.Row="1" Content="Apply to server tool" Style="{StaticResource AccentButton}" Margin="0,0,0,12"/><TextBox x:Name="LogTextBox" Grid.Row="2" Margin="0" IsReadOnly="True" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"/></Grid></Border>
      </Grid>
    </Grid>
    <TextBlock Grid.Row="3" Margin="0,16,0,0" Foreground="{StaticResource MutedTextBrush}" Text="Tip: console manager is available at app\Open Console Manager.cmd"/>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

function Get-Control {
    param([string]$Name)
    $control = $window.FindName($Name)
    if ($null -eq $control) { throw "Control not found: $Name" }
    $control
}

$modsCountText = Get-Control 'ModsCountText'
$dirtyStateText = Get-Control 'DirtyStateText'
$syncStateText = Get-Control 'SyncStateText'
$currentFilterTextBox = Get-Control 'CurrentFilterTextBox'
$currentModsGrid = Get-Control 'CurrentModsGrid'
$moveCategoryCombo = Get-Control 'MoveCategoryCombo'
$moveCategoryButton = Get-Control 'MoveCategoryButton'
$removeSelectedButton = Get-Control 'RemoveSelectedButton'
$reloadButton = Get-Control 'ReloadButton'
$searchSourceCombo = Get-Control 'SearchSourceCombo'
$searchTextBox = Get-Control 'SearchTextBox'
$searchButton = Get-Control 'SearchButton'
$addByIdTextBox = Get-Control 'AddByIdTextBox'
$addCategoryCombo = Get-Control 'AddCategoryCombo'
$addByIdButton = Get-Control 'AddByIdButton'
$searchResultsGrid = Get-Control 'SearchResultsGrid'
$addSelectedButton = Get-Control 'AddSelectedButton'
$applyButton = Get-Control 'ApplyButton'
$openSharedButton = Get-Control 'OpenSharedButton'
$logTextBox = Get-Control 'LogTextBox'

function Show-Info { param([string]$Message) [System.Windows.MessageBox]::Show($window,$Message,'ARK Server Creation Tool Shared Mods Manager','OK','Information') | Out-Null }
function Show-Error { param([string]$Message) [System.Windows.MessageBox]::Show($window,$Message,'ARK Server Creation Tool Shared Mods Manager','OK','Error') | Out-Null }
function Confirm-Action { param([string]$Message,[string]$Title='Confirm') ([System.Windows.MessageBox]::Show($window,$Message,$Title,'YesNo','Question') -eq 'Yes') }

function Add-Log {
    param([string]$Message)
    $state.Log += ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message)
    $logTextBox.Text = ($state.Log -join [Environment]::NewLine)
    $logTextBox.ScrollToEnd()
}

function Get-CategoryChoices {
    $all = @($defaultCategoryOrder)
    foreach ($category in @($state.Entries | ForEach-Object { $_.Category } | Where-Object { $_ } | Select-Object -Unique)) {
        if ($all -notcontains $category) { $all += $category }
    }
    if ($all -notcontains 'Uncategorized') { $all += 'Uncategorized' }
    @($all)
}

function Refresh-CategoryCombos {
    $categories = Get-CategoryChoices
    $moveCategoryCombo.ItemsSource = $categories
    $addCategoryCombo.ItemsSource = $categories
    if (-not $moveCategoryCombo.SelectedItem) { $moveCategoryCombo.SelectedItem = 'Uncategorized' }
    if (-not $addCategoryCombo.SelectedItem) { $addCategoryCombo.SelectedItem = 'Uncategorized' }
}

function Refresh-CurrentModsView {
    $filterText = $currentFilterTextBox.Text.Trim().ToLowerInvariant()
    $rows = @(Get-OrderedEntries -Entries $state.Entries)
    if ($filterText) {
        $rows = @($rows | Where-Object {
            $_.Name.ToLowerInvariant().Contains($filterText) -or
            $_.Id.ToLowerInvariant().Contains($filterText) -or
            $_.Category.ToLowerInvariant().Contains($filterText)
        })
    }
    $currentModsGrid.ItemsSource = $rows
}

function Refresh-SearchResultsView { $searchResultsGrid.ItemsSource = @($state.SearchResults) }

function Refresh-Status {
    $modsCountText.Text = [string]@($state.Entries).Count
    $dirtyStateText.Text = if ($state.Dirty) { 'YES' } else { 'NO' }
    $dirtyStateText.Foreground = if ($state.Dirty) { '#F6C177' } else { '#8BD5CA' }
    $inSync = $false
    try { $inSync = Test-ConfigInSync -Entries $state.Entries } catch { Add-Log ("Could not verify sync status: {0}" -f $_.Exception.Message) }
    if ($state.Dirty) { $syncStateText.Text = 'PENDING'; $syncStateText.Foreground = '#F6C177' }
    elseif ($inSync) { $syncStateText.Text = 'YES'; $syncStateText.Foreground = '#8BD5CA' }
    else { $syncStateText.Text = 'NO'; $syncStateText.Foreground = '#E67E80' }
}

function Refresh-All { Refresh-CategoryCombos; Refresh-CurrentModsView; Refresh-SearchResultsView; Refresh-Status }

function Set-Dirty {
    param([bool]$Value)
    $state.Dirty = $Value
    Refresh-Status
}

function Add-ModEntry {
    param([string]$Id,[string]$Name,[string]$Category)
    $normalizedId = Normalize-ModId -Id $Id
    $baseId = Get-ModBaseId -Id $normalizedId
    $existingVariant = @($state.Entries | Where-Object { (Get-ModBaseId -Id $_.Id) -eq $baseId } | Select-Object -First 1)
    if ($existingVariant.Count -gt 0 -and [string]$existingVariant[0].Id -eq $normalizedId) { Add-Log ("Mod {0} is already in the list." -f $normalizedId); return }
    if ($existingVariant.Count -gt 0) {
        $state.Entries = @($state.Entries | Where-Object { (Get-ModBaseId -Id $_.Id) -ne $baseId })
        Add-Log ("Replaced {0} with {1}" -f $existingVariant[0].Id, $normalizedId)
    }
    $resolvedCategory = if ([string]::IsNullOrWhiteSpace($Category)) { Get-DefaultCategoryForId -Id $normalizedId } else { $Category }
    $resolvedName = if ([string]::IsNullOrWhiteSpace($Name) -and $libraryModNameMap.ContainsKey($baseId)) { $libraryModNameMap[$baseId] } else { $Name }
    if ([string]::IsNullOrWhiteSpace($resolvedName)) { $resolvedName = '(Unknown mod)' }
    $state.Entries += [pscustomobject]@{ Id = [string]$normalizedId; Name = [string]$resolvedName; Category = [string]$resolvedCategory }
    Add-Log ("Added {0} ({1}) to {2}" -f $resolvedName, $normalizedId, $resolvedCategory)
    Set-Dirty -Value $true
    Refresh-All
}

function Search-InstalledMods {
    param([string]$Query)
    $pattern = $Query.Trim().ToLowerInvariant()
    @($state.LibraryMods | Where-Object { $_.Name.ToLowerInvariant().Contains($pattern) -or $_.Id.ToLowerInvariant().Contains($pattern) } | Sort-Object Name, Id | ForEach-Object {
        [pscustomobject]@{ Id = $_.Id; Name = $_.Name; Summary = 'Local library' }
    })
}

function Reload-FromFile {
    $reloaded = @(Parse-SharedModEntries -Lines (Get-Content -LiteralPath $sharedModsPath))
    foreach ($entry in $reloaded) {
        $baseId = Get-ModBaseId -Id $entry.Id
        if ([string]::IsNullOrWhiteSpace($entry.Name) -and $libraryModNameMap.ContainsKey($baseId)) { $entry.Name = $libraryModNameMap[$baseId] }
        if ([string]::IsNullOrWhiteSpace($entry.Category)) { $entry.Category = Get-DefaultCategoryForId -Id $entry.Id }
    }
    $state.Entries = @($reloaded)
    $state.SearchResults = @()
    Set-Dirty -Value $false
    Add-Log 'Reloaded from SharedModIDs.txt'
    Refresh-All
}

$currentFilterTextBox.Text = ''
$searchSourceCombo.ItemsSource = @('CurseForge','Installed')
$searchSourceCombo.SelectedIndex = 0
$searchTextBox.Text = ''
$addByIdTextBox.Text = ''
Refresh-All
Add-Log 'Application ready.'
Restore-WindowPlacement -Window $window

$window.Add_Closing({
    Save-WindowPlacement -Window $window
    if ($null -ne $singleInstanceMutex) {
        $singleInstanceMutex.ReleaseMutex()
        $singleInstanceMutex.Dispose()
    }
})

$searchButton.Add_Click({
    try {
        $query = $searchTextBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($query)) { Show-Info 'Enter a search term.'; return }
        if ($searchSourceCombo.SelectedItem -eq 'Installed') {
            $state.SearchResults = @(Search-InstalledMods -Query $query)
            Add-Log ("Local library search: {0} results" -f @($state.SearchResults).Count)
        } else {
            $state.SearchResults = @(Search-CurseForgeMods -Query $query)
            Add-Log ("CurseForge search: {0} results" -f @($state.SearchResults).Count)
        }
        Refresh-SearchResultsView
    } catch { Show-Error $_.Exception.Message; Add-Log ("Error searching mods: {0}" -f $_.Exception.Message) }
})

$searchTextBox.Add_KeyDown({
    if ($_.Key -eq 'Return') {
        $searchButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    }
})

$addByIdButton.Add_Click({
    try {
        $ids = @(Parse-CommaSeparatedIds -InputText $addByIdTextBox.Text)
        if ($ids.Count -eq 0) { Show-Info 'Enter one or more IDs separated by commas.'; return }
        $mods = @(); foreach ($id in $ids) { $mods += Get-CurseForgeModById -Id $id }
        $label = @($mods | ForEach-Object { '- {0} ({1})' -f $_.Name, $_.Id }) -join [Environment]::NewLine
        if (-not (Confirm-Action -Message ("These mods will be added:`n`n{0}" -f $label) -Title 'Confirm add')) { return }
        $selectedCategory = [string]$addCategoryCombo.SelectedItem
        foreach ($mod in $mods) {
            $category = if ($selectedCategory -eq 'Uncategorized') { Get-DefaultCategoryForId -Id $mod.Id } else { $selectedCategory }
            Add-ModEntry -Id $mod.Id -Name $mod.Name -Category $category
        }
        $addByIdTextBox.Clear()
    } catch { Show-Error $_.Exception.Message; Add-Log ("Error adding by ID: {0}" -f $_.Exception.Message) }
})

$addSelectedButton.Add_Click({
    try {
        $selected = @($searchResultsGrid.SelectedItems)
        if ($selected.Count -eq 0) { Show-Info 'Select one or more mods in the results.'; return }
        $selectedCategory = [string]$addCategoryCombo.SelectedItem
        foreach ($item in $selected) {
            $category = if ($selectedCategory -eq 'Uncategorized') { Get-DefaultCategoryForId -Id $item.Id } else { $selectedCategory }
            Add-ModEntry -Id $item.Id -Name $item.Name -Category $category
        }
    } catch { Show-Error $_.Exception.Message; Add-Log ("Error adding selected mods: {0}" -f $_.Exception.Message) }
})

$removeSelectedButton.Add_Click({
    $selected = @($currentModsGrid.SelectedItems)
    if ($selected.Count -eq 0) { Show-Info 'Select one or more mods in the current list.'; return }
    $label = @($selected | ForEach-Object { '- {0} ({1})' -f $_.Name, $_.Id }) -join [Environment]::NewLine
    if (-not (Confirm-Action -Message ("These mods will be removed:`n`n{0}" -f $label) -Title 'Confirm removal')) { return }
    $idsToRemove = @($selected | ForEach-Object { $_.Id })
    $state.Entries = @($state.Entries | Where-Object { $idsToRemove -notcontains $_.Id })
    Add-Log ("Removed {0} mods from the list." -f $idsToRemove.Count)
    Set-Dirty -Value $true
    Refresh-All
})

$moveCategoryButton.Add_Click({
    $selected = @($currentModsGrid.SelectedItems)
    if ($selected.Count -eq 0) { Show-Info 'Select one or more mods in the current list.'; return }
    $targetCategory = [string]$moveCategoryCombo.SelectedItem
    foreach ($entry in $state.Entries) {
        if ($selected.Id -contains $entry.Id) { $entry.Category = $targetCategory }
    }
    Add-Log ("Changed category for {0} mods to {1}" -f $selected.Count, $targetCategory)
    Set-Dirty -Value $true
    Refresh-All
})

$reloadButton.Add_Click({
    if ($state.Dirty -and -not (Confirm-Action -Message 'There are unapplied changes. They will be lost if you reload from file. Continue?' -Title 'Reload')) { return }
    try { Reload-FromFile } catch { Show-Error $_.Exception.Message; Add-Log ("Error reloading list: {0}" -f $_.Exception.Message) }
})

$applyButton.Add_Click({
    try {
        if (-not $state.Dirty -and (Test-ConfigInSync -Entries $state.Entries)) { Show-Info 'There are no pending changes.'; return }
        if (-not (Confirm-Action -Message 'SharedModIDs.txt will be saved and ARK Server Creation Tool will be synced for all servers. Continue?' -Title 'Apply changes')) { return }
        Save-SharedModEntries -Entries $state.Entries
        $result = Invoke-BackendApply
        $state.Entries = @(Parse-SharedModEntries -Lines (Get-Content -LiteralPath $sharedModsPath))
        foreach ($entry in $state.Entries) {
            $baseId = Get-ModBaseId -Id $entry.Id
            if ([string]::IsNullOrWhiteSpace($entry.Name) -and $libraryModNameMap.ContainsKey($baseId)) { $entry.Name = $libraryModNameMap[$baseId] }
            if ([string]::IsNullOrWhiteSpace($entry.Category)) { $entry.Category = Get-DefaultCategoryForId -Id $entry.Id }
        }
        Set-Dirty -Value $false
        Refresh-All
        if ($result) { Add-Log ("Sync applied. Backup: {0}" -f $result.BackupPath) } else { Add-Log 'Sync applied.' }
        Show-Info 'Changes applied successfully.'
    } catch { Show-Error $_.Exception.Message; Add-Log ("Error applying changes: {0}" -f $_.Exception.Message) }
})

$currentFilterTextBox.Add_TextChanged({ Refresh-CurrentModsView })
$openSharedButton.Add_Click({ Start-Process notepad.exe $sharedModsPath | Out-Null })

if ($SmokeTest) {
    Write-Output 'SmokeTest: OK'
    exit 0
}

[void]$window.ShowDialog()
