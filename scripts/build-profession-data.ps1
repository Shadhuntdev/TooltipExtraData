[CmdletBinding()]
param(
    # Builds de wago.tools. Si se omiten, se usa la última build de cada producto.
    [string]$RetailBuild = "",
    [string]$ForeverBuild = "",

    [string]$OutputDir = "Data",

    [string]$CacheDir = (Join-Path $env:TEMP "TooltipExtraData-db2"),

    [switch]$NoCache
)

# Genera Data/ProfessionData_Retail.lua y Data/ProfessionData_Forever.lua:
# itemID -> máscara de bits con las profesiones que lo usan como reagente en alguna receta.
#
# Fuentes (tablas DB2 exportadas por wago.tools):
#   SkillLine, SkillLineAbility                -> receta (spell) -> profesión
#   SpellReagents                              -> reagentes clásicos de la receta
#   ModifiedCraftingSpellSlot, MCRSlotXMCRCategory,
#   CraftingReagentQuality, ModifiedCraftingItem,
#   ModifiedCraftingReagentItem                -> reagentes del sistema de crafteo moderno (solo Retail)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Bits fijos para todas las versiones. Deben coincidir con PROFESSION_ORDER en TooltipExtraData.lua.
$Professions = [ordered]@{
    171 = 0x0001  # Alchemy
    164 = 0x0002  # Blacksmithing
    333 = 0x0004  # Enchanting
    202 = 0x0008  # Engineering
    182 = 0x0010  # Herbalism
    773 = 0x0020  # Inscription
    755 = 0x0040  # Jewelcrafting
    165 = 0x0080  # Leatherworking
    186 = 0x0100  # Mining
    393 = 0x0200  # Skinning
    197 = 0x0400  # Tailoring
    185 = 0x0800  # Cooking
    356 = 0x1000  # Fishing
    129 = 0x2000  # First Aid
}

# Copia sin orden para buscar por ID: en un [ordered] un índice [int] es posicional.
$ProfessionBits = @{}
foreach ($id in $Professions.Keys) { $ProfessionBits[[int]$id] = [int]$Professions[[object]$id] }

$Targets = @(
    @{ Name = "Retail";  Product = "wow";  Build = $RetailBuild },
    @{ Name = "Forever"; Product = "wowf"; Build = $ForeverBuild }
)

function Get-ProjectRoot {
    return Split-Path -Parent $PSScriptRoot
}

function Resolve-Build {
    param([string]$Product, [string]$Build)

    if ($Build) { return $Build }

    $builds = Invoke-RestMethod -Uri "https://wago.tools/api/builds" -UseBasicParsing
    $list = $builds.$Product
    if (-not $list) {
        throw "wago.tools no devuelve builds para el producto '$Product'."
    }
    return $list[0].version
}

# Descarga una tabla como CSV. Devuelve $null si la tabla no existe en esa build.
function Get-Table {
    param([string]$Table, [string]$Build)

    $dir = Join-Path $CacheDir $Build
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }

    $file = Join-Path $dir "$Table.csv"
    $missing = Join-Path $dir "$Table.missing"

    if ($NoCache -or -not ((Test-Path -LiteralPath $file) -or (Test-Path -LiteralPath $missing))) {
        $url = "https://wago.tools/db2/$Table/csv?build=$Build"
        try {
            Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing | Out-Null
            Remove-Item -LiteralPath $missing -ErrorAction SilentlyContinue
        }
        catch {
            $status = $null
            if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
            if ($status -eq 400 -or $status -eq 404) {
                Remove-Item -LiteralPath $file -ErrorAction SilentlyContinue
                New-Item -ItemType File -Path $missing -Force | Out-Null
            }
            else {
                throw
            }
        }
    }

    if (Test-Path -LiteralPath $missing) {
        Write-Host "  $Table no existe en $Build (se omite)"
        return $null
    }

    return Import-Csv -LiteralPath $file -Encoding UTF8
}

function Add-ToSetMap {
    param([hashtable]$Map, $Key, $Value)

    if (-not $Map.ContainsKey($Key)) {
        $Map[$Key] = New-Object System.Collections.Generic.HashSet[int]
    }
    [void]$Map[$Key].Add([int]$Value)
}

function Build-ProfessionData {
    param([string]$Build)

    # SkillLine: sube por ParentSkillLineID hasta la profesión base (p. ej. "Khaz Algar Alchemy" -> Alchemy).
    $parents = @{}
    $icons = @{}
    foreach ($row in (Get-Table "SkillLine" $Build)) {
        $parents[[int]$row.ID] = [int]$row.ParentSkillLineID
        $icons[[int]$row.ID] = [int]$row.SpellIconFileID
    }

    $rootCache = @{}
    function Get-RootProfession([int]$skillLine) {
        if ($rootCache.ContainsKey($skillLine)) { return $rootCache[$skillLine] }
        $current = $skillLine
        $result = 0
        for ($i = 0; $i -lt 5 -and $current -gt 0; $i++) {
            if ($ProfessionBits.ContainsKey($current)) { $result = $current; break }
            if (-not $parents.ContainsKey($current)) { break }
            $current = $parents[$current]
        }
        $rootCache[$skillLine] = $result
        return $result
    }

    # Receta -> máscara de profesiones
    $spellMask = @{}
    foreach ($row in (Get-Table "SkillLineAbility" $Build)) {
        $root = Get-RootProfession ([int]$row.SkillLine)
        if ($root -eq 0) { continue }
        $spell = [int]$row.Spell
        $spellMask[$spell] = [int]$spellMask[$spell] -bor $ProfessionBits[$root]
    }

    $itemMask = @{}
    function Add-Item([int]$itemId, [int]$mask) {
        if ($itemId -le 0 -or $mask -eq 0) { return }
        $itemMask[$itemId] = [int]$itemMask[$itemId] -bor $mask
    }

    # Reagentes clásicos
    foreach ($row in (Get-Table "SpellReagents" $Build)) {
        $mask = [int]$spellMask[[int]$row.SpellID]
        if ($mask -eq 0) { continue }
        for ($i = 0; $i -lt 8; $i++) {
            Add-Item ([int]$row."Reagent_$i") $mask
        }
    }

    # Crafteo moderno: receta -> slot -> categoría -> objetos
    $slotRows = Get-Table "ModifiedCraftingSpellSlot" $Build
    if ($slotRows) {
        $slotCategories = @{}
        foreach ($row in (Get-Table "MCRSlotXMCRCategory" $Build)) {
            Add-ToSetMap $slotCategories ([int]$row.ModifiedCraftingReagentSlotID) ([int]$row.ModifiedCraftingCategoryID)
        }

        $categoryItems = @{}
        foreach ($row in (Get-Table "CraftingReagentQuality" $Build)) {
            Add-ToSetMap $categoryItems ([int]$row.ModifiedCraftingCategoryID) ([int]$row.ItemID)
        }

        $reagentItemCategory = @{}
        foreach ($row in (Get-Table "ModifiedCraftingReagentItem" $Build)) {
            $reagentItemCategory[[int]$row.ID] = [int]$row.ModifiedCraftingCategoryID
        }
        foreach ($row in (Get-Table "ModifiedCraftingItem" $Build)) {
            $category = $reagentItemCategory[[int]$row.ModifiedCraftingReagentItemID]
            if ($category) {
                Add-ToSetMap $categoryItems $category ([int]$row.ItemID)
            }
        }

        foreach ($row in $slotRows) {
            $mask = [int]$spellMask[[int]$row.SpellID]
            if ($mask -eq 0) { continue }
            $categories = $slotCategories[[int]$row.ModifiedCraftingReagentSlotID]
            if (-not $categories) { continue }
            foreach ($category in $categories) {
                $items = $categoryItems[$category]
                if (-not $items) { continue }
                foreach ($item in $items) { Add-Item $item $mask }
            }
        }
    }

    $professionIcons = [ordered]@{}
    foreach ($id in $Professions.Keys) {
        if ($icons.ContainsKey([int]$id)) { $professionIcons.Add([int]$id, $icons[[int]$id]) }
    }

    return @{ Items = $itemMask; Icons = $professionIcons }
}

function Write-DataFile {
    param([string]$Path, [string]$Flavor, [string]$Build, [hashtable]$Data)

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("-- Generado por scripts/build-profession-data.ps1. No editar a mano.")
    [void]$sb.AppendLine("-- Fuente: wago.tools, build $Build ($Flavor).")
    [void]$sb.AppendLine("local _, TED = ...")
    if ($Flavor -eq "Forever") {
        [void]$sb.AppendLine("if (select(4, GetBuildInfo()) or 0) >= 20000 then return end")
    }
    else {
        [void]$sb.AppendLine("if (select(4, GetBuildInfo()) or 0) < 20000 then return end")
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("TED.ProfessionData = {")
    [void]$sb.AppendLine("  build = `"$Build`",")
    [void]$sb.Append("  icons = {")
    $iconParts = foreach ($entry in $Data.Icons.GetEnumerator()) { "[$($entry.Key)]=$($entry.Value)" }
    [void]$sb.AppendLine(($iconParts -join ", ") + "},")
    [void]$sb.AppendLine("  items = {")

    $ids = @($Data.Items.Keys | Sort-Object { [int]$_ })
    for ($i = 0; $i -lt $ids.Count; $i += 10) {
        $end = [Math]::Min($i + 9, $ids.Count - 1)
        $line = ($ids[$i..$end] | ForEach-Object { "[$_]=$($Data.Items[$_])" }) -join ","
        [void]$sb.AppendLine("    $line,")
    }

    [void]$sb.AppendLine("  },")
    [void]$sb.AppendLine("}")

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $sb.ToString(), $utf8NoBom)
    return $ids.Count
}

$root = Get-ProjectRoot
$outDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $root $OutputDir }
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

foreach ($target in $Targets) {
    $build = Resolve-Build -Product $target.Product -Build $target.Build
    Write-Host "==== $($target.Name): build $build ===="
    $data = Build-ProfessionData -Build $build
    $path = Join-Path $outDir "ProfessionData_$($target.Name).lua"
    $count = Write-DataFile -Path $path -Flavor $target.Name -Build $build -Data $data
    $size = [Math]::Round((Get-Item -LiteralPath $path).Length / 1KB, 1)
    Write-Host "  $count objetos, $size KB -> $path"
}
