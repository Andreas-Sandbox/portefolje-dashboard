# setup-org.ps1 - automatiserer Del C og D fra STEG-FOR-STEG.md:
#   - org-niva Issue types (Objective, Feature)
#   - org-niva Issue fields (Status, Team, Kvartal)
#   - setter type + feltverdier pa alle 8 dummy-issuene fra seed.ps1
#   - blocked-by-relasjonene mellom Offline-modus / Plattform-API / Synk
#   - oppretter Portefolje-prosjektet og legger til de 8 issuene
#
# Bruk:
#   .\scripts\setup-org.ps1 -Org Andreas-Sandbox
#
# Forutsetter at scripts\seed.ps1 er kjort mot samme org forst (samme
# fire repoer / atte issues, i samme rekkefolge).
#
# Ting scriptet IKKE gjor (ma gjores i nettleseren etterpa):
#   - Roadmap- og Board-visningene i prosjektet (D6/D7)
#   - Sub-issues (E2)
#   - Kobling til dashboardet (Del F)

param(
    [Parameter(Mandatory = $true)]
    [string]$Org
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false
# Uten dette leser/skriver PowerShell gh sin UTF-8-output med feil codepage,
# som ga mojibake for norske bokstaver hentet via JSON og sendt videre som arg.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$graphqlDir = Join-Path $PSScriptRoot "graphql"

function Invoke-GraphQL {
    param(
        [Parameter(Mandatory = $true)][string]$QueryFile,
        [hashtable]$Variables = @{}
    )
    $callArgs = @("api", "graphql", "-F", "query=@$QueryFile")
    foreach ($key in $Variables.Keys) {
        $callArgs += "-F"
        $callArgs += "$key=$($Variables[$key])"
    }
    $raw = & gh @callArgs 2>&1
    $exit = $LASTEXITCODE
    $parsed = $null
    try { $parsed = $raw | ConvertFrom-Json } catch { }
    if ($exit -ne 0 -or -not $parsed -or ($parsed.errors -and -not $parsed.data)) {
        throw "GraphQL-kall mot $QueryFile feilet:`n$raw"
    }
    if ($parsed.errors) {
        Write-Host "  (advarsel fra GraphQL, fortsetter): $($parsed.errors[0].message)"
    }
    return $parsed
}

function Get-IssueNodeId {
    param([string]$Repo, [int]$Number)
    return (gh issue view $Number --repo "$Org/$Repo" --json id --jq ".id")
}

Write-Host "== Del C1/C2: Issue types og Issue fields (org-niva) =="

$orgResp = Invoke-GraphQL -QueryFile (Join-Path $graphqlDir "org-id.graphql") -Variables @{ login = $Org }
$ownerId = $orgResp.data.organization.id
if (-not $ownerId) { throw "Fant ikke organisasjonen $Org - sjekk navn og at du er innlogget med riktig konto." }

# --- Issue types: Objective + Feature ---
$existingTypes = Invoke-GraphQL -QueryFile (Join-Path $graphqlDir "issue-types.graphql") -Variables @{ login = $Org }
$typeMap = @{}
foreach ($t in $existingTypes.data.organization.issueTypes.nodes) { $typeMap[$t.name] = $t.id }

$typesToCreate = @(
    @{ Name = "Objective"; Description = "Kvartalsmal et team har committet til"; Color = "PURPLE" }
    @{ Name = "Feature"; Description = "Leveranse som ruller opp til et Objective"; Color = "BLUE" }
)
foreach ($t in $typesToCreate) {
    if ($typeMap.ContainsKey($t.Name)) {
        Write-Host "  Issue type '$($t.Name)' finnes allerede - hopper over"
        continue
    }
    $resp = Invoke-GraphQL -QueryFile (Join-Path $graphqlDir "create-issue-type.graphql") -Variables @{
        ownerId     = $ownerId
        name        = $t.Name
        description = $t.Description
        color       = $t.Color
    }
    $typeMap[$t.Name] = $resp.data.createIssueType.issueType.id
    Write-Host "  opprettet issue type '$($t.Name)'"
}
$featureTypeId = $typeMap["Feature"]

# --- Issue fields: Status, Team, Kvartal (alle single-select) ---
$existingFields = Invoke-GraphQL -QueryFile (Join-Path $graphqlDir "issue-fields.graphql") -Variables @{ login = $Org }
$fieldMap = @{}
foreach ($f in $existingFields.data.organization.issueFields.nodes) {
    $fieldMap[$f.name] = $f
}

# GitHub reserverer navnet "Status" til et innebygd felt, sa det egendefinerte
# feltet heter "Leveransestatus" i stedet. Det har ogsa en norsk bokstav i ett
# av valgene ("Pa plan"), sa vi bruker indeks i options-lista (samme
# rekkefolge som i .graphql-filen) i stedet for a matche pa tekst.
if (-not $fieldMap.ContainsKey("Leveransestatus")) {
    $resp = Invoke-GraphQL -QueryFile (Join-Path $graphqlDir "create-field-status.graphql") -Variables @{ ownerId = $ownerId }
    $fieldMap["Leveransestatus"] = $resp.data.createIssueField.issueField
    Write-Host "  opprettet issue field 'Leveransestatus'"
}
else {
    Write-Host "  issue field 'Leveransestatus' finnes allerede - hopper over"
}
$statusOptionIds = @($fieldMap["Leveransestatus"].options | ForEach-Object { $_.id })
$statusFieldId = $fieldMap["Leveransestatus"].id

if (-not $fieldMap.ContainsKey("Team")) {
    $resp = Invoke-GraphQL -QueryFile (Join-Path $graphqlDir "create-field-team.graphql") -Variables @{ ownerId = $ownerId }
    $fieldMap["Team"] = $resp.data.createIssueField.issueField
    Write-Host "  opprettet issue field 'Team'"
}
else {
    Write-Host "  issue field 'Team' finnes allerede - hopper over"
}
$teamFieldId = $fieldMap["Team"].id
$teamOptionMap = @{}
foreach ($o in $fieldMap["Team"].options) { $teamOptionMap[$o.name] = $o.id }

if (-not $fieldMap.ContainsKey("Kvartal")) {
    $resp = Invoke-GraphQL -QueryFile (Join-Path $graphqlDir "create-field-kvartal.graphql") -Variables @{ ownerId = $ownerId }
    $fieldMap["Kvartal"] = $resp.data.createIssueField.issueField
    Write-Host "  opprettet issue field 'Kvartal'"
}
else {
    Write-Host "  issue field 'Kvartal' finnes allerede - hopper over"
}
$kvartalFieldId = $fieldMap["Kvartal"].id
$kvartalOptionMap = @{}
foreach ($o in $fieldMap["Kvartal"].options) { $kvartalOptionMap[$o.name] = $o.id }

Write-Host ""
Write-Host "== Del C3: setter Type + feltverdier pa de 8 issuene =="

# StatusIndex: 0=Levert, 1=Pa plan, 2=I faresonen, 3=Blokkert
# (samme rekkefolge som options i create-field-status.graphql)
$issueData = @(
    @{ Repo = "app-kompass"; Number = 1; Team = "Kompass"; Kvartal = "Q3 2026"; StatusIndex = 0; Start = "2026-07-01"; Slutt = "2026-07-31" }
    @{ Repo = "app-kompass"; Number = 2; Team = "Kompass"; Kvartal = "Q4 2026"; StatusIndex = 1; Start = "2026-10-01"; Slutt = "2026-11-15" }
    @{ Repo = "app-kompass"; Number = 3; Team = "Kompass"; Kvartal = "Q4 2026"; StatusIndex = 1; Start = "2026-10-15"; Slutt = "2026-12-01" }
    @{ Repo = "app-puls";    Number = 1; Team = "Puls";    Kvartal = "Q3 2026"; StatusIndex = 0; Start = "2026-07-01"; Slutt = "2026-08-15" }
    @{ Repo = "app-puls";    Number = 2; Team = "Puls";    Kvartal = "Q4 2026"; StatusIndex = 1; Start = "2026-10-01"; Slutt = "2026-11-30" }
    @{ Repo = "app-vega";    Number = 1; Team = "Vega";    Kvartal = "Q3 2026"; StatusIndex = 1; Start = "2026-07-15"; Slutt = "2026-09-15" }
    @{ Repo = "app-nordlys"; Number = 1; Team = "Nordlys"; Kvartal = "Q4 2026"; StatusIndex = 2; Start = "2026-10-01"; Slutt = "2026-12-15" }
    @{ Repo = "app-nordlys"; Number = 2; Team = "Nordlys"; Kvartal = "Q4 2026"; StatusIndex = 3; Start = "2026-10-01"; Slutt = "2026-12-31" }
)

$issueNodeIds = @{}
foreach ($item in $issueData) {
    $key = "$($item.Repo)#$($item.Number)"
    $issueId = Get-IssueNodeId -Repo $item.Repo -Number $item.Number
    $issueNodeIds[$key] = $issueId

    Invoke-GraphQL -QueryFile (Join-Path $graphqlDir "update-issue-type.graphql") -Variables @{
        issueId     = $issueId
        issueTypeId = $featureTypeId
    } | Out-Null

    $callSetOrUpdate = {
        param($fieldId, $optionId)
        try {
            Invoke-GraphQL -QueryFile (Join-Path $graphqlDir "set-issue-field-value.graphql") -Variables @{
                issueId  = $issueId
                fieldId  = $fieldId
                optionId = $optionId
            } | Out-Null
        }
        catch {
            Invoke-GraphQL -QueryFile (Join-Path $graphqlDir "update-issue-field-value.graphql") -Variables @{
                issueId  = $issueId
                fieldId  = $fieldId
                optionId = $optionId
            } | Out-Null
        }
    }

    & $callSetOrUpdate $statusFieldId $statusOptionIds[$item.StatusIndex]
    & $callSetOrUpdate $teamFieldId $teamOptionMap[$item.Team]
    & $callSetOrUpdate $kvartalFieldId $kvartalOptionMap[$item.Kvartal]

    Write-Host "  [$key] Type=Feature, Team=$($item.Team), Kvartal=$($item.Kvartal)"
}

Write-Host ""
Write-Host "== Del E1: blocked-by-relasjoner =="

$blockedByPairs = @(
    @{ Issue = "app-nordlys#1"; BlockedBy = "app-puls#1" }
    @{ Issue = "app-nordlys#2"; BlockedBy = "app-nordlys#1" }
)
foreach ($pair in $blockedByPairs) {
    try {
        Invoke-GraphQL -QueryFile (Join-Path $graphqlDir "add-blocked-by.graphql") -Variables @{
            issueId         = $issueNodeIds[$pair.Issue]
            blockingIssueId = $issueNodeIds[$pair.BlockedBy]
        } | Out-Null
        Write-Host "  $($pair.Issue) blocked by $($pair.BlockedBy)"
    }
    catch {
        Write-Host "  (hopper over, virker allerede satt) $($pair.Issue) blocked by $($pair.BlockedBy)"
    }
}

Write-Host ""
Write-Host "== Del D: Portefolje-prosjektet =="

$existingProjects = gh project list --owner $Org --format json | ConvertFrom-Json
$project = $existingProjects.projects | Where-Object { $_.title -eq "Portefolje" } | Select-Object -First 1
if ($project) {
    Write-Host "  Prosjektet 'Portefolje' finnes allerede (nr $($project.number)) - hopper over oppretting"
    $projectNumber = $project.number
}
else {
    $created = gh project create --owner $Org --title "Portefolje" --format json | ConvertFrom-Json
    $projectNumber = $created.number
    Write-Host "  opprettet prosjektet 'Portefolje' (nr $projectNumber)"
}

foreach ($item in $issueData) {
    $url = "https://github.com/$Org/$($item.Repo)/issues/$($item.Number)"
    gh project item-add $projectNumber --owner $Org --url $url | Out-Null
}
Write-Host "  la til alle 8 issuene i prosjektet"

Write-Host ""
Write-Host "== Del D6/D7 forberedelse: prosjekt-native felt for Group by =="
# Roadmap/Board sin "Group by" stotter (per na) bare native ProjectV2-felt,
# ikke org-niva Issue fields. Derfor dupliserer vi Team/Leveransestatus som
# egne felt pa selve prosjektet, med samme verdier som Issue fields-versjonen.
$existingProjectFields = gh project field-list $projectNumber --owner $Org --format json | ConvertFrom-Json

$teamProjField = $existingProjectFields.fields | Where-Object { $_.name -eq "Team" } | Select-Object -First 1
if (-not $teamProjField) {
    gh project field-create $projectNumber --owner $Org --name "Team" --data-type SINGLE_SELECT `
        --single-select-options "Kompass,Nordlys,Puls,Vega" | Out-Null
    Write-Host "  opprettet prosjekt-felt 'Team'"
}
else {
    Write-Host "  prosjekt-felt 'Team' finnes allerede - hopper over"
}

$statusProjField = $existingProjectFields.fields | Where-Object { $_.name -eq "Leveransestatus" } | Select-Object -First 1
if (-not $statusProjField) {
    $createdField = gh project field-create $projectNumber --owner $Org --name "Leveransestatus" --data-type SINGLE_SELECT `
        --single-select-options "Levert,Pa plan,I faresonen,Blokkert" --format json | ConvertFrom-Json
    $opt = @{}
    foreach ($o in $createdField.options) { $opt[$o.name] = $o.id }
    Invoke-GraphQL -QueryFile (Join-Path $graphqlDir "rename-leveransestatus-options.graphql") -Variables @{
        fieldId      = $createdField.id
        levertId     = $opt["Levert"]
        paaPlanId    = $opt["Pa plan"]
        faresonenId  = $opt["I faresonen"]
        blokkertId   = $opt["Blokkert"]
    } | Out-Null
    Write-Host "  opprettet prosjekt-felt 'Leveransestatus'"
    $statusProjField = gh project field-list $projectNumber --owner $Org --format json | ConvertFrom-Json |
        Select-Object -ExpandProperty fields | Where-Object { $_.name -eq "Leveransestatus" } | Select-Object -First 1
}
else {
    Write-Host "  prosjekt-felt 'Leveransestatus' finnes allerede - hopper over"
}
# Bruk felt-/opsjon-ID (ikke tekstnavn) for Leveransestatus - IDene er rene
# ASCII-strenger, sa dette er immunt mot encoding-fallgruven der "Pa plan"
# (norsk bokstav) ble korrupt nar den gikk via JSON -> kommandolinje-arg.
$statusProjFieldId = $statusProjField.id
$statusProjOptionIds = @($statusProjField.options | ForEach-Object { $_.id })

foreach ($item in $issueData) {
    $url = "https://github.com/$Org/$($item.Repo)/issues/$($item.Number)"
    gh project item-edit $projectNumber --owner $Org --url $url --field "Team" --value $item.Team | Out-Null
    gh project item-edit $projectNumber --owner $Org --url $url --field-id $statusProjFieldId --single-select-option-id $statusProjOptionIds[$item.StatusIndex] | Out-Null
}
Write-Host "  satte Team/Leveransestatus pa alle 8 prosjektradene"

Write-Host ""
Write-Host "== Del D6 forberedelse: Start-/sluttdato for Roadmap-visningen =="
# Roadmap-visningens tidslinje tegner ingen bar for et issue for du har pekt
# den til to Date-felt (Start/Target) via "Date fields" i verktoylinja.
# Kvartal er single-select (tekst), sa vi trenger egne Date-felt i tillegg.
$startProjField = $existingProjectFields.fields | Where-Object { $_.name -eq "Start dato" } | Select-Object -First 1
if (-not $startProjField) {
    gh project field-create $projectNumber --owner $Org --name "Start dato" --data-type DATE | Out-Null
    Write-Host "  opprettet prosjekt-felt 'Start dato'"
}
else {
    Write-Host "  prosjekt-felt 'Start dato' finnes allerede - hopper over"
}

$endProjField = $existingProjectFields.fields | Where-Object { $_.name -eq "Slutt dato" } | Select-Object -First 1
if (-not $endProjField) {
    gh project field-create $projectNumber --owner $Org --name "Slutt dato" --data-type DATE | Out-Null
    Write-Host "  opprettet prosjekt-felt 'Slutt dato'"
}
else {
    Write-Host "  prosjekt-felt 'Slutt dato' finnes allerede - hopper over"
}

foreach ($item in $issueData) {
    $url = "https://github.com/$Org/$($item.Repo)/issues/$($item.Number)"
    gh project item-edit $projectNumber --owner $Org --url $url --field "Start dato" --date $item.Start | Out-Null
    gh project item-edit $projectNumber --owner $Org --url $url --field "Slutt dato" --date $item.Slutt | Out-Null
}
Write-Host "  satte Start/Slutt-dato pa alle 8 prosjektradene"

Write-Host ""
Write-Host "Ferdig med automatisk oppsett."
Write-Host ""
Write-Host "Gjenstar (ma gjores i nettleseren, se STEG-FOR-STEG.md):"
Write-Host "  1. Del D6: apne Roadmap-visningen -> Date fields -> Start = 'Start dato', Target = 'Slutt dato'"
Write-Host "  2. Del D6: Group by 'Team'"
Write-Host "  3. Del D7: + New view -> Board -> Group by 'Leveransestatus'"
Write-Host "  4. Del E2: sub-issues under Betalingsflyt v1 (valgfritt)"
Write-Host "  5. Del F: koble pa dashboardet"
