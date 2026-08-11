# seed.ps1 — oppretter fire dummy-team (repoer) og åtte dummy-issues
# i en GitHub-organisasjon, som utgangspunkt for Nooga-erstatnings-POC-en.
#
# Bruk (fra VS Code-terminalen, PowerShell):
#   .\scripts\seed.ps1 -Org Andreas-Sandbox
#
# Krever: gh CLI, innlogget (gh auth login + gh auth refresh -s project)

param(
    [Parameter(Mandatory = $true)]
    [string]$Org
)

$ErrorActionPreference = "Stop"
# I PowerShell 7.3+ ma denne vaere $false, ellers blir ikke-null exit code fra
# native kommandoer (som "gh repo view" pa et repo som ikke finnes enna) kastet
# som en terminerende feil, selv om stderr er omdirigert med 2>$null.
$PSNativeCommandUseErrorActionPreference = $false

Write-Host "Oppretter fire dummy-team-repoer i $Org ..."
$repos = @("app-kompass", "app-nordlys", "app-puls", "app-vega")

foreach ($r in $repos) {
    # gh sin stderr-linje ("kunne ikke finne repo") blir ogsaa en terminerende feil
    # naar $ErrorActionPreference = "Stop", sjol om den er omdirigert med 2>$null.
    # Fang den i stedet - den betyr bare at repoet ikke finnes enna.
    $repoExists = $false
    try {
        gh repo view "$Org/$r" 2>$null | Out-Null
        $repoExists = ($LASTEXITCODE -eq 0)
    }
    catch {
        $repoExists = $false
    }

    if ($repoExists) {
        Write-Host "  $Org/$r finnes allerede - hopper over"
    }
    else {
        gh repo create "$Org/$r" --private -y `
            --description "Dummy-team for GitHub Projects-POC (Nooga-erstatning)" | Out-Null
        Write-Host "  opprettet $Org/$r"
    }
}

Write-Host "Oppretter atte dummy-issues ..."

function New-DummyIssue {
    param([string]$Repo, [string]$Title, [string]$Body)
    gh issue create --repo "$Org/$Repo" --title "$Title" --body "$Body" | Out-Null
    Write-Host "  [$Repo] $Title"
}

# Kompass
New-DummyIssue -Repo "app-kompass" -Title "Innlogging & SSO" `
    -Body "Committet Q3 2026. Status: Levert."
New-DummyIssue -Repo "app-kompass" -Title "Betalingsflyt v1" `
    -Body "Committet Q4 2026. Avhenger av Innlogging & SSO."
New-DummyIssue -Repo "app-kompass" -Title "Innstillinger & profil" `
    -Body "Committet Q4 2026."

# Puls
New-DummyIssue -Repo "app-puls" -Title "Plattform-API" `
    -Body "Committet Q3 2026. Status: Levert. Andre team avhenger av denne."
New-DummyIssue -Repo "app-puls" -Title "Push-varsler" `
    -Body "Committet Q4 2026."

# Vega
New-DummyIssue -Repo "app-vega" -Title "Dashboard MVP" `
    -Body "Committet Q3 2026."

# Nordlys
New-DummyIssue -Repo "app-nordlys" -Title "Offline-modus" `
    -Body "Committet Q4 2026. Avhenger av Plattform-API (Puls) - sett som 'blocked by' manuelt."
New-DummyIssue -Repo "app-nordlys" -Title "Synk & konflikthandtering" `
    -Body "Committet Q4 2026. Avhenger av Offline-modus - sett som 'blocked by' manuelt."

Write-Host ""
Write-Host "Ferdig. 4 repoer og 8 issues opprettet i $Org."
Write-Host ""
Write-Host "Neste steg (se STEG-FOR-STEG.md del C og D):"
Write-Host "  1. Sett opp Issue types (Objective, Feature) under org Settings > Planning"
Write-Host "  2. Sett opp Issue fields (Status, Team, Kvartal) under org Settings > Planning"
Write-Host "  3. Opprett Portefolje-prosjektet og legg til de 8 issuene"
Write-Host "  4. Sett feltverdier og 'blocked by'-relasjonene i prosjektets tabellvisning"
