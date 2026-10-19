// check-voice.mjs: reads the site copy and points at lines that sound
// machine-written. It reports and nothing else. It never edits a file.
//
//   node check-voice.mjs              every page, worst first
//   node check-voice.mjs routes       one page (any part of its name)
//   node check-voice.mjs --summary    just the league table
//
// The checks come from the voice notes: dashes, stock phrases, lists of
// three, hedging, paragraphs that end on reassurance, long words, long
// sentences and reading grade. It also enforces the one hard rule: DEIS
// is never said on a student-facing page.
//
// A flag is a prompt to look, not a verdict. Ignore any you disagree with.
//
// Lines Jack typed himself in the CMS are his voice, not AI, so they are
// left out (git blame: Decap CMS commits are titled "Update ..."). The DEIS
// rule still applies to them. --all shows them too.
//
// A small fix to one of his lines (a typo) would otherwise make git credit
// the whole line to that fix. List such commits in .git-blame-ignore-revs
// and the line stays his.

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";

// ---------------------------------------------------------------------------
// Which pages are which. Student pages get the strictest checks.

const AUDIENCE = {
  index: "student", routes: "student", funding: "student", careers: "student",
  members: "student", sectors: "student",
  mentors: "adult", schools: "adult", businesses: "adult", about: "adult",
  terms: "legal", privacy: "legal", safeguarding: "legal",
};
// The only pages allowed to say DEIS.
const DEIS_ALLOWED = new Set(["schools", "businesses", "privacy"]);
const TARGET_GRADE = 7;   // student pages, Flesch-Kincaid
const GRADE_FLAG = 9;     // a little leeway before a paragraph is flagged

// Keys that hold codes, links or dates rather than prose.
const SKIP_KEYS = new Set(["slug", "url", "href", "checked", "marker", "places",
  "attribution", "value", "duration", "cost"]);

// ---------------------------------------------------------------------------
// The word lists. Each entry: pattern, and what to do about it.

const STOCK = [
  [/\bit(?:'|’)?s important to note\b|\bit is important to note\b/i, "cut it and say the thing"],
  [/\b(?:it(?:'|’)?s |it is )?worth noting\b/i, "cut it and say the thing"],
  [/\bit should be noted\b/i, "cut it and say the thing"],
  [/\bthat said\b|\bhaving said that\b|\bwith that said\b/i, "pick a side instead of balancing"],
  [/\bneedless to say\b/i, "then don't say it"],
  [/\bat the end of the day\b/i, "cliché"],
  [/\bin today(?:'|’)?s\b/i, "cliché opener"],
  [/\bwhen it comes to\b/i, "start with the subject itself"],
  [/\bwhether you(?:'|’)?re\b|\bwhether you are\b/i, "talks to everyone, so to no one"],
  [/\bsomething for every(?:one|body)\b|\bthere(?:'|’)?s something that\b|\bmatches any\b/i, "brochure filler"],
  [/\bno matter (?:what|who|where|how)\b/i, "brochure filler"],
  [/\ba wide (?:range|variety) of\b|\ba variety of\b/i, "say what they are"],
  [/\bplays? an? (?:key|vital|crucial|important|pivotal) role\b/i, "say what it does"],
  [/\b(?:is|are|it(?:'|’)?s|isn(?:'|’)?t|aren(?:'|’)?t) not (?:just|only|merely) about\b|\bnot just about\b|\bmore than just\b/i, "the 'not just X but Y' move"],
  [/\bthe power of\b/i, "brochure filler"],
  [/\b(?:deep )?dive into\b|\bdelve\b/i, "AI favourite"],
  [/\bnavigat(?:e|ing)\b/i, "AI favourite; try 'get through' or 'work out'"],
  [/\blandscape\b/i, "AI favourite"],
  [/\bjourney\b/i, "inspirational filler"],
  [/\bempower\w*/i, "inspirational filler"],
  [/\bunlock\w*/i, "inspirational filler"],
  [/\b(?:full |your |their )potential\b/i, "inspirational filler"],
  [/\bthriv\w+/i, "inspirational filler"],
  [/\bembark\w*/i, "inspirational filler"],
  [/\belevat\w+/i, "inspirational filler"],
  [/\bfoster\w*/i, "AI favourite"],
  [/\bleverag\w+/i, "corporate"],
  [/\bseamless\w*/i, "corporate"],
  [/\brobust\b/i, "corporate"],
  [/\bholistic\b/i, "corporate"],
  [/\btailored\b/i, "corporate"],
  [/\bcutting[- ]edge\b|\bgame[- ]changer\b|\bever[- ]evolving\b/i, "corporate"],
  [/\binvaluable\b|\bcomprehensive\b/i, "puffed up; say what is in it"],
  [/\bcrucial\b|\bvital\b|\bpivotal\b|\bessential\b/i, "everything is crucial in AI copy; show why instead"],
  [/\bpassionate\b|\bdedicated to\b|\bcommitted to\b|\bstrive\w*/i, "mission-statement voice"],
  [/\brest assured\b|\bdon(?:'|’)?t worry\b|\bwe(?:'|’)?ve got you\b|\bevery step of the way\b/i, "reassurance"],
  [/\bhere to help\b|\bhere for you\b/i, "reassurance"],
  [/(?:^|[.!?]\s+)(?:Additionally|Furthermore|Moreover|In conclusion|Ultimately|Overall|In summary|Finally|Importantly),/, "essay connective; just start the sentence"],
];

const LONG_WORDS = {
  frequently: "often", considerably: "a lot / much", precisely: "exactly",
  utilise: "use", utilize: "use", utilising: "using", additionally: "also",
  numerous: "many", commence: "start", approximately: "about",
  individuals: "people", facilitate: "help", regarding: "about",
  assist: "help", obtain: "get", subsequently: "then / later",
  sufficient: "enough", require: "need", requires: "needs",
  purchase: "buy", demonstrate: "show", possess: "have",
  endeavour: "try", currently: "now", therefore: "so",
  nevertheless: "still", significant: "big", significantly: "a lot",
  whereby: "where", aforementioned: "that", ensure: "make sure",
  "prior to": "before", "in order to": "to", "a number of": "some",
};

const HEDGES = /\b(?:may|might|could|often|usually|generally|typically|perhaps|possibly|potentially|arguably|somewhat|tend to|tends to|likely|in some cases|in many cases)\b/gi;

const REASSURE = /\b(?:don(?:'|’)?t worry|here to help|help you|support you|you(?:'|’)?re not alone|it(?:'|’)?s (?:ok|okay|fine)|there(?:'|’)?s always|no matter|anyone can|you can do (?:it|this)|you(?:'|’)?ve got this|rest assured|every step|right for you|matches any|something for)\b/i;

const DEFICIT = /\b(?:DEIS|disadvantaged|underprivileged|less fortunate|deprived|at[- ]risk)\b/i;

// ---------------------------------------------------------------------------
// Text helpers

const words = (s) => s.match(/[A-Za-z0-9][A-Za-z0-9'’-]*/g) || [];

function sentences(s) {
  return s.split(/(?<=[.!?…])["'’”)]*\s+(?=["'‘“(]?[A-Z0-9])|\n+/)
    .map((x) => x.trim()).filter(Boolean);
}

function syllables(w) {
  w = w.toLowerCase().replace(/[^a-z]/g, "");
  if (!w) return 0;
  if (w.length <= 3) return 1;
  w = w.replace(/(?:[^laeiouy]es|[^laeiouy]ed|[^laeiouy]e)$/, "").replace(/^y/, "");
  const groups = w.match(/[aeiouy]{1,2}/g);
  return Math.max(1, groups ? groups.length : 1);
}

function grade(text) {
  const ws = words(text);
  const ss = sentences(text).filter((s) => words(s).length);
  if (!ws.length || !ss.length) return null;
  const syl = ws.reduce((n, w) => n + syllables(w), 0);
  return 0.39 * (ws.length / ss.length) + 11.8 * (syl / ws.length) - 15.59;
}

// ---------------------------------------------------------------------------
// CMS labels, read from admin/config.yml so locations match the boxes Jack
// sees. Anything not found falls back to the raw key name.

function readCmsLabels() {
  const files = {};
  let lines;
  try { lines = readFileSync("admin/config.yml", "utf8").split("\n"); }
  catch { return files; }
  let stack = [];
  let current = null;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const m = line.match(/^(\s*)- (?:\{\s*)?name:\s*["']?([\w-]+)/);
    if (m) {
      const indent = m[1].length;
      const inline = line.match(/label:\s*"([^"]*)"/);
      const next = (lines[i + 1] || "").match(/^\s*label:\s*"?([^"\n]*)"?/);
      const node = { name: m[2], label: inline ? inline[1] : next ? next[1].trim() : m[2], kids: {} };
      while (stack.length && stack[stack.length - 1].indent >= indent) stack.pop();
      if (stack.length) stack[stack.length - 1].node.kids[node.name] = node;
      stack.push({ indent, node });
      current = node;
      continue;
    }
    const f = line.match(/^\s*file:\s*"content\/(?:pages\/)?([\w-]+)\.(?:json|md)"/);
    if (f && current) files[f[1]] = current;
  }
  return files;
}

const CMS = readCmsLabels();
const FALLBACK = { safeguarding: "Safeguarding statement" };
const pageLabel = (name) => (CMS[name]?.label || FALLBACK[name] || name).replace(/\s*\((?:legal|shown)[^)]*\)/i, "");

// ---------------------------------------------------------------------------
// Collect the prose: one entry per box (JSON) or paragraph (markdown).

function itemName(obj, i) {
  return obj.title || obj.name || obj.heading || obj.myth || obj.label || obj.slug || `#${i + 1}`;
}

// For each line of a file: did one of Jack's CMS saves write it? Returns
// null if git is not available, and then nothing is treated as his.
const CMS_COMMIT = /^(?:Update|Create) /;
function cmsLines(file) {
  try {
    const flags = ["blame", "--line-porcelain"];
    if (existsSync(".git-blame-ignore-revs")) flags.push("--ignore-revs-file", ".git-blame-ignore-revs");
    const out = execFileSync("git", [...flags, "--", file],
      { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], maxBuffer: 1 << 26 });
    const mine = [];
    let summary = "";
    for (const line of out.split("\n")) {
      if (line.startsWith("summary ")) summary = line.slice(8);
      else if (line.startsWith("\t")) mine.push(CMS_COMMIT.test(summary));
    }
    return mine;
  } catch {
    return null;
  }
}

function collectJson(name) {
  const data = JSON.parse(readFileSync(`content/${name}.json`, "utf8"));
  const out = [];
  const walk = (v, key, node, where) => {
    if (SKIP_KEYS.has(key)) return;
    if (typeof v === "string") {
      if (v.trim()) out.push({ where: where.join(" › "), key, text: v });
    } else if (Array.isArray(v)) {
      v.forEach((x, i) => walk(x, key, node, x && typeof x === "object" ? [...where, itemName(x, i)] : where));
    } else if (v && typeof v === "object") {
      for (const [k, vv] of Object.entries(v)) {
        const kid = node?.kids?.[k];
        walk(vv, k, kid, [...where, kid?.label || k]);
      }
    }
  };
  walk(data, "", CMS[name], []);
  // Lists add the list label and then the item name; for strings the last
  // step is the field. Tidy "Points › Points" style repeats.
  for (const o of out) o.where = o.where.replace(/(\b[^›]+) › \1\b/g, "$1");
  const lines = readFileSync(`content/${name}.json`, "utf8").split("\n");
  const his = cmsLines(`content/${name}.json`);
  for (const o of out) {
    const at = lines.findIndex((l) => l.includes(JSON.stringify(o.text)));
    o.yours = !!(his && at >= 0 && his[at]);
  }
  return out;
}

function collectMarkdown(name) {
  const md = readFileSync(`content/pages/${name}.md`, "utf8");
  const his = cmsLines(`content/pages/${name}.md`);
  const out = [];
  let heading = "top of page";
  let buf = [], start = 0;
  const flush = () => {
    if (!buf.length) return;
    let text = buf.reduce((acc, line) => {
      const l = line.replace(/^>\s?/, "");
      return acc && !/^\s*(?:[-*+|]|\d+\.)\s/.test(l) ? `${acc} ${l.trim()}` : `${acc}\n${l}`;
    }, "")
      .replace(/^\s*\|\s*|\s*\|\s*$/gm, "").replace(/\s*\|\s*/g, ". ")
      .replace(/^\s*(?:[-*+]|\d+\.)\s+/gm, "")
      .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
      .replace(/[*_`]+/g, "")
      .trim();
    if (text) out.push({ where: `under "${heading}" (line ${start})`, key: "text", text,
                         yours: !!(his && his[start - 1]) });
    buf = [];
  };
  md.split("\n").forEach((line, i) => {
    const h = line.match(/^#{1,6}\s+(.*)/);
    if (h) { flush(); heading = h[1].trim(); return; }
    if (!line.trim() || /^>\s*$/.test(line)) { flush(); return; }
    if (!buf.length) start = i + 1;
    buf.push(line);
  });
  flush();
  return out;
}

// Jack's own words are never judged. The founder statement lives in
// mentors.json and is quoted on the About page.
function founderText() {
  try {
    const q = JSON.parse(readFileSync("content/mentors.json", "utf8")).quote;
    return [q?.body, q?.attribution].filter(Boolean).map(norm);
  } catch { return []; }
}
function norm(s) { return s.replace(/\s+/g, " ").replace(/[—–-]\s*Jack, founder.*$/, "").trim(); }
const FOUNDER = founderText();
const isFounder = (text) => /^[—–-]\s*Jack, founder/.test(text.trim()) ||
  FOUNDER.some((f) => f && norm(text).includes(f.slice(0, 120)));

// ---------------------------------------------------------------------------
// The checks

const WH = /^(?:how|what|who|why|where|when|which|whether|to)$/i;

// "A, B and C" where the items are short, or where a long lead-in ends in
// the first item and the other two are visibly parallel ("how they got it,
// and what they would do").
function triads(sentence) {
  const found = [];
  for (const clause of sentence.split(/[;:—–()]|\s-\s/)) {
    const m = clause.match(/^(.*?)\s(and|or)\s([^,]+)$/i);
    if (!m) continue;
    const parts = m[1].split(/,\s*/).filter((x) => words(x).length);
    if (parts.length < 2) continue;
    const last = words(m[3]);
    const mid = words(parts[parts.length - 1]);
    const first = words(parts[parts.length - 2]);
    if (parts.length > 2 && words(parts[parts.length - 3]).length <= 4) continue; // four or more items
    const short = first.length <= 4 && mid.length <= 4 && last.length <= 4;
    const parallel = mid.length && last.length &&
      (mid[0].toLowerCase() === last[0].toLowerCase() || (WH.test(mid[0]) && WH.test(last[0])));
    if (short || parallel) {
      const lead = short ? parts[parts.length - 2].trim() : `… ${first.slice(-2).join(" ")}`;
      found.push(`${lead}, ${mid.join(" ")} ${m[2]} ${last.slice(0, 5).join(" ")}`);
    }
  }
  return found;
}

function check(page, entry) {
  const aud = AUDIENCE[page] || "adult";
  const { text, key } = entry;
  const hits = [];
  const add = (type, snippet, note) => hits.push({ type, snippet: snippet.trim(), note });
  const ss = sentences(text);
  const wc = words(text).length;
  const prose = wc >= 8;      // titles and labels get the light checks only

  // The hard rule.
  if (!DEIS_ALLOWED.has(page)) {
    const m = text.match(DEFICIT);
    if (m && m[0].toUpperCase() === "DEIS") {
      add("rule", sentenceWith(ss, m[0]), "DEIS named on a page students can read. House rule: only schools, businesses and privacy");
    } else if (m && aud === "student") {
      add("framing", sentenceWith(ss, m[0]), `"${m[0]}" frames the reader. Keep it only if it is the official wording`);
    }
  }

  // Dashes doing a comma's job.
  for (const s of ss) {
    if (!/\s[—–-]\s|—|–|\s--\s/.test(s)) continue;
    const lead = s.split(/\s[—–-]\s|[—–]/)[0];
    const definition = words(lead).length <= 5 && s.split(/[—–]|\s-\s/).length === 2;
    if (!definition) add("dash", s, "swap for a full stop, comma or brackets");
  }

  for (const [re, note] of STOCK) {
    if (aud === "legal" && /corporate|everything is crucial|puffed/.test(note)) continue;
    const m = text.match(re);
    if (m) add("phrase", sentenceWith(ss, m[0]), `"${m[0].replace(/^[.!?]\s+/, "")}": ${note}`);
  }

  if (aud !== "legal") {
    for (const [long, short] of Object.entries(LONG_WORDS)) {
      const m = text.match(new RegExp(`\\b${long}\\b`, "i"));
      if (m) add("word", sentenceWith(ss, m[0]), `"${m[0]}" → ${short}`);
    }
  }

  if (!prose || aud === "legal") return hits;

  if (key !== "label") for (const s of ss) for (const t of triads(s)) add("three", s, `list of three: ${t}`);
  for (let i = 0; i + 2 < ss.length; i++) {
    const a = words(ss[i])[0], b = words(ss[i + 1])[0], c = words(ss[i + 2])[0];
    if (a && a === b && b === c && words(ss[i + 3] || "")[0] !== a) {
      add("three", `${ss[i]} ${ss[i + 1]} ${ss[i + 2]}`, `three sentences in a row starting "${a}"`);
    }
  }

  const hedges = text.match(HEDGES) || [];
  if (hedges.length >= 3) add("hedge", firstWords(text, 18), `${hedges.length} hedges: ${[...new Set(hedges.map((h) => h.toLowerCase()))].join(", ")}`);

  if (ss.length >= 2 && REASSURE.test(ss[ss.length - 1])) {
    add("reassure", ss[ss.length - 1], "the paragraph ends by reassuring. End on the fact instead");
  }

  const limit = aud === "student" ? 25 : 30;
  for (const s of ss) {
    const n = words(s).length;
    if (n > limit) add("long", s, `${n} words in one sentence`);
  }

  if (aud === "student" && wc >= 25) {
    const g = grade(text);
    if (g !== null && g > GRADE_FLAG) add("grade", firstWords(text, 18), `reads at grade ${g.toFixed(1)} (aim about ${TARGET_GRADE})`);
  }
  return hits;
}

function sentenceWith(ss, needle) {
  const n = needle.toLowerCase().replace(/^[.!?]\s+/, "");
  return ss.find((s) => s.toLowerCase().includes(n)) || n;
}
function firstWords(text, n) {
  const w = text.replace(/\s+/g, " ").split(" ");
  return w.length > n ? w.slice(0, n).join(" ") + " …" : text;
}

// ---------------------------------------------------------------------------
// Run

const KINDS = {
  rule:     "DEIS named on a page students can read (house rule)",
  framing:  "deficit wording on a student page",
  dash:     "dash doing a comma's job",
  phrase:   "stock AI phrase",
  word:     "a shorter word would do",
  three:    "list of three",
  hedge:    "too much hedging",
  reassure: "ends on reassurance",
  long:     "long sentence",
  grade:    "reading grade too high",
};

const args = process.argv.slice(2);
const summaryOnly = args.includes("--summary");
const showAll = args.includes("--all");
const filter = args.find((a) => !a.startsWith("--"))?.toLowerCase();
const tty = process.stdout.isTTY;
const c = (code, s) => (tty ? `\x1b[${code}m${s}\x1b[0m` : s);

const pages = [
  ...readdirSync("content").filter((f) => f.endsWith(".json")).map((f) => [f.slice(0, -5), "json"]),
  ...readdirSync("content/pages").filter((f) => f.endsWith(".md")).map((f) => [f.slice(0, -3), "md"]),
].filter(([n]) => !filter || n.includes(filter) || pageLabel(n).toLowerCase().includes(filter));

if (!pages.length) {
  console.log(`No page matches "${filter}".`);
  process.exit(0);
}

const report = pages.map(([name, kind]) => {
  const entries = (kind === "json" ? collectJson(name) : collectMarkdown(name)).filter((e) => !isFounder(e.text));
  // His lines keep only the house rule; every other flag on them is his style.
  const all = entries.map((e) => {
    const hits = check(name, e);
    return { ...e, hits: e.yours && !showAll ? hits.filter((h) => h.type === "rule") : hits };
  });
  const theirs = entries.filter((e) => !e.yours);
  const wc = theirs.reduce((n, e) => n + words(e.text).length, 0);
  const yoursWc = entries.length ? entries.reduce((n, e) => n + words(e.text).length, 0) - wc : 0;
  const prose = entries.filter((e) => words(e.text).length >= 25).map((e) => e.text).join("\n");
  const flags = all.filter((e) => !e.yours).reduce((n, e) => n + e.hits.length, 0);
  const file = kind === "json" ? `content/${name}.json` : `content/pages/${name}.md`;
  return { name, file, aud: AUDIENCE[name] || "adult", all, wc, yoursWc, flags,
           per100: wc ? (flags / wc) * 100 : 0, grade: grade(prose) };
}).sort((a, b) => b.per100 - a.per100);

console.log(c(1, "\nVoice check: report only, nothing has been changed\n"));
console.log("Worst first. 'per 100' is flags per hundred words: a rough guide, not a score.");
console.log(showAll
  ? "Including lines you wrote yourself in the CMS, marked (yours).\n"
  : "Lines you wrote yourself in the CMS are left out ('yours' column). Add --all to include them.\n");
console.log(c(2, "  page".padEnd(46) + "audience  words  yours  flags  per 100  grade"));
for (const p of report) {
  const g = p.grade === null ? "  -" : p.grade.toFixed(1).padStart(5);
  const gc = p.aud === "student" && p.grade > GRADE_FLAG ? c(33, g) : g;
  console.log(`  ${pageLabel(p.name).slice(0, 42).padEnd(44)}${p.aud.padEnd(9)}${String(p.wc).padStart(6)}${String(p.yoursWc).padStart(7)}${String(p.flags).padStart(7)}${p.per100.toFixed(1).padStart(9)}  ${gc}`);
}
console.log(c(2, `\n  Grade is Flesch-Kincaid for the longer paragraphs. Student pages aim for about ${TARGET_GRADE}.`));
console.log(c(2, "  Legal pages get the dash and stock-phrase checks only."));
console.log(c(2, "  'words' counts copy not written by you; 'yours' counts the words you wrote."));

if (summaryOnly) process.exit(0);

for (const p of report) {
  const withHits = p.all.filter((e) => e.hits.length);
  if (!withHits.length) continue;
  const shown = withHits.reduce((n, e) => n + e.hits.length, 0);
  console.log("\n" + c(1, `━━ ${pageLabel(p.name)} `) + c(2, `(${shown} flags, ${p.file})`));
  for (const e of withHits) {
    console.log("\n  " + c(36, e.where || "(top level)") + (e.yours ? c(2, "  (yours)") : ""));
    for (const h of e.hits) {
      const tag = h.type === "rule" ? c(31, `[${h.type}]`) : c(33, `[${h.type}]`);
      console.log(`    ${tag} ${h.note}`);
      console.log(c(2, `        "${h.snippet.length > 220 ? h.snippet.slice(0, 220) + " …" : h.snippet}"`));
    }
  }
}

console.log(c(1, "\nWhat the tags mean"));
for (const [k, v] of Object.entries(KINDS)) console.log(`  ${k.padEnd(9)} ${v}`);
console.log("");
