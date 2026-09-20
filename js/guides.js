// ===========================================================================
// Renders the three guide sections: Ways in, Paying for it, and Careers.
//
// All public - no login, no database. Content lives in content/<section>.json
// and is edited through the CMS.
//
// URLs: /routes/apprenticeships, /funding/hear, /careers/electrician
// A Netlify rewrite serves guide.html for all of them; this reads the path
// to work out which section and which page.
// ===========================================================================
(function () {
  var SECTIONS = ["routes", "funding", "careers"];

  function esc(v) {
    return String(v == null ? "" : v).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  // Turns blank lines into paragraphs so CMS text can have more than one.
  function paras(text) {
    return String(text || "").split(/\n\s*\n/).filter(Boolean)
      .map(function (p) { return "<p>" + esc(p).replace(/\n/g, "<br>") + "</p>"; })
      .join("");
  }

  function load(section) {
    return fetch("/content/" + section + ".json", { cache: "no-cache" })
      .then(function (r) {
        if (!r.ok) throw new Error(section + " " + r.status);
        return r.json();
      });
  }

  // ---- which page are we on? ---------------------------------------------
  function target() {
    var q = new URLSearchParams(window.location.search);
    if (q.get("s")) return { section: q.get("s"), slug: q.get("p") };
    var parts = window.location.pathname.replace(/^\/+|\/+$/g, "").split("/");
    if (SECTIONS.indexOf(parts[0]) !== -1) {
      return { section: parts[0], slug: parts[1] || null };
    }
    return { section: null, slug: null };
  }

  // ---- hub page ----------------------------------------------------------
  function renderHub() {
    var host = document.getElementById("guideHub");
    if (!host) return;

    Promise.all(SECTIONS.map(function (s) {
      return load(s).catch(function () { return null; });
    })).then(function (all) {
      host.innerHTML = all.filter(Boolean).map(function (data) {
        var sec = data.section || {};
        var cards = (data.items || []).map(function (it) {
          return (
            '<a class="guide-card" href="/' + esc(sec.slug) + "/" + esc(it.slug) + '">' +
              '<div class="guide-card-top">' +
                '<span class="guide-sub">' + esc(it.subtitle || "") + "</span>" +
                '<span class="guide-arrow">›</span>' +
              "</div>" +
              "<h3>" + esc(it.title) + "</h3>" +
              "<p>" + esc(it.summary) + "</p>" +
            "</a>"
          );
        }).join("");

        return (
          '<section class="guide-group">' +
            '<p class="pw-kicker">' + esc(sec.tag || "") + "</p>" +
            "<h2>" + esc(sec.title) + "</h2>" +
            '<p class="guide-intro">' + esc(sec.intro || "") + "</p>" +
            '<div class="guide-grid">' + cards + "</div>" +
          "</section>"
        );
      }).join("");
    });
  }

  // ---- detail page -------------------------------------------------------
  function renderDetail() {
    var host = document.getElementById("guideDetail");
    if (!host) return;

    var t = target();
    if (!t.section || !t.slug) {
      host.innerHTML = "<h1>Not found</h1><p><a href=\"/guides.html\">See all guides</a>.</p>";
      return;
    }

    load(t.section).then(function (data) {
      var it = (data.items || []).filter(function (x) { return x.slug === t.slug; })[0];
      if (!it) {
        host.innerHTML =
          "<h1>Not found</h1><p>We couldn't find that page. " +
          '<a href="/guides.html">See all guides</a>.</p>';
        return;
      }

      document.title = "Social Capital — " + it.title;
      var sec = data.section || {};

      var facts = (it.facts || []).length
        ? '<dl class="fact-grid">' + it.facts.map(function (f) {
            return "<div><dt>" + esc(f.label) + "</dt><dd>" + esc(f.value) + "</dd></div>";
          }).join("") + "</dl>"
        : "";

      var routes = (it.routes || []).length
        ? "<h2>Ways in</h2><p class=\"pw-note\">There is more than one. None of these is the \"proper\" one.</p>" +
          it.routes.map(function (r) {
            return (
              '<div class="route">' +
                '<div class="route-head"><h3>' + esc(r.name) + "</h3>" +
                  (r.tag ? '<span class="route-tag">' + esc(r.tag) + "</span>" : "") +
                "</div>" + paras(r.detail) +
                '<dl class="route-facts">' +
                  (r.duration ? "<div><dt>How long</dt><dd>" + esc(r.duration) + "</dd></div>" : "") +
                  (r.cost ? "<div><dt>What it costs</dt><dd>" + esc(r.cost) + "</dd></div>" : "") +
                "</dl></div>"
            );
          }).join("")
        : "";

      var blocks = (it.blocks || []).map(function (b) {
        return "<h2>" + esc(b.heading) + "</h2>" + paras(b.text);
      }).join("");

      var myths = (it.myths || []).length
        ? "<h2>What people get wrong</h2>" + it.myths.map(function (m) {
            return '<div class="myth"><p class="myth-claim">“' + esc(m.myth) +
                   '”</p><p class="myth-reality">' + esc(m.reality) + "</p></div>";
          }).join("")
        : "";

      var links = (it.apply || []).length
        ? '<h2>Where to go next</h2><ul class="pw-links">' + it.apply.map(function (l) {
            return '<li><a href="' + esc(l.url) + '" rel="noopener">' + esc(l.label) + "</a></li>";
          }).join("") + "</ul>"
        : "";

      var related = (it.related || []).length
        ? '<div class="related"><p class="pw-kicker">Read next</p><ul>' +
          it.related.map(function (r) {
            return '<li><a href="' + esc(r.href) + '">' + esc(r.label) + "</a></li>";
          }).join("") + "</ul></div>"
        : "";

      host.innerHTML =
        '<p class="pw-kicker">' + esc(sec.title || "") +
          (it.subtitle ? " · " + esc(it.subtitle) : "") + "</p>" +
        "<h1>" + esc(it.title) + "</h1>" +
        '<p class="pw-summary">' + esc(it.summary) + "</p>" +
        facts + paras(it.body) + routes + blocks + myths + links + related +
        '<div class="pw-cta"><h2>Talk to someone who did it</h2>' +
          "<p>These pages tell you how it works. A person can tell you what it was " +
          "actually like. Mentor profiles are open to registered schools.</p>" +
          '<a class="btn" href="/schools.html">How schools register</a></div>' +
        (it.checked ? '<p class="pw-checked">Information checked ' + esc(it.checked) +
          ". Requirements, fees and deadlines change — always confirm with the " +
          "official sources linked above before making a decision.</p>" : "");
    }).catch(function (e) {
      console.error("[Social Capital] guide failed to load", e);
      host.innerHTML = '<p class="dir-empty">Couldn\'t load this just now. Please refresh.</p>';
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    renderHub();
    renderDetail();
  });
})();
