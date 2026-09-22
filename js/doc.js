// ===========================================================================
// Renders a long-form page (About, Terms, Privacy) from a markdown file in
// content/pages/, which Jack edits in the CMS like a normal document.
//
// The current wording is also written into the HTML, so if this file can't
// load - an old browser, a blocked script, a network blip - the page still
// shows the last published version rather than going blank.
//
// The markdown comes from our own repository via the CMS, so it is trusted
// in the way the rest of the site's content is.
// ===========================================================================
(function () {
  function render(el, md) {
    if (!window.marked) return;
    el.innerHTML = window.marked.parse(md, { gfm: true, breaks: false });

    // Links to other pages on this site stay in the tab; outside links don't.
    el.querySelectorAll("a[href]").forEach(function (a) {
      if (/^https?:\/\//i.test(a.getAttribute("href"))) {
        a.setAttribute("rel", "noopener");
      }
    });

    var h1 = el.querySelector("h1");
    if (h1) document.title = "Social Capital — " + h1.textContent;
  }

  document.addEventListener("DOMContentLoaded", function () {
    var el = document.querySelector("[data-doc]");
    if (!el) return;
    var name = el.getAttribute("data-doc");

    fetch("/content/pages/" + name + ".md", { cache: "no-cache" })
      .then(function (r) {
        if (!r.ok) throw new Error(name + " " + r.status);
        return r.text();
      })
      .then(function (md) {
        // The CMS may save a small "front matter" header at the top of the
        // file (between --- lines). It isn't page text, so strip it rather
        // than letting it render as a stray line.
        md = md.replace(/^\uFEFF?---\s*\n[\s\S]*?\n---\s*\n/, "");
        render(el, md);
      })
      .catch(function (e) {
        // Silent on purpose - the HTML fallback is already on screen.
        console.info("[Social Capital] showing built-in text for", name, "-", e.message);
      });
  });
})();
