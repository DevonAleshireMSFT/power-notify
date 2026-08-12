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
    ./build/Build-PnfySchema.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ManifestPath = (Join-Path $PSScriptRoot '..\schema\pnfy-columns.csv'),
    [string]$RelationshipPath = (Join-Path $PSScriptRoot '..\schema\pnfy-relationships.csv'),
    [string]$KeyPath = (Join-Path $PSScriptRoot '..\schema\pnfy-keys.csv'),
    [string]$SecuredPath = (Join-Path $PSScriptRoot '..\schema\pnfy-secured-columns.csv'),
    [string]$SolutionRoot = (Join-Path $PSScriptRoot '..\solutions\PowerNotifyCore'),
    # Restricts relationship generation to named relationships, for validating one slice at a time.
    [string[]]$OnlyRelationship,
    [string[]]$OnlyKey
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

# --- Lookup columns -------------------------------------------------------
# A lookup needs both an attribute on the referencing entity and a matching
# EntityRelationship in the shared customizations file. Both are emitted here so
# the two can never drift apart.
$relationships = @()
if (Test-Path $RelationshipPath) { $relationships = @(Import-Csv -Path $RelationshipPath) }
if ($OnlyRelationship) { $relationships = @($relationships | Where-Object { $OnlyRelationship -contains $_.Name.Trim() }) }

# Solution XML refers to tables by schema name, not logical name. Entity folder names carry the
# correct casing for custom tables; platform tables are mapped explicitly.
$schemaNameMap = @{ 'systemuser' = 'SystemUser'; 'team' = 'Team' }
Get-ChildItem -Path (Join-Path $SolutionRoot 'Entities') -Directory |
    ForEach-Object { $schemaNameMap[$_.Name.ToLowerInvariant()] = $_.Name }

function Resolve-SchemaName([string]$Name) {
    $key = $Name.Trim().ToLowerInvariant()
    if ($schemaNameMap.ContainsKey($key)) { return $schemaNameMap[$key] }
    $Name.Trim()
}

function New-LookupAttributeXml($Rel) {
    $logical  = $Rel.LookupColumn.Trim().ToLowerInvariant()
    $required = if ([string]::IsNullOrWhiteSpace($Rel.Required)) { 'none' } else { $Rel.Required.Trim() }
    $display  = ConvertTo-XmlText $Rel.LookupDisplay
    $desc     = ConvertTo-XmlText $Rel.Description
    $physical = Get-PhysicalName -LogicalName $logical -Display $Rel.LookupDisplay

    $mask = 'ValidForAdvancedFind|ValidForForm|ValidForGrid'
    if ($required -eq 'required') { $mask += '|RequiredForForm' }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("        <attribute PhysicalName=`"$physical`">")
    [void]$sb.AppendLine("          <Type>lookup</Type>")
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
    [void]$sb.AppendLine("          <IsDataSourceSecret>0</IsDataSourceSecret>")
    [void]$sb.AppendLine("          <AutoNumberFormat></AutoNumberFormat>")
    [void]$sb.AppendLine("          <IsSearchable>0</IsSearchable>")
    [void]$sb.AppendLine("          <IsFilterable>1</IsFilterable>")
    [void]$sb.AppendLine("          <IsRetrievable>1</IsRetrievable>")
    [void]$sb.AppendLine("          <IsLocalizable>0</IsLocalizable>")
    [void]$sb.AppendLine("          <LookupStyle>single</LookupStyle>")
    [void]$sb.AppendLine("          <LookupTypes />")
    [void]$sb.AppendLine("          <displaynames>")
    [void]$sb.AppendLine("            <displayname description=`"$display`" languagecode=`"1033`" />")
    [void]$sb.AppendLine("          </displaynames>")
    [void]$sb.AppendLine("          <Descriptions>")
    [void]$sb.AppendLine("            <Description description=`"$desc`" languagecode=`"1033`" />")
    [void]$sb.AppendLine("          </Descriptions>")
    [void]$sb.AppendLine("        </attribute>")
    $sb.ToString()
}

function New-RelationshipXml($Rel) {
    $referencing = Resolve-SchemaName $Rel.ReferencingTable
    $referenced  = Resolve-SchemaName $Rel.ReferencedTable
    $lookup      = $Rel.LookupColumn.Trim().ToLowerInvariant()
    $lookupSchema = Get-PhysicalName -LogicalName $lookup -Display $Rel.LookupDisplay
    $cascadeDelete = $Rel.CascadeDelete.Trim()
    $cascadeAssign = $Rel.CascadeAssign.Trim()
    $cascadeShare  = if ($cascadeAssign -eq 'Cascade') { 'Cascade' } else { 'NoCascade' }
    $desc = ConvertTo-XmlText $Rel.Description
    # Related-record navigation is noise on systemuser and team, so suppress it there.
    $navOption = if ($referenced -in 'SystemUser', 'Team') { 'DoNotDisplay' } else { 'UseCollectionName' }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("  <EntityRelationship Name=`"$($Rel.Name.Trim())`">")
    [void]$sb.AppendLine("    <EntityRelationshipType>OneToMany</EntityRelationshipType>")
    [void]$sb.AppendLine("    <IsCustomizable>1</IsCustomizable>")
    [void]$sb.AppendLine("    <IntroducedVersion>1.0.0.0</IntroducedVersion>")
    [void]$sb.AppendLine("    <IsHierarchical>0</IsHierarchical>")
    [void]$sb.AppendLine("    <ReferencingEntityName>$referencing</ReferencingEntityName>")
    [void]$sb.AppendLine("    <ReferencedEntityName>$referenced</ReferencedEntityName>")
    [void]$sb.AppendLine("    <CascadeAssign>$cascadeAssign</CascadeAssign>")
    [void]$sb.AppendLine("    <CascadeDelete>$cascadeDelete</CascadeDelete>")
    [void]$sb.AppendLine("    <CascadeArchive>$cascadeDelete</CascadeArchive>")
    [void]$sb.AppendLine("    <CascadeReparent>NoCascade</CascadeReparent>")
    [void]$sb.AppendLine("    <CascadeShare>$cascadeShare</CascadeShare>")
    [void]$sb.AppendLine("    <CascadeUnshare>$cascadeShare</CascadeUnshare>")
    [void]$sb.AppendLine("    <CascadeRollupView>NoCascade</CascadeRollupView>")
    [void]$sb.AppendLine("    <IsValidForAdvancedFind>1</IsValidForAdvancedFind>")
    [void]$sb.AppendLine("    <ReferencingAttributeName>$lookupSchema</ReferencingAttributeName>")
    [void]$sb.AppendLine("    <RelationshipDescription>")
    [void]$sb.AppendLine("      <Descriptions>")
    [void]$sb.AppendLine("        <Description description=`"$desc`" languagecode=`"1033`" />")
    [void]$sb.AppendLine("      </Descriptions>")
    [void]$sb.AppendLine("    </RelationshipDescription>")
    [void]$sb.AppendLine("    <EntityRelationshipRoles>")
    [void]$sb.AppendLine("      <EntityRelationshipRole>")
    [void]$sb.AppendLine("        <NavPaneDisplayOption>$navOption</NavPaneDisplayOption>")
    [void]$sb.AppendLine("        <NavPaneArea>Details</NavPaneArea>")
    [void]$sb.AppendLine("        <NavPaneOrder>10000</NavPaneOrder>")
        [void]$sb.AppendLine("        <NavigationPropertyName>$lookupSchema</NavigationPropertyName>")
    [void]$sb.AppendLine("        <RelationshipRoleType>1</RelationshipRoleType>")
    [void]$sb.AppendLine("      </EntityRelationshipRole>")
    [void]$sb.AppendLine("      <EntityRelationshipRole>")
    [void]$sb.AppendLine("        <NavigationPropertyName>$($Rel.Name.Trim())</NavigationPropertyName>")
    [void]$sb.AppendLine("        <RelationshipRoleType>0</RelationshipRoleType>")
    [void]$sb.AppendLine("      </EntityRelationshipRole>")
    [void]$sb.AppendLine("    </EntityRelationshipRoles>")
    [void]$sb.AppendLine("  </EntityRelationship>")
    $sb.ToString()
}

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

# --- Lookups and relationships -------------------------------------------
$lookupsAdded = 0
$relsAdded = 0

foreach ($relGroup in $relationships | Group-Object ReferencingTable) {
    $dir = Get-ChildItem -Path $entitiesRoot -Directory | Where-Object { $_.Name -ieq $relGroup.Name }
    if (-not $dir) { throw "No unpacked entity folder for referencing table '$($relGroup.Name)'" }

    $entityPath = Join-Path $dir.FullName 'Entity.xml'
    $xml = Get-Content -Path $entityPath -Raw
    $present = [regex]::Matches($xml, '<LogicalName>(?<n>[^<]+)</LogicalName>') |
               ForEach-Object { $_.Groups['n'].Value.ToLowerInvariant() }

    $block = [System.Text.StringBuilder]::new()
    foreach ($rel in $relGroup.Group) {
        if ($present -contains $rel.LookupColumn.Trim().ToLowerInvariant()) { continue }
        [void]$block.Append((New-LookupAttributeXml $rel))
        $lookupsAdded++
    }

    if ($block.Length -eq 0) { continue }
    $marker = '      </attributes>'
    $idx = $xml.IndexOf($marker)
    if ($idx -lt 0) { throw "Could not find the attributes close tag in $entityPath" }

    if ($PSCmdlet.ShouldProcess($entityPath, 'Insert lookup attribute XML')) {
        [System.IO.File]::WriteAllText($entityPath, $xml.Insert($idx, $block.ToString()))
        Write-Host "$($relGroup.Name): wrote lookups"
    }
}

# Relationships live one file per referenced entity under Other/Relationships, and every one must
# also be listed in Other/Relationships.xml - the packer reads that index, not the folder.
$relDir = Join-Path $SolutionRoot 'Other\Relationships'
if (-not (Test-Path $relDir)) { New-Item -ItemType Directory -Path $relDir -Force | Out-Null }
$indexPath = Join-Path $SolutionRoot 'Other\Relationships.xml'
$index = Get-Content -Path $indexPath -Raw

foreach ($refGroup in $relationships | Group-Object { Resolve-SchemaName $_.ReferencedTable }) {
    $referenced = $refGroup.Name
    $relFile = Join-Path $relDir "$referenced.xml"
    $existing = if (Test-Path $relFile) { Get-Content $relFile -Raw } else { '' }

    $body = [System.Text.StringBuilder]::new()
    foreach ($rel in $refGroup.Group) {
        if ($existing -match [regex]::Escape("<EntityRelationship Name=`"$($rel.Name.Trim())`">")) { continue }
        [void]$body.Append((New-RelationshipXml $rel))
        $relsAdded++
    }
    if ($body.Length -eq 0) { continue }

    if ($PSCmdlet.ShouldProcess($relFile, 'Write entity relationships')) {
        if ($existing) {
            $idx = $existing.LastIndexOf('</EntityRelationships>')
            $out = $existing.Insert($idx, $body.ToString())
        } else {
            $out = "<?xml version=`"1.0`" encoding=`"utf-8`"?>`r`n<EntityRelationships xmlns:xsi=`"http://www.w3.org/2001/XMLSchema-instance`">`r`n$($body.ToString())</EntityRelationships>"
        }
        [System.IO.File]::WriteAllText($relFile, $out)
        Write-Host "Relationships/$referenced.xml: written"
    }
}

$indexAdditions = [System.Text.StringBuilder]::new()
foreach ($rel in $relationships) {
    $entry = "  <EntityRelationship Name=`"$($rel.Name.Trim())`" />"
    if ($index -match [regex]::Escape($entry)) { continue }
    [void]$indexAdditions.AppendLine($entry)
}
if ($indexAdditions.Length -gt 0 -and $PSCmdlet.ShouldProcess($indexPath, 'Register relationships in index')) {
    $idx = $index.LastIndexOf('</EntityRelationships>')
    [System.IO.File]::WriteAllText($indexPath, $index.Insert($idx, $indexAdditions.ToString()))
    Write-Host 'Relationships.xml: index updated'
}

Write-Host "Lookups added: $lookupsAdded   relationships added: $relsAdded"

# --- Alternate keys -------------------------------------------------------
$keys = @()
if (Test-Path $KeyPath) { $keys = @(Import-Csv -Path $KeyPath) }
if ($OnlyKey) { $keys = @($keys | Where-Object { $OnlyKey -contains $_.Name.Trim() }) }
$keysAdded = 0

foreach ($keyGroup in $keys | Group-Object Table) {
    $dir = Get-ChildItem -Path $entitiesRoot -Directory | Where-Object { $_.Name -ieq $keyGroup.Name }
    if (-not $dir) { throw "No unpacked entity folder for table '$($keyGroup.Name)'" }

    $entityPath = Join-Path $dir.FullName 'Entity.xml'
    $xml = Get-Content -Path $entityPath -Raw

    $block = [System.Text.StringBuilder]::new()
    foreach ($key in $keyGroup.Group) {
        $name = $key.Name.Trim()
        if ($xml -match [regex]::Escape("<Name>$name</Name>")) { continue }
        [void]$block.AppendLine("        <EntityKey>")
        [void]$block.AppendLine("          <Name>$name</Name>")
        [void]$block.AppendLine("          <LogicalName>$($name.ToLowerInvariant())</LogicalName>")
        [void]$block.AppendLine("          <IntroducedVersion>1.0.0.0</IntroducedVersion>")
        [void]$block.AppendLine("          <IsCustomizable>1</IsCustomizable>")
        [void]$block.AppendLine("          <EntityKeyAttributes>")
        foreach ($attr in $key.Attributes.Split(';')) {
            [void]$block.AppendLine("            <AttributeName>$($attr.Trim().ToLowerInvariant())</AttributeName>")
        }
        [void]$block.AppendLine("          </EntityKeyAttributes>")
        [void]$block.AppendLine("          <displaynames>")
        [void]$block.AppendLine("            <displayname description=`"$(ConvertTo-XmlText $key.DisplayName)`" languagecode=`"1033`" />")
        [void]$block.AppendLine("          </displaynames>")
        [void]$block.AppendLine("        </EntityKey>")
        $keysAdded++
    }
    if ($block.Length -eq 0) { continue }

    if ($PSCmdlet.ShouldProcess($entityPath, 'Insert entity keys')) {
        if ($xml -match '<EntityKeys>') {
            $idx = $xml.IndexOf('      </EntityKeys>')
            $updated = $xml.Insert($idx, $block.ToString())
        } else {
            # EntityKeys must sit between the attributes block and EntitySetName.
            $anchor = $xml.IndexOf('      <EntitySetName>')
            if ($anchor -lt 0) { throw "Could not find EntitySetName in $entityPath" }
            $wrapped = "      <EntityKeys>`r`n$($block.ToString())      </EntityKeys>`r`n"
            $updated = $xml.Insert($anchor, $wrapped)
        }
        [System.IO.File]::WriteAllText($entityPath, $updated)
        Write-Host "$($keyGroup.Name): wrote alternate keys"
    }
}

Write-Host "Alternate keys added: $keysAdded"

# --- Column security ------------------------------------------------------
# Unlike everything above, this pass ENFORCES a property on columns that already exist.
# A column cannot be added to a column security profile unless IsSecured is 1, and that
# switch is a security control, so the manifest wins over whatever is currently in source.
$secured = @()
if (Test-Path $SecuredPath) { $secured = @(Import-Csv -Path $SecuredPath) }
$securedChanged = 0

foreach ($secGroup in $secured | Group-Object Table) {
    $dir = Get-ChildItem -Path $entitiesRoot -Directory | Where-Object { $_.Name -ieq $secGroup.Name }
    if (-not $dir) { throw "No unpacked entity folder for table '$($secGroup.Name)'" }

    $entityPath = Join-Path $dir.FullName 'Entity.xml'
    $xml = Get-Content -Path $entityPath -Raw
    $original = $xml

    foreach ($col in $secGroup.Group) {
        $logical = $col.Column.Trim().ToLowerInvariant()
        # Scope the edit to this attribute's own block so sibling columns are untouched.
        $pattern = '(?s)(<attribute PhysicalName="[^"]*">(?:(?!</attribute>).)*?<LogicalName>' +
                   [regex]::Escape($logical) +
                   '</LogicalName>(?:(?!</attribute>).)*?)<IsSecured>0</IsSecured>'
        $xml = [regex]::Replace($xml, $pattern, '${1}<IsSecured>1</IsSecured>')
    }

    if ($xml -ne $original -and $PSCmdlet.ShouldProcess($entityPath, 'Enable column security')) {
        [System.IO.File]::WriteAllText($entityPath, $xml)
        $securedChanged++
        Write-Host "$($secGroup.Name): enabled column security"
    }
}

Write-Host "Tables with column security updated: $securedChanged"
