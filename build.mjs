// ===========================================================================
// Builds a real HTML file for every guide page.
//
// Why this exists: the guides are rendered in the browser from JSON, which
// means every /routes/*, /funding/* and /careers/* URL served Google the
// same empty template with the same title. Nine duplicate blank pages, and
// the best content on the site invisible to search.
//
// This runs on every deploy, so a CMS edit still ends up in the HTML.
// No dependencies - plain Node.
// ===========================================================================
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";

const SECTIONS = ["routes", "funding", "careers"];
const SITE = "https://socialcapital.ie";

const esc = (v) =>
  String(v ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

const paras = (t) =>
  String(t || "").split(/\n\s*\n/).filter(Boolean)
    .map((p) => `<p>${esc(p).replace(/\n/g, "<br>")}</p>`).join("");

function body(item, section) {
  const facts = (item.facts || []).length
    ? `<dl class="fact-grid">${item.facts.map((f) =>
        `<div><dt>${esc(f.label)}</dt><dd>${esc(f.value)}</dd></div>`).join("")}</dl>`
    : "";

  const routes = (item.routes || []).length
    ? `<h2>Ways in</h2><p class="pw-note">There is more than one. None of these is the "proper" one.</p>` +
      item.routes.map((r) =>
        `<div class="route"><div class="route-head"><h3>${esc(r.name)}</h3>` +
        (r.tag ? `<span class="route-tag">${esc(r.tag)}</span>` : "") +
        `</div>${paras(r.detail)}<dl class="route-facts">` +
        (r.duration ? `<div><dt>How long</dt><dd>${esc(r.duration)}</dd></div>` : "") +
        (r.cost ? `<div><dt>What it costs</dt><dd>${esc(r.cost)}</dd></div>` : "") +
        `</dl></div>`).join("")
    : "";

  const blocks = (item.blocks || [])
    .map((b) => `<h2>${esc(b.heading)}</h2>${paras(b.text)}`).join("");

  const myths = (item.myths || []).length
    ? `<h2>What people get wrong</h2>` + item.myths.map((m) =>
        `<div class="myth"><p class="myth-claim">“${esc(m.myth)}”</p>` +
        `<p class="myth-reality">${esc(m.reality)}</p></div>`).join("")
    : "";

  const links = (item.apply || []).length
    ? `<h2>Where to go next</h2><ul class="pw-links">` + item.apply.map((l) =>
        `<li><a href="${esc(l.url)}" rel="noopener">${esc(l.label)}</a></li>`).join("") + `</ul>`
    : "";

  const related = (item.related || []).length
    ? `<div class="related"><p class="pw-kicker">Read next</p><ul>` + item.related.map((r) =>
        `<li><a href="${esc(r.href)}">${esc(r.label)}</a></li>`).join("") + `</ul></div>`
    : "";

  return `<p class="pw-kicker">${esc(section.title || "")}` +
    (item.subtitle ? ` · ${esc(item.subtitle)}` : "") + `</p>` +
    `<h1>${esc(item.title)}</h1>` +
    `<p class="pw-summary">${esc(item.summary)}</p>` +
    facts + paras(item.body) + routes + blocks + myths + links + related +
    `<div class="pw-cta"><h2>Talk to someone who did it</h2>` +
    `<p>These pages tell you how it works. A person can tell you what it was ` +
    `actually like. Mentor profiles are open to registered schools.</p>` +
    `<a class="btn" href="/schools.html">How schools register</a></div>` +
    (item.checked
      ? `<p class="pw-checked">Information checked ${esc(item.checked)}. Requirements, ` +
        `fees and deadlines change — always confirm with the official sources ` +
        `linked above before making a decision.</p>`
      : "");
}

const template = readFileSync("guide.html", "utf8");
let built = 0;

for (const name of SECTIONS) {
  const data = JSON.parse(readFileSync(`content/${name}.json`, "utf8"));
  const section = data.section || {};

  for (const item of data.items || []) {
    const title = `${item.title} — Social Capital`;
    const desc = (item.summary || "").slice(0, 300);
    const url = `${SITE}/${name}/${item.slug}`;

    let html = template
      .replace(/<title>[^<]*<\/title>/, `<title>${esc(title)}</title>`)
      .replace(/<meta property="og:title" content="[^"]*">/,
               `<meta property="og:title" content="${esc(title)}">`)
      .replace(/<meta property="og:url" content="[^"]*">/,
               `<meta property="og:url" content="${esc(url)}">`)
      .replace(/<meta property="og:description" content="[^"]*">/,
               `<meta property="og:description" content="${esc(desc)}">`)
      // the real content, so a crawler sees it without running any JavaScript
      .replace(/(<div class="pw-wrap" id="guideDetail">)[\s\S]*?(<\/div>\s*<footer)/,
               `$1\n${body(item, section)}\n$2`);

    if (!/<meta name="description"/.test(html)) {
      html = html.replace("</head>",
        `<meta name="description" content="${esc(desc)}">\n<link rel="canonical" href="${esc(url)}">\n</head>`);
    }

    mkdirSync(`${name}/${item.slug}`, { recursive: true });
    writeFileSync(`${name}/${item.slug}/index.html`, html);
    built++;
    console.log(`  ${name}/${item.slug}/index.html  —  ${esc(title)}`);
  }
}
console.log(`\n${built} guide pages prerendered`);
