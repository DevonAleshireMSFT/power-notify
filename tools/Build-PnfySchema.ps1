<#
.SYNOPSIS
    Generates Dataverse attribute XML from a CSV manifest and injects it into unpacked solution source.

.DESCRIPTION
    Power Notify keeps its schema as source. Hand-writing ~40 lines of solution XML per column does
    not scale and is not reviewable, so columns are declared in schema/pnfy-columns.csv and expanded
    here. The generator is additive and idempotent: a column already present in Entity.xml is skipped,
    never rewritten, so hand edits and portal changes survive a regeneration.

    Lookup columns are deliberately out of scope - they require a matching EntityRelationship entry
    and are authored separately.

.EXAMPLE
    ./tools/Build-PnfySchema.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ManifestPath = (Join-Path $PSScriptRoot '..\schema\pnfy-columns.csv'),
    [string]$SolutionRoot = (Join-Path $PSScriptRoot '..\solutions\PowerNotifyCore')
)

$ErrorActionPreference = 'Stop'

function ConvertTo-XmlText([string]$Value) {
    if ([string]::IsNullOrEmpty($Value)) { return '' }
    [System.Security.SecurityElement]::Escape($Value)
}

function Get-PhysicalName([string]$LogicalName, [string]$Display) {
    $candidate = 'pnfy_' + (($Display -replace '[^A-Za-z0-9]', ''))
    if ($candidate.ToLowerInvariant() -ne $LogicalName.ToLowerInvariant()) {
        # Display name does not round-trip to the logical name, so preserve the logical name casing.
        return $LogicalName
    }
    $candidate
}

function New-AttributeXml($Column, [string]$EntityLogicalName) {
    $logical  = $Column.Column.Trim().ToLowerInvariant()
    $physical = Get-PhysicalName -LogicalName $logical -Display $Column.Display
    $required = if ([string]::IsNullOrWhiteSpace($Column.Required)) { 'none' } else { $Column.Required.Trim() }
    $display  = ConvertTo-XmlText $Column.Display
    $desc     = ConvertTo-XmlText $Column.Description
    $type     = $Column.Type.Trim().ToLowerInvariant()

    $mask = 'ValidForAdvancedFind|ValidForForm|ValidForGrid'
    if ($required -eq 'required') { $mask += '|RequiredForForm' }

    switch ($type) {
        'text'        { $dvType = 'nvarchar'; $format = 'text' }
        'memo'        { $dvType = 'ntext';    $format = 'textarea' }
        'url'         { $dvType = 'nvarchar'; $format = 'url' }
        'email'       { $dvType = 'nvarchar'; $format = 'email' }
        'int'         { $dvType = 'int';      $format = 'none' }
        'datetime'    { $dvType = 'datetime'; $format = 'datetime' }
        'bit'         { $dvType = 'bit';      $format = $null }
        'choice'      { $dvType = 'picklist'; $format = $null }
        'multichoice' { $dvType = 'multiselectpicklist'; $format = $null }
        default       { throw "Unsupported type '$type' for column $logical" }
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("        <attribute PhysicalName=`"$physical`">")
    [void]$sb.AppendLine("          <Type>$dvType</Type>")
    [void]$sb.AppendLine("          <Name>$logical</Name>")
    [void]$sb.AppendLine("          <LogicalName>$logical</LogicalName>")
    [void]$sb.AppendLine("          <RequiredLevel>$required</RequiredLevel>")
    [void]$sb.AppendLine("          <DisplayMask>$mask</DisplayMask>")
    [void]$sb.AppendLine("          <ImeMode>auto</ImeMode>")
    [void]$sb.AppendLine("          <ValidForUpdateApi>1</ValidForUpdateApi>")
    [void]$sb.AppendLine("          <ValidForReadApi>1</ValidForReadApi>")
    [void]$sb.AppendLine("          <ValidForCreateApi>1</ValidForCreateApi>")
    [void]$sb.AppendLine("          <IsCustomField>1</IsCustomField>")
    [void]$sb.AppendLine("          <IsAuditEnabled>1</IsAuditEnabled>")
    [void]$sb.AppendLine("          <IsSecured>0</IsSecured>")
    [void]$sb.AppendLine("          <IntroducedVersion>1.0.0.0</IntroducedVersion>")
    [void]$sb.AppendLine("          <IsCustomizable>1</IsCustomizable>")
    [void]$sb.AppendLine("          <IsRenameable>1</IsRenameable>")
    [void]$sb.AppendLine("          <CanModifySearchSettings>1</CanModifySearchSettings>")
    [void]$sb.AppendLine("          <CanModifyRequirementLevelSettings>1</CanModifyRequirementLevelSettings>")
    [void]$sb.AppendLine("          <CanModifyAdditionalSettings>1</CanModifyAdditionalSettings>")
    [void]$sb.AppendLine("          <SourceType>0</SourceType>")
    [void]$sb.AppendLine("          <IsGlobalFilterEnabled>0</IsGlobalFilterEnabled>")
    [void]$sb.AppendLine("          <IsSortableEnabled>0</IsSortableEnabled>")
    [void]$sb.AppendLine("          <CanModifyGlobalFilterSettings>1</CanModifyGlobalFilterSettings>")
    [void]$sb.AppendLine("          <CanModifyIsSortableSettings>1</CanModifyIsSortableSettings>")
    [void]$sb.AppendLine("          <ExternalName></ExternalName>")
    [void]$sb.AppendLine("          <IsDataSourceSecret>0</IsDataSourceSecret>")
    [void]$sb.AppendLine("          <AutoNumberFormat></AutoNumberFormat>")
    [void]$sb.AppendLine("          <IsSearchable>0</IsSearchable>")
    [void]$sb.AppendLine("          <IsFilterable>1</IsFilterable>")
    [void]$sb.AppendLine("          <IsRetrievable>1</IsRetrievable>")
    [void]$sb.AppendLine("          <IsLocalizable>0</IsLocalizable>")

    switch ($type) {
        { $_ -in 'text', 'url', 'email' } {
            $len = [int]$Column.Length
            [void]$sb.AppendLine("          <Format>$format</Format>")
            [void]$sb.AppendLine("          <MaxLength>$len</MaxLength>")
            [void]$sb.AppendLine("          <Length>$($len * 2)</Length>")
        }
        'memo' {
            $len = [int]$Column.Length
            [void]$sb.AppendLine("          <Format>$format</Format>")
            [void]$sb.AppendLine("          <MaxLength>$len</MaxLength>")
        }
        'int' {
            [void]$sb.AppendLine("          <Format>$format</Format>")
            [void]$sb.AppendLine("          <MinValue>-2147483648</MinValue>")
            [void]$sb.AppendLine("          <MaxValue>2147483647</MaxValue>")
        }
        'datetime' {
            [void]$sb.AppendLine("          <Format>$format</Format>")
            [void]$sb.AppendLine("          <CanChangeDateTimeBehavior>1</CanChangeDateTimeBehavior>")
            [void]$sb.AppendLine("          <Behavior>1</Behavior>")
        }
        'bit' {
            # Local boolean option sets must be unique org-wide, so qualify with the entity name.
            $bitSetName = "${EntityLogicalName}_$logical"
            [void]$sb.AppendLine("          <AppDefaultValue>0</AppDefaultValue>")
            [void]$sb.AppendLine("          <optionset Name=`"$bitSetName`">")
            [void]$sb.AppendLine("            <OptionSetType>bit</OptionSetType>")
            [void]$sb.AppendLine("            <IntroducedVersion>1.0.0.0</IntroducedVersion>")
            [void]$sb.AppendLine("            <IsCustomizable>1</IsCustomizable>")
            [void]$sb.AppendLine("            <ExternalTypeName></ExternalTypeName>")
            [void]$sb.AppendLine("            <displaynames><displayname description=`"$display`" languagecode=`"1033`" /></displaynames>")
            [void]$sb.AppendLine("            <Descriptions><Description description=`"$desc`" languagecode=`"1033`" /></Descriptions>")
            [void]$sb.AppendLine("            <options>")
            [void]$sb.AppendLine("              <option value=`"1`" ExternalValue=`"`" IsHidden=`"0`"><labels><label description=`"Yes`" languagecode=`"1033`" /></labels></option>")
            [void]$sb.AppendLine("              <option value=`"0`" ExternalValue=`"`" IsHidden=`"0`"><labels><label description=`"No`" languagecode=`"1033`" /></labels></option>")
            [void]$sb.AppendLine("            </options>")
            [void]$sb.AppendLine("          </optionset>")
        }
        { $_ -in 'choice', 'multichoice' } {
            if ([string]::IsNullOrWhiteSpace($Column.OptionSet)) { throw "Column $logical is a choice but declares no OptionSet" }
            [void]$sb.AppendLine("          <OptionSetName>$($Column.OptionSet.Trim())</OptionSetName>")
        }
    }

    [void]$sb.AppendLine("          <displaynames>")
    [void]$sb.AppendLine("            <displayname description=`"$display`" languagecode=`"1033`" />")
    [void]$sb.AppendLine("          </displaynames>")
    [void]$sb.AppendLine("          <Descriptions>")
    [void]$sb.AppendLine("            <Description description=`"$desc`" languagecode=`"1033`" />")
    [void]$sb.AppendLine("          </Descriptions>")
    [void]$sb.AppendLine("        </attribute>")
    $sb.ToString()
}

$manifest = Import-Csv -Path $ManifestPath
$entitiesRoot = Join-Path $SolutionRoot 'Entities'
$added = 0
$skipped = 0

foreach ($group in $manifest | Group-Object Table) {
    $dir = Get-ChildItem -Path $entitiesRoot -Directory | Where-Object { $_.Name -ieq $group.Name }
    if (-not $dir) { throw "No unpacked entity folder for table '$($group.Name)'. Create the table shell first." }

    $entityPath = Join-Path $dir.FullName 'Entity.xml'
    $xml = Get-Content -Path $entityPath -Raw
    $present = [regex]::Matches($xml, '<LogicalName>(?<n>[^<]+)</LogicalName>') |
               ForEach-Object { $_.Groups['n'].Value.ToLowerInvariant() }

    $block = [System.Text.StringBuilder]::new()
    foreach ($col in $group.Group) {
        $logical = $col.Column.Trim().ToLowerInvariant()
        if ($present -contains $logical) { $skipped++; continue }
        [void]$block.Append((New-AttributeXml $col $group.Name.ToLowerInvariant()))
        $added++
    }

    if ($block.Length -eq 0) { continue }

    $marker = '      </attributes>'
    $idx = $xml.IndexOf($marker)
    if ($idx -lt 0) { throw "Could not find the attributes close tag in $entityPath" }

    if ($PSCmdlet.ShouldProcess($entityPath, "Insert $($block.Length) chars of attribute XML")) {
        $updated = $xml.Insert($idx, $block.ToString())
        [System.IO.File]::WriteAllText($entityPath, $updated)
        Write-Host "$($group.Name): wrote attributes"
    }
}

Write-Host ""
Write-Host "Columns added: $added   already present (skipped): $skipped"
