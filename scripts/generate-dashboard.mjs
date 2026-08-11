#!/usr/bin/env node
/*
 * generate-dashboard.mjs
 * --------------------------------------------------------------------------
 * Henter porteføljedata fra GitHub og skriver to filer som dashboardet og et
 * GitHub-issue bruker:
 *   - data.json          → mater den interaktive siden (index.html)
 *   - dependencies.mmd   → Mermaid-diagram som limes inn i et issue / README
 *
 * Kjøres av GitHub Actions (se .github/workflows/portfolio-dashboard.yml),
 * men kan også kjøres lokalt:
 *
 *   # Ekte data (krever gh CLI v2.94+ og en innlogget token):
 *   OWNER=equinor PROJECT_NUMBER=42 node scripts/generate-dashboard.mjs
 *
 *   # Demo uten API (samme eksempeldata som ligger i index.html):
 *   node scripts/generate-dashboard.mjs --mock
 *
 * Alt henger på GitHub-primitiver som finnes i dag: Projects v2 (egendefinerte
 * felt for Team/Kvartal/Status), sub-issues (fremdrift) og issue-avhengigheter
 * ("blocked by", GA aug. 2025, eksponert som JSON i gh CLI v2.94+).
 */
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";

const MOCK = process.argv.includes("--mock");
const OWNER = process.env.OWNER;
const PROJECT_NUMBER = process.env.PROJECT_NUMBER;

/* ---- statuskartlegging: tilpass til navnene på Status-feltet deres ---- */
const STATUS_MAP = {
  "done": "done", "ferdig": "done", "levert": "done",
  "on track": "ok", "in progress": "ok", "på plan": "ok",
  "at risk": "risk", "i faresonen": "risk",
  "blocked": "blocked", "blokkert": "blocked",
};
const normStatus = (s) => STATUS_MAP[(s || "").toLowerCase().trim()] || "ok";

function gh(args) {
  return JSON.parse(execFileSync("gh", args, { encoding: "utf8", maxBuffer: 1 << 24 }));
}

/* ------------------------------------------------------------------ */
/*  REAL MODE: les fra GitHub via gh CLI                              */
/* ------------------------------------------------------------------ */
function fromGitHub() {
  if (!OWNER || !PROJECT_NUMBER) {
    throw new Error("Sett OWNER og PROJECT_NUMBER (eller kjør med --mock).");
  }

  // 1) Prosjekt-items med egendefinerte felt (Team, Kvartal, Status).
  const proj = gh([
    "project", "item-list", PROJECT_NUMBER,
    "--owner", OWNER, "--format", "json", "--limit", "200",
  ]);

  // Repo -> team, brukt til å bygge globalt unike, korte id-er (issue-numre
  // er kun unike innad i hvert repo, ikke på tvers av porteføljen).
  const repoTeam = {};
  for (const i of proj.items) {
    if (i.content?.type !== "Issue") continue;
    repoTeam[i.content.repository] = (i.team || i.content.repository || "ukjent").toString().toLowerCase();
  }
  const shortId = (repo, number) => `#${repoTeam[repo] || repo}-${number}`;

  // 2) Avhengigheter pr. issue. gh v2.94+ eksponerer disse som JSON-felt.
  //    blockedBy/subIssues er GraphQL-connections ({nodes:[...], totalCount}),
  //    ikke rene arrays.
  const repos = [...new Set(proj.items
    .map(i => i.content?.repository).filter(Boolean))];
  const deps = {};
  for (const repo of repos) {
    try {
      const issues = gh([
        "issue", "list", "--repo", repo, "--state", "all", "--limit", "200",
        "--json", "number,blockedBy,subIssues",
      ]);
      for (const it of issues) {
        const blockedByNodes = it.blockedBy?.nodes || [];
        const subNodes = it.subIssues?.nodes || [];
        deps[`${repo}#${it.number}`] = {
          blockedBy: blockedByNodes.map(b => {
            const m = b.url && b.url.match(/github\.com\/([^/]+\/[^/]+)\/issues\/(\d+)/);
            return m ? shortId(m[1], Number(m[2])) : shortId(repo, b.number);
          }),
          subs: subNodes.length
            ? [subNodes.filter(s => s.state === "CLOSED").length, subNodes.length]
            : null,
        };
      }
    } catch (e) {
      console.warn(`Klarte ikke hente avhengigheter for ${repo}: ${e.message}`);
    }
  }

  // 3) Slå sammen til dashboardets datamodell.
  const teamColors = ["#58A6FF", "#A371F7", "#3FB950", "#D29922", "#FF7B72", "#79C0FF"];
  const teamSet = new Map();
  const items = proj.items
    .filter(i => i.content?.type === "Issue")
    .map(i => {
      const c = i.content;
      const key = `${c.repository}#${c.number}`;
      const team = (i.team || c.repository || "ukjent").toString();
      if (!teamSet.has(team)) teamSet.set(team, teamColors[teamSet.size % teamColors.length]);
      const d = deps[key] || {};
      const subs = d.subs || [0, 0];
      // Feltet heter "Leveransestatus" (org-nivå), ikke "Status" - GitHub reserverer
      // det navnet for egendefinerte Issue fields.
      const progress = subs[1] ? Math.round((subs[0] / subs[1]) * 100)
        : (normStatus(i.leveransestatus) === "done" ? 100 : 0);
      return {
        id: shortId(c.repository, c.number),
        title: c.title,
        team: team.toLowerCase(),
        quarter: i.kvartal || "—",
        status: normStatus(i.leveransestatus),
        progress,
        subs,
        blockedBy: d.blockedBy || [],
        url: c.url,
      };
    });

  const teams = [...teamSet.entries()].map(([name, color]) => ({
    id: name.toLowerCase(), name, color,
  }));
  const quarters = [...new Set(items.map(i => i.quarter))].filter(q => q !== "—").sort();

  return {
    meta: { portfolio: `Prosjekt #${PROJECT_NUMBER}`, updated: new Date().toISOString().slice(0, 16).replace("T", " "), quarters },
    teams, items,
  };
}

/* ------------------------------------------------------------------ */
/*  MOCK MODE: samme eksempeldata som demo-siden                      */
/* ------------------------------------------------------------------ */
function mock() {
  return {
    meta: { portfolio: "App-portefølje", updated: "15.06.2026 07:00", quarters: ["Q3 2026", "Q4 2026"] },
    teams: [
      { id: "kompass", name: "Kompass", color: "#58A6FF" },
      { id: "nordlys", name: "Nordlys", color: "#A371F7" },
      { id: "puls", name: "Puls", color: "#3FB950" },
      { id: "vega", name: "Vega", color: "#D29922" },
    ],
    items: [
      { id: "#103", title: "Innlogging & SSO", team: "kompass", quarter: "Q3 2026", status: "done", progress: 100, subs: [8, 8], blockedBy: [] },
      { id: "#150", title: "Betalingsflyt v1", team: "kompass", quarter: "Q4 2026", status: "ok", progress: 70, subs: [7, 12], blockedBy: ["#103"] },
      { id: "#190", title: "Innstillinger & profil", team: "kompass", quarter: "Q4 2026", status: "ok", progress: 40, subs: [3, 9], blockedBy: [] },
      { id: "#142", title: "Plattform-API", team: "puls", quarter: "Q3 2026", status: "done", progress: 100, subs: [10, 10], blockedBy: [] },
      { id: "#175", title: "Push-varsler", team: "puls", quarter: "Q4 2026", status: "ok", progress: 55, subs: [4, 8], blockedBy: [] },
      { id: "#160", title: "Dashboard MVP", team: "vega", quarter: "Q3 2026", status: "ok", progress: 85, subs: [6, 7], blockedBy: [] },
      { id: "#168", title: "Offline-modus", team: "nordlys", quarter: "Q4 2026", status: "risk", progress: 45, subs: [4, 10], blockedBy: ["#142"] },
      { id: "#181", title: "Synk & konflikthåndtering", team: "nordlys", quarter: "Q4 2026", status: "blocked", progress: 0, subs: [0, 6], blockedBy: ["#168"] },
    ],
  };
}

/* ------------------------------------------------------------------ */
/*  Mermaid-generator: skrives inn i et issue og renderes av GitHub   */
/* ------------------------------------------------------------------ */
function toMermaid(data) {
  const cls = { done: "done", ok: "ok", risk: "risk", blocked: "blocked" };
  const byId = (id) => data.items.find((i) => i.id === id);
  const def = (it) => `  n${it.id.slice(1)}["${it.id} ${it.title}"]:::${cls[it.status]}`;
  const lines = ["```mermaid", "flowchart LR"];
  let edges = 0;
  for (const it of data.items) {
    for (const b of it.blockedBy) {
      const from = byId(b);
      if (from) { lines.push(`${def(from)} --> ${def(it)}`); edges++; }
    }
  }
  if (!edges) lines.push("  cleared[Ingen aktive avhengigheter]:::ok");
  lines.push(
    "  classDef done fill:#13263c,stroke:#58A6FF,color:#cde;",
    "  classDef ok fill:#15301f,stroke:#3FB950,color:#cfe;",
    "  classDef risk fill:#352a18,stroke:#D29922,color:#fed;",
    "  classDef blocked fill:#3a1d1d,stroke:#F85149,color:#fdd;",
    "```",
  );
  return lines.join("\n");
}

/* ---- run ---- */
const data = MOCK ? mock() : fromGitHub();
writeFileSync("data.json", JSON.stringify(data, null, 2));
writeFileSync("dependencies.mmd", toMermaid(data) + "\n");
console.log(`Skrev data.json (${data.items.length} items) og dependencies.mmd${MOCK ? " [mock]" : ""}.`);
