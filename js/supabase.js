// Creates the one shared Supabase connection used by the rest of the site.
// If the keys in config.js haven't been filled in yet, the site still works
// as a demo — forms just say so instead of throwing errors at visitors.
(function () {
  var cfg = window.SC_CONFIG || {};
  var ready =
    typeof cfg.SUPABASE_URL === "string" &&
    cfg.SUPABASE_URL.indexOf("PASTE_") !== 0 &&
    typeof cfg.SUPABASE_ANON_KEY === "string" &&
    cfg.SUPABASE_ANON_KEY.indexOf("PASTE_") !== 0 &&
    window.supabase;

  window.SC = {
    ready: !!ready,
    client: ready
      ? window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY)
      : null
  };

  if (!ready) {
    console.warn(
      "[Social Capital] Supabase keys not set yet — see js/config.js. " +
      "Forms and login are disabled until they are."
    );
  }
})();
