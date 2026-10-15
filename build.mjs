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
import { marked } from "marked";

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

// A marker written into every page the build touches, so anyone can check
// whether the build actually ran - and how recently - with a single request:
//   curl -s https://socialcapital.ie/ | grep "built-by-build.mjs"
// If it is missing, the Cloudflare build command is not set and the HTML a
// crawler reads is whatever was last committed by hand.
const STAMP = `<!-- built-by-build.mjs ${new Date().toISOString()} -->`;
function stamp(html) {
  return html.replace(/<!-- built-by-build\.mjs [^>]*-->\n?/g, "")
             .replace("</head>", STAMP + "\n</head>");
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

    // Written as routes/plc.html, not routes/plc/index.html: Cloudflare
    // Pages serves the former at /routes/plc exactly, while the latter is
    // 308-redirected to /routes/plc/ - a wasted hop that also would not match
    // our canonical URLs, sitemap or internal links.
    mkdirSync(name, { recursive: true });
    writeFileSync(`${name}/${item.slug}.html`, stamp(html));
    built++;
    console.log(`  ${name}/${item.slug}.html  —  ${esc(title)}`);
  }
}
console.log(`\n${built} guide pages prerendered`);

// ===========================================================================
// Second job: refresh the fallback text baked into each page's HTML.
//
// Each page carries a copy of its wording in the HTML so it never renders
// blank, then JavaScript swaps in the current version from the CMS. Visitors
// always see the current wording. Crawlers, which do not reliably run
// JavaScript, were reading whatever was baked in - which went stale the
// moment anything was edited in the CMS. Google was quoting copy nobody had
// used for weeks, including a claim that the service was free.
//
// This rewrites those fallbacks from the same JSON, on every deploy.
// ===========================================================================
const CONTENT_PAGES = {
  "index.html": "index",
  "schools.html": "schools",
  "mentors.html": "mentors",
  "businesses.html": "businesses",
  "alumni.html": "alumni",
};

const dig = (obj, path) =>
  path.split(".").reduce((a, k) => (a == null ? undefined : a[k]), obj);

let refreshed = 0;
for (const [page, key] of Object.entries(CONTENT_PAGES)) {
  let html;
  try { html = readFileSync(page, "utf8"); } catch { continue; }
  const data = JSON.parse(readFileSync(`content/${key}.json`, "utf8"));
  let changes = 0;

  // data-sc-text / data-sc-html: replace the element's contents
  html = html.replace(
    /(<(\w+)([^>]*?)data-sc-(text|html)="([^"]+)"([^>]*)>)([\s\S]*?)(<\/\2>)/g,
    (whole, open, tag, pre, kind, path, post, inner, close) => {
      const value = dig(data, path);
      if (typeof value !== "string") return whole;
      const next = kind === "html" ? value : esc(value);
      if (next !== inner) changes++;
      return open + next + close;
    }
  );

  // data-sc-list: rebuild the fallback items from the <template>
  html = html.replace(
    /(<(\w+)([^>]*?)data-sc-list="([^"]+)"([^>]*)>)([\s\S]*?)(<\/\2>)/g,
    (whole, open, tag, pre, path, post, inner, close) => {
      const items = dig(data, path);
      const tpl = inner.match(/<template[^>]*data-sc-item[^>]*>([\s\S]*?)<\/template>/);
      if (!Array.isArray(items) || !tpl) return whole;
      const shape = tpl[1];
      const built = items
        .map((it) => shape.replace(/\{\{(\w+)\}\}/g, (_, k) => esc(it[k])))
        .join("");
      changes++;
      return open + tpl[0] + built + close;
    }
  );

  // Always written, even when nothing changed, so every page carries the
  // build stamp. That is what makes "did the build actually run?" answerable.
  writeFileSync(page, stamp(html));
  refreshed++;
  console.log(`  ${page} — ${changes} fallback block${changes === 1 ? "" : "s"} refreshed from the CMS`);
}
console.log(`${refreshed} pages refreshed`);

// ===========================================================================
// Third job: the long-form documents (About, Terms, Privacy).
//
// These are written as markdown in the CMS and rendered in the browser. The
// HTML carried a copy so the page never renders blank - and that copy went
// stale as soon as the markdown was edited, leaving crawlers reading an old
// version of the About page.
//
// Rendering the markdown here, with the same library the browser uses, ties
// the two together: edit in the CMS, push, and the HTML a crawler reads is
// rebuilt from the same source.
// ===========================================================================
const DOCS = ["about", "terms", "privacy"];

function innerRange(html, openTagStart) {
  // Walk forward from an opening <div ...> to its matching </div>.
  const from = html.indexOf(">", openTagStart) + 1;
  let depth = 1, i = from;
  const re = /<div\b|<\/div>/g;
  re.lastIndex = from;
  let m;
  while ((m = re.exec(html))) {
    depth += m[0] === "</div>" ? -1 : 1;
    if (depth === 0) return [from, m.index];
  }
  return null;
}

let docsBuilt = 0;
for (const name of DOCS) {
  let html;
  try { html = readFileSync(`${name}.html`, "utf8"); } catch { continue; }
  let md = readFileSync(`content/pages/${name}.md`, "utf8");
  md = md.replace(/^\uFEFF?---\s*\n[\s\S]*?\n---\s*\n/, "");   // strip front matter

  const open = html.indexOf(`<div class="doc" data-doc="${name}"`);
  if (open === -1) continue;
  const range = innerRange(html, open);
  if (!range) continue;

  const rendered = marked.parse(md, { gfm: true });
  html = html.slice(0, range[0]) + "\n" + rendered + html.slice(range[1]);

  // Title and description from the document itself, so they track edits too.
  const h1 = md.match(/^#\s+(.+)$/m);
  if (h1) {
    html = html.replace(/<title>[^<]*<\/title>/, `<title>Social Capital \u2014 ${esc(h1[1].trim())}</title>`);
  }
  const firstPara = md.split(/\n\s*\n/).find(
    (b) => b.trim() && !b.startsWith("#") && !b.startsWith(">") && !b.startsWith("*") && !b.startsWith("-")
  );
  if (firstPara) {
    const desc = esc(firstPara.replace(/[*_`\[\]]/g, "").replace(/\s+/g, " ").trim().slice(0, 300));
    html = /<meta name="description"/.test(html)
      ? html.replace(/<meta name="description" content="[^"]*">/, `<meta name="description" content="${desc}">`)
      : html.replace("</head>", `<meta name="description" content="${desc}">\n</head>`);
  }

  writeFileSync(`${name}.html`, stamp(html));
  docsBuilt++;
  console.log(`  ${name}.html — rebuilt from content/pages/${name}.md`);
}
console.log(`${docsBuilt} documents rebuilt`);
