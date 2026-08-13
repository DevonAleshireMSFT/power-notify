# Creates the Power Notify backlog as GitHub issues and adds them to the project board.
# One-time bootstrap; safe to re-run because issue titles are checked first.
$ErrorActionPreference = 'Stop'
$owner = 'DevonAleshireMSFT'
$projectNumber = 7

$labels = @(
    @{ n = 'security'; c = 'B60205'; d = 'Security-affecting work' },
    @{ n = 'spike';    c = 'FBCA04'; d = 'Time-boxed investigation to remove an unknown' },
    @{ n = 'flows';    c = '1D76DB'; d = 'Power Automate cloud flows' },
    @{ n = 'app';      c = '0E8A16'; d = 'Model-driven app, forms, views' },
    @{ n = 'alm';      c = '5319E7'; d = 'Solutions, deployment, configuration data' },
    @{ n = 'decision'; c = 'D93F0B'; d = 'Needs a decision before work can start' }
)
foreach ($l in $labels) {
    gh label create $l.n --color $l.c --description $l.d --force 2>&1 | Out-Null
}

$issues = @(
    @{ t = 'Rotate the exposed legacy Logic Apps trigger'
       l = 'security'
       b = "The legacy web resource contained a live Logic Apps shared access signature on a flow whose trigger accepted Anyone. The value is redacted in the repo, but the trigger itself has NOT been rotated in the source environment and remains callable by anyone holding the original URL.`n`nDone when: the original URL returns 401 or 404, and the old flow is deleted." },

    @{ t = 'Decide deployment identity mode per environment'
       l = 'decision'
       b = "ADR 0008 defines Mode A (service account, all channels) and Mode B (no service account, email only). Decide which mode applies to GCC High and to DoD.`n`nThis blocks connection references and determines which email transport is built first. Building Mode A and retrofitting Mode B is the expensive order.`n`nDone when: ADR 0008 moves from proposed to accepted with the per-environment choice recorded." },

    @{ t = 'Spike: Dataverse connector service principal auth in DoD'
       l = 'spike'
       b = "ADR 0008 assumes an application user can own the Dataverse connection reference in Mode B. Verified behaviour in commercial does not transfer to DoD.`n`nDone when: a connection reference authenticated by service principal is proven working in a DoD environment, or ruled out with evidence." },

    @{ t = 'Spike: queue-based Dataverse email in the target environment'
       l = 'spike'
       b = "Mode B sends email via the Dataverse email table with a queue as sender through server-side sync, avoiding a mailbox-owning account.`n`nDone when: a test email is delivered from a queue in the target environment, or the approach is ruled out with evidence." },

    @{ t = 'Spike: verify Adaptive Card delivery in DoD'
       l = 'spike'
       b = "Flow Bot is unsupported in government clouds, so cards must post as the User. Whether Adaptive Cards render and post correctly in DoD is unverified; the channel is gated behind pnfy_AdaptiveCardsEnabled until proven.`n`nDone when: a card is posted successfully in DoD, or the channel is formally descoped." },

    @{ t = 'Create the three connection references'
       l = 'alm'
       b = "pnfy_Dataverse, pnfy_Office365Outlook, pnfy_Teams.`n`nBlocked by the identity mode decision. Whoever owns these cannot be changed later for Teams, because Teams connections are not shareable.`n`nDone when: all three exist in PowerNotifyCore, owned by the identity chosen in ADR 0008." },

    @{ t = 'Build main forms for all 11 tables'
       l = 'app'
       b = "Every table currently has only its primary column on the form, so the tables are unusable in the UI and configuration records cannot be created comfortably.`n`nDone when: each table has a main form with its columns grouped logically, and an administrator can create a complete notification definition without leaving the app." },

    @{ t = 'Build views for all 11 tables'
       l = 'app'
       b = "Includes the operational views the support model depends on: Failed in Last 24 Hours, Stuck Requests, Suppressed, By Calling Application, Retry Queue, Definitions Failing Validation.`n`nDone when: a support analyst can answer 'why did this not arrive' from views alone, without opening a flow run." },

    @{ t = 'Build the Power Notify Administration app sitemap'
       l = 'app'
       b = "Areas: Configuration (definitions, channel bindings, templates, tokens; routing: recipient rules, Teams destinations, calling applications) and Operations (requests, delivery attempts; diagnostics: payload snapshots, suppression entries).`n`nDone when: the app opens for a non-administrator holding only the Power Notify Support Analyst role." },

    @{ t = 'PN | Enqueue Notification - the public contract'
       l = 'flows'
       b = "The single supported entry point. Validates, writes a Queued request row, returns immediately. Hybrid input: typed parameters plus RuntimeParametersJson.`n`nDone when: an unknown message key returns Accepted=false with a validation error and does not throw; a valid call returns a request number and writes exactly one Queued row." },

    @{ t = 'PN | Dispatch Notification - orchestrator'
       l = 'flows'
       b = "Dataverse-triggered on Queued requests. Resolves recipients, renders templates, calls channel senders, writes delivery attempts, rolls up status.`n`nDone when: a definition with two enabled channels produces two attempt rows, and one channel failing still delivers the other and leaves the request PartiallySent." },

    @{ t = 'PN | Render Template - token substitution and encoding'
       l = 'flows,security'
       b = "Iterates DECLARED tokens rather than scanning the body. HTML-encodes values unless the token allows raw HTML; JSON-escapes for card payloads.`n`nDone when: a token value containing a script tag is delivered encoded and does not execute; a missing required token fails the request before anything sends; no delivered message contains a literal double brace." },

    @{ t = 'PN | Resolve Recipients'
       l = 'flows'
       b = "Returns a typed array with a resolved flag and a reason per entry. Handles static address, Dataverse user and team, Entra group, record owner, created by, requesting user, runtime parameter, and Teams destination.`n`nDone when: an unresolvable primary falls back correctly, and an unresolved recipient produces a Skipped attempt with a reason rather than silence." },

    @{ t = 'PN | Send Email - both transports'
       l = 'flows'
       b = "Two supported transports per ADR 0008, selected by pnfy_EmailTransport: Office 365 Outlook connector, and Dataverse email with a queue sender. The Dataverse path is a supported transport, not a fallback.`n`nDone when: both paths deliver and are covered by test evidence, and test mode redirects both." },

    @{ t = 'PN | Send Teams Message and Adaptive Card'
       l = 'flows'
       b = "Poster must be User; Flow Bot is unsupported in government clouds. Gated behind pnfy_TeamsEnabled and pnfy_AdaptiveCardsEnabled.`n`nDone when: messages post to a configured Teams destination, and a disabled channel produces a Skipped attempt with a reason." },

    @{ t = 'PN | Retry, Monitor Stuck Requests, and Purge'
       l = 'flows'
       b = "Retry with exponential backoff bounded by pnfy_MaxRetryCount, retrying only retryable error classes. Stuck-request monitor with an alert-loop guard. Daily purge driven by the retention variables.`n`nDone when: a transient failure retries and stops at the ceiling; a stuck request is flagged and alerts once; purge removes requests and cascades to attempts and payloads." },

    @{ t = 'PN | Validate Notification Definition'
       l = 'flows'
       b = "Pre-activation gate. Checks every enabled binding has a published template, every required token is declared, recipient rules resolve, Teams destinations exist, and card JSON parses.`n`nDone when: a definition cannot be activated while validation fails." },

    @{ t = 'Configuration data migration package'
       l = 'alm'
       b = "pac data export and import schema over the seven configuration tables. The alternate keys make this a deterministic upsert across environments. Log tables are never migrated.`n`nDone when: configuration moves Dev to Test without ID mapping and re-running is idempotent." },

    @{ t = 'Deployment settings files per environment'
       l = 'alm'
       b = "pac solution create-settings output for Dev, Test, and Prod. Environment-specific variables ship with no default precisely so these files must supply them.`n`nDone when: a managed import into a clean environment resolves every variable from the settings file, with zero unmanaged layers." },

    @{ t = 'Security role matrix testing with real test users'
       l = 'security'
       b = "One test user per role, verifying every cell of the permission matrix. Column security must be verified through the Web API, not only the form, because the form can hide what the API still returns.`n`nDone when: a Caller-role user cannot read another application's requests, and a Template Author cannot modify a recipient rule." },

    @{ t = 'Consumer onboarding guide'
       l = 'alm'
       b = "How another solution calls Power Notify: the contract, the message key, failure modes, and the compatibility matrix. Must state plainly that enqueue returns acceptance and NOT delivery outcome, and that channel availability is environment-dependent.`n`nDone when: a second team onboards from the guide without help." },

    @{ t = 'Pilot with one consuming application'
       l = 'alm'
       b = "End-to-end proof with a real consumer.`n`nDone when: the pilot application sends through Power Notify and carries no notification logic of its own." }
)

$existing = (gh issue list --state all --limit 200 --json title | ConvertFrom-Json).title

foreach ($i in $issues) {
    if ($existing -contains $i.t) { Write-Host "skip (exists): $($i.t)"; continue }
    $url = gh issue create --title $i.t --body $i.b --label $i.l
    gh project item-add $projectNumber --owner $owner --url $url | Out-Null
    Write-Host "created: $($i.t)"
}
