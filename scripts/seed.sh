#!/usr/bin/env bash
# seed.sh — oppretter fire dummy-team (repoer) og åtte dummy-issues
# i en GitHub-organisasjon, som utgangspunkt for Nooga-erstatnings-POC-en.
#
# Bruk:
#   chmod +x scripts/seed.sh
#   ./scripts/seed.sh <org-navn>
#
# Krever: gh CLI, innlogget (`gh auth login` + `gh auth refresh -s project`)
set -euo pipefail

ORG="${1:?Bruk: ./seed.sh <org-navn>}"

echo "Oppretter fire dummy-team-repoer i $ORG ..."
repos=(app-kompass app-nordlys app-puls app-vega)
for r in "${repos[@]}"; do
  if gh repo view "$ORG/$r" >/dev/null 2>&1; then
    echo "  $ORG/$r finnes allerede — hopper over"
  else
    gh repo create "$ORG/$r" --private -y \
      --description "Dummy-team for GitHub Projects-POC (Nooga-erstatning)"
    echo "  opprettet $ORG/$r"
  fi
done

echo "Oppretter åtte dummy-issues ..."

create_issue () {
  local repo="$1" title="$2" body="$3"
  gh issue create --repo "$ORG/$repo" --title "$title" --body "$body" >/dev/null
  echo "  [$repo] $title"
}

# Kompass
create_issue app-kompass "Innlogging & SSO" \
  "Committet Q3 2026. Status: Levert."
create_issue app-kompass "Betalingsflyt v1" \
  "Committet Q4 2026. Avhenger av Innlogging & SSO."
create_issue app-kompass "Innstillinger & profil" \
  "Committet Q4 2026."

# Puls
create_issue app-puls "Plattform-API" \
  "Committet Q3 2026. Status: Levert. Andre team avhenger av denne."
create_issue app-puls "Push-varsler" \
  "Committet Q4 2026."

# Vega
create_issue app-vega "Dashboard MVP" \
  "Committet Q3 2026."

# Nordlys
create_issue app-nordlys "Offline-modus" \
  "Committet Q4 2026. Avhenger av Plattform-API (Puls) — sett som 'blocked by' manuelt."
create_issue app-nordlys "Synk & konflikthåndtering" \
  "Committet Q4 2026. Avhenger av Offline-modus — sett som 'blocked by' manuelt."

cat <<EOF

Ferdig. 4 repoer og 8 issues opprettet i $ORG.

Neste steg (se STEG-FOR-STEG.md del C og D):
  1. Sett opp Issue types (Objective, Feature) under org Settings > Planning
  2. Sett opp Issue fields (Status, Team, Kvartal) under org Settings > Planning
  3. Opprett Portefølje-prosjektet og legg til de 8 issuene
  4. Sett feltverdier og 'blocked by'-relasjonene i prosjektets tabellvisning
EOF
