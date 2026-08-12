<#
.SYNOPSIS
    Generates Dataverse security roles and column security profiles from CSV manifests.

.DESCRIPTION
    Roles and column security profiles cannot be addressed by schema name, so pac cannot add them
    to a solution and they are tedious to build by hand. They are declared in schema/pnfy-roles.csv
    and schema/pnfy-column-profiles.csv and expanded here.

    Every generated role inherits the platform baseline in schema/pnfy-role-baseline.csv. That
    baseline was captured from a portal-created role and is the minimum privilege set required to
    open a model-driven app - without it a role looks correct and still cannot load the app.

    Additive and idempotent: an existing role file or profile is skipped, never rewritten.

.EXAMPLE
    ./build/Build-PnfySecurity.ps1 -OnlyRole 'Power Notify Reader'
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RolePath = (Join-Path $PSScriptRoot '..\schema\pnfy-roles.csv'),
    [string]$BaselinePath = (Join-Path $PSScriptRoot '..\schema\pnfy-role-baseline.csv'),
    [string]$ProfilePath = (Join-Path $PSScriptRoot '..\schema\pnfy-column-profiles.csv'),
    [string]$SolutionRoot = (Join-Path $PSScriptRoot '..\solutions\PowerNotifyCore'),
    [string[]]$OnlyRole,
    [string[]]$OnlyProfile
)

$ErrorActionPreference = 'Stop'

function ConvertTo-XmlText([string]$Value) {
    if ([string]::IsNullOrEmpty($Value)) { return '' }
    [System.Security.SecurityElement]::Escape($Value)
}

$verbToPrivilege = @{
    'Create'   = 'prvCreate'
    'Read'     = 'prvRead'
    'Write'    = 'prvWrite'
    'Delete'   = 'prvDelete'
    'Append'   = 'prvAppend'
    'AppendTo' = 'prvAppendTo'
    'Assign'   = 'prvAssign'
    'Share'    = 'prvShare'
}

$rolesDir = Join-Path $SolutionRoot 'Roles'
if (-not (Test-Path $rolesDir)) { New-Item -ItemType Directory -Path $rolesDir -Force | Out-Null }
$solutionPath = Join-Path $SolutionRoot 'Other\Solution.xml'
$solutionXml = Get-Content -Path $solutionPath -Raw
$rootAdditions = [System.Text.StringBuilder]::new()

# --- Security roles -------------------------------------------------------
$baseline = @(Import-Csv -Path $BaselinePath)
$roleRows = @(Import-Csv -Path $RolePath)
if ($OnlyRole) { $roleRows = @($roleRows | Where-Object { $OnlyRole -contains $_.Role.Trim() }) }
$rolesAdded = 0

foreach ($group in $roleRows | Group-Object Role) {
    $roleName = $group.Name.Trim()
    $roleFile = Join-Path $rolesDir "$roleName.xml"
    if (Test-Path $roleFile) { Write-Host "$roleName : already exists, skipped"; continue }

    $privileges = [ordered]@{}
    foreach ($p in $baseline) { $privileges[$p.Name] = $p.Level }

    foreach ($row in $group.Group) {
        $level = $row.Level.Trim()
        foreach ($table in $row.Tables.Split(';')) {
            $t = $table.Trim()
            if (-not $t) { continue }
            foreach ($verb in $row.Privileges.Split(';')) {
                $v = $verb.Trim()
                if (-not $v) { continue }
                if (-not $verbToPrivilege.ContainsKey($v)) { throw "Unknown privilege verb '$v' for role $roleName" }
                $privileges["$($verbToPrivilege[$v])$t"] = $level
            }
        }
    }

    $roleId = "{$([guid]::NewGuid().ToString())}"
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
    [void]$sb.AppendLine("<Role id=`"$roleId`" name=`"$(ConvertTo-XmlText $roleName)`" xmlns:xsi=`"http://www.w3.org/2001/XMLSchema-instance`">")
    [void]$sb.AppendLine('  <IsCustomizable>1</IsCustomizable>')
    [void]$sb.AppendLine('  <IsAutoAssigned>0</IsAutoAssigned>')
    [void]$sb.AppendLine('  <RolePrivileges>')
    foreach ($name in ($privileges.Keys | Sort-Object)) {
        [void]$sb.AppendLine("    <RolePrivilege name=`"$name`" level=`"$($privileges[$name])`" />")
    }
    [void]$sb.AppendLine('  </RolePrivileges>')
    [void]$sb.AppendLine('</Role>')

    if ($PSCmdlet.ShouldProcess($roleFile, 'Write security role')) {
        [System.IO.File]::WriteAllText($roleFile, $sb.ToString(), [System.Text.UTF8Encoding]::new($true))
        [void]$rootAdditions.AppendLine("      <RootComponent type=`"20`" id=`"$roleId`" behavior=`"0`" />")
        $rolesAdded++
        Write-Host "$roleName : written ($($privileges.Count) privileges)"
    }
}

# --- Column security profiles --------------------------------------------
$profileRows = @(Import-Csv -Path $ProfilePath)
if ($OnlyProfile) { $profileRows = @($profileRows | Where-Object { $OnlyProfile -contains $_.Profile.Trim() }) }
$profilePath = Join-Path $SolutionRoot 'Other\FieldSecurityProfiles.xml'
$profileXml = if (Test-Path $profilePath) { Get-Content -Path $profilePath -Raw } else {
    "<?xml version=`"1.0`" encoding=`"utf-8`"?>`r`n<FieldSecurityProfiles xmlns:xsi=`"http://www.w3.org/2001/XMLSchema-instance`">`r`n</FieldSecurityProfiles>"
}
$profilesAdded = 0
$profileBlock = [System.Text.StringBuilder]::new()

foreach ($group in $profileRows | Group-Object Profile) {
    $profileName = $group.Name.Trim()
    if ($profileXml -match [regex]::Escape("<FieldSecurityProfile name=`"$profileName`"")) {
        Write-Host "$profileName : already exists, skipped"
        continue
    }

    $profileId = "{$([guid]::NewGuid().ToString())}"
    $desc = ConvertTo-XmlText $group.Group[0].Description
    [void]$profileBlock.AppendLine("  <FieldSecurityProfile name=`"$(ConvertTo-XmlText $profileName)`" description=`"$desc`" fieldsecurityprofileid=`"$profileId`">")
    [void]$profileBlock.AppendLine('    <FieldPermissions>')
    foreach ($row in $group.Group) {
        [void]$profileBlock.AppendLine('      <FieldPermission>')
        [void]$profileBlock.AppendLine("        <EntityName>$($row.Table.Trim().ToLowerInvariant())</EntityName>")
        [void]$profileBlock.AppendLine("        <AttributeName>$($row.Column.Trim().ToLowerInvariant())</AttributeName>")
        [void]$profileBlock.AppendLine("        <CanRead>$($row.CanRead.Trim())</CanRead>")
        [void]$profileBlock.AppendLine("        <CanUpdate>$($row.CanUpdate.Trim())</CanUpdate>")
        [void]$profileBlock.AppendLine("        <CanCreate>$($row.CanCreate.Trim())</CanCreate>")
        [void]$profileBlock.AppendLine('        <CanReadUnmasked>0</CanReadUnmasked>')
        [void]$profileBlock.AppendLine('      </FieldPermission>')
    }
    [void]$profileBlock.AppendLine('    </FieldPermissions>')
    [void]$profileBlock.AppendLine('  </FieldSecurityProfile>')
    [void]$rootAdditions.AppendLine("      <RootComponent type=`"70`" id=`"$profileId`" behavior=`"0`" />")
    $profilesAdded++
    Write-Host "$profileName : written ($(@($group.Group).Count) columns)"
}

if ($profileBlock.Length -gt 0 -and $PSCmdlet.ShouldProcess($profilePath, 'Write column security profiles')) {
    $idx = $profileXml.LastIndexOf('</FieldSecurityProfiles>')
    [System.IO.File]::WriteAllText($profilePath, $profileXml.Insert($idx, $profileBlock.ToString()), [System.Text.UTF8Encoding]::new($true))
}

# --- Root components ------------------------------------------------------
# Roles and profiles are referenced in the manifest by GUID, not schema name.
if ($rootAdditions.Length -gt 0 -and $PSCmdlet.ShouldProcess($solutionPath, 'Register root components')) {
    $idx = $solutionXml.LastIndexOf('    </RootComponents>')
    [System.IO.File]::WriteAllText($solutionPath, $solutionXml.Insert($idx, $rootAdditions.ToString()), [System.Text.UTF8Encoding]::new($true))
    Write-Host 'Solution.xml: root components registered'
}

Write-Host ""
Write-Host "Roles added: $rolesAdded   profiles added: $profilesAdded"
