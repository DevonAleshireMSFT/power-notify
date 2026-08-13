<#
.SYNOPSIS
    Posts a test Adaptive Card to a Teams Workflows webhook.

.DESCRIPTION
    Spike support for issue #23 - verifying whether the "When a Teams webhook request is
    received" path works in GCC High and DoD.

    Power Notify's production Teams sender would make exactly this call: a plain HTTP POST
    with no Teams connection reference and no Teams identity.

    SECURITY: the webhook URL is a bearer credential. Anyone holding it can post to the
    channel. Pass it as a parameter - never hardcode it, never commit it, never paste it
    into an issue or a screenshot.

.PARAMETER WebhookUrl
    The HTTPS URL minted by the Teams webhook trigger.

.PARAMETER BearerToken
    Only needed when the trigger's authentication mode is stricter than "Anyone". If this
    is required, the production sender flow needs an authenticated call rather than a
    plain POST - record that, it changes the design.

.EXAMPLE
    .\Test-PnfyTeamsWebhook.ps1 -WebhookUrl $url

.EXAMPLE
    .\Test-PnfyTeamsWebhook.ps1 -WebhookUrl $url -Title 'DoD test' -Message 'Cloud: DoD'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^https://')]
    [string]$WebhookUrl,

    [string]$Title = 'Power Notify webhook test',

    [string]$Message = 'If this card is visible, the Teams webhook path works in this cloud.',

    [string]$BearerToken
)

$ErrorActionPreference = 'Stop'

$card = @{
    type        = 'message'
    attachments = @(
        @{
            contentType = 'application/vnd.microsoft.card.adaptive'
            content     = @{
                type      = 'AdaptiveCard'
                '$schema' = 'http://adaptivecards.io/schemas/adaptive-card.json'
                version   = '1.4'
                body      = @(
                    @{ type = 'TextBlock'; text = $Title; weight = 'Bolder'; size = 'Medium' }
                    @{ type = 'TextBlock'; text = $Message; wrap = $true }
                    @{
                        type  = 'FactSet'
                        facts = @(
                            @{ title = 'Sent'; value = (Get-Date).ToString('u') }
                            @{ title = 'Sender'; value = 'Test-PnfyTeamsWebhook.ps1' }
                        )
                    }
                )
            }
        }
    )
}

$json = $card | ConvertTo-Json -Depth 20
$headers = @{}
if ($BearerToken) { $headers['Authorization'] = "Bearer $BearerToken" }

Write-Host "POST -> $($WebhookUrl -replace '(?<=^https://[^/]{1,60}/).*', '<redacted>')"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $response = Invoke-WebRequest -Uri $WebhookUrl -Method Post `
        -ContentType 'application/json; charset=utf-8' `
        -Headers $headers `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($json))

    $sw.Stop()
    Write-Host "PASS - HTTP $($response.StatusCode) in $($sw.ElapsedMilliseconds) ms" -ForegroundColor Green
    if ($response.Content) { Write-Host "Body: $($response.Content)" }
    Write-Host "`nNow confirm the card actually rendered in the channel. A 2xx only means the"
    Write-Host "trigger accepted the request - the receiving flow can still fail afterwards."
}
catch {
    $sw.Stop()
    $status = $null
    if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
    Write-Host "FAIL - HTTP $status after $($sw.ElapsedMilliseconds) ms" -ForegroundColor Red
    Write-Host $_.Exception.Message
    Write-Host "`nCheck the receiving flow's run history in Power Automate. A failure there"
    Write-Host "rather than here is the interesting case - see issue #23."
    exit 1
}
