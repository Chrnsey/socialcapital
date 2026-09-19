// ===========================================================================
// Loads editable text from content/*.json and drops it into the page.
//
// How it works, and why it works this way:
//   Every editable bit of text stays written in the HTML as normal. This
//   script then looks for elements tagged data-sc-text="some.key" and
//   replaces their text with the matching value from the JSON file.
//
//   That means if the JSON can't be loaded — for example if you open the
//   file by double-clicking it rather than through a web server — the page
//   still shows the last published wording instead of going blank.
// ===========================================================================
(function () {
  function escapeHtml(value) {
    return String(value == null ? "" : value).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function lookup(obj, path) {
    return path.split(".").reduce(function (acc, key) {
      return acc == null ? undefined : acc[key];
    }, obj);
  }

  function apply(data) {
    document.querySelectorAll("[data-sc-text]").forEach(function (el) {
      var value = lookup(data, el.getAttribute("data-sc-text"));
      if (typeof value === "string") el.textContent = value;
    });

    // Used only for the handful of sentences containing <strong> tags.
    // The content comes from your own CMS/repo, so it is trusted.
    document.querySelectorAll("[data-sc-html]").forEach(function (el) {
      var value = lookup(data, el.getAttribute("data-sc-html"));
      if (typeof value === "string") el.innerHTML = value;
    });

    // Repeating blocks, e.g. the three cards on the homepage. The shape of
    // one card lives in a <template>, which browsers do not display, so the
    // plain fallback cards in the HTML stay visible if the JSON never loads.
    document.querySelectorAll("[data-sc-list]").forEach(function (container) {
      var items = lookup(data, container.getAttribute("data-sc-list"));
      if (!Array.isArray(items)) return;
      var template = container.querySelector("template[data-sc-item]");
      if (!template) return;
      var shape = template.innerHTML;
      container.innerHTML = items
        .map(function (item) {
          return shape.replace(/\{\{(\w+)\}\}/g, function (_, key) {
            return escapeHtml(item[key]);
          });
        })
        .join("");
    });
  }

  window.SCContent = {
    load: function (name) {
      return fetch("content/" + name + ".json", { cache: "no-cache" })
        .then(function (r) {
          if (!r.ok) throw new Error("content " + r.status);
          return r.json();
        })
        .then(apply)
        .catch(function (err) {
          // Silent by design: the HTML fallback text is already on screen.
          console.info("[Social Capital] using built-in text —", err.message);
        });
    }
  };
})();
