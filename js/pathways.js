// ===========================================================================
// Renders the career pathway pages from content/pathways.json.
//
// This is public information — no login, no database, nothing gated. The
// content lives in the CMS so you can write and correct it yourself.
// ===========================================================================
(function () {
  function esc(v) {
    return String(v == null ? "" : v).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  // Works with clean URLs (/pathways/electrician) and with ?p=electrician,
  // so the pages still work when opened from a plain local server.
  function currentSlug() {
    var q = new URLSearchParams(window.location.search).get("p");
    if (q) return q;
    var parts = window.location.pathname.replace(/\/+$/, "").split("/");
    var last = parts[parts.length - 1];
    return last && last !== "pathway.html" ? last : null;
  }

  // Always absolute. A relative path would resolve to
  // /pathways/content/pathways.json on a detail page, which the Netlify
  // rewrite serves as HTML — a failed request and a visible delay.
  function load() {
    return fetch("/content/pathways.json", { cache: "no-cache" })
      .then(function (r) {
        if (!r.ok) throw new Error("pathways " + r.status);
        return r.json();
      });
  }

  // ---- index page ---------------------------------------------------------
  function renderIndex(data) {
    var el = document.getElementById("pathwayList");
    if (!el) return;

    var intro = data.intro || {};
    var setText = function (id, value) {
      var n = document.getElementById(id);
      if (n && value) n.textContent = value;
    };
    setText("pwTag", intro.tag);
    setText("pwTitle", intro.title);
    setText("pwBody", intro.body);

    var list = data.pathways || [];
    if (!list.length) {
      el.innerHTML = '<p class="dir-empty">Pathways are being written. Check back shortly.</p>';
      return;
    }

    el.innerHTML = list.map(function (p) {
      return (
        '<a class="pathway-card" href="pathways/' + esc(p.slug) + '">' +
          '<div class="pathway-card-top">' +
            '<span class="pathway-sector">' + esc(p.sector) + "</span>" +
            '<span class="pathway-arrow">›</span>' +
          "</div>" +
          "<h3>" + esc(p.title) + "</h3>" +
          "<p>" + esc(p.summary) + "</p>" +
        "</a>"
      );
    }).join("");
  }

  // ---- detail page -------------------------------------------------------
  function renderDetail(data) {
    var host = document.getElementById("pathwayDetail");
    if (!host) return;

    var slug = currentSlug();
    var p = (data.pathways || []).filter(function (x) { return x.slug === slug; })[0];

    if (!p) {
      host.innerHTML =
        "<h1>Pathway not found</h1>" +
        '<p>We couldn\'t find that one. <a href="/pathways.html">See all pathways</a>.</p>';
      return;
    }

    document.title = "Social Capital — " + p.title;

    var routes = (p.routes || []).map(function (r) {
      return (
        '<div class="route">' +
          '<div class="route-head">' +
            "<h3>" + esc(r.name) + "</h3>" +
            (r.tag ? '<span class="route-tag">' + esc(r.tag) + "</span>" : "") +
          "</div>" +
          "<p>" + esc(r.detail) + "</p>" +
          '<dl class="route-facts">' +
            (r.duration ? "<div><dt>How long</dt><dd>" + esc(r.duration) + "</dd></div>" : "") +
            (r.cost ? "<div><dt>What it costs</dt><dd>" + esc(r.cost) + "</dd></div>" : "") +
          "</dl>" +
        "</div>"
      );
    }).join("");

    var myths = (p.myths || []).map(function (m) {
      return (
        '<div class="myth">' +
          '<p class="myth-claim">“' + esc(m.myth) + '”</p>' +
          '<p class="myth-reality">' + esc(m.reality) + "</p>" +
        "</div>"
      );
    }).join("");

    var links = (p.apply || []).map(function (l) {
      return '<li><a href="' + esc(l.url) + '" rel="noopener">' + esc(l.label) + "</a></li>";
    }).join("");

    host.innerHTML =
      '<p class="pw-kicker">' + esc(p.sector) + " · route into work</p>" +
      "<h1>" + esc(p.title) + "</h1>" +
      '<p class="pw-summary">' + esc(p.summary) + "</p>" +

      "<h2>What the job actually is</h2>" +
      "<p>" + esc(p.what_it_is) + "</p>" +

      "<h2>Ways in</h2>" +
      '<p class="pw-note">There is more than one. None of these is the "proper" one.</p>' +
      routes +

      "<h2>What you need</h2>" +
      "<p>" + esc(p.what_you_need) + "</p>" +

      (p.earning ? "<h2>What you earn while training</h2><p>" + esc(p.earning) + "</p>" : "") +

      (myths ? "<h2>What people get wrong</h2>" + myths : "") +

      (links ? "<h2>Where to go next</h2><ul class=\"pw-links\">" + links + "</ul>" : "") +

      '<div class="pw-cta">' +
        "<h2>Talk to someone who did it</h2>" +
        "<p>These pages tell you the route. A person can tell you what it was actually like — " +
        "and answer the thing you specifically want to know. Mentor profiles are open to " +
        "registered schools.</p>" +
        '<a class="btn" href="/schools.html">How schools register</a>' +
      "</div>" +

      (p.checked ? '<p class="pw-checked">Information checked ' + esc(p.checked) +
        '. Course requirements, fees and rates change — always confirm with the official ' +
        'sources linked above.</p>' : "");
  }

  document.addEventListener("DOMContentLoaded", function () {
    load().then(function (data) {
      renderIndex(data);
      renderDetail(data);
    }).catch(function (e) {
      console.error("[Social Capital] pathways failed to load", e);
      var host = document.getElementById("pathwayDetail") || document.getElementById("pathwayList");
      if (host) host.innerHTML = '<p class="dir-empty">Couldn\'t load this just now. Please refresh.</p>';
    });
  });
})();
