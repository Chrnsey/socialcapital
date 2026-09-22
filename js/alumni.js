// ===========================================================================
// Sign-in for former students, 18 and over.
//
// Same passwordless approach as the school login. The gate is the same shape
// too: Supabase will email a link to anyone who asks, so the real check is
// in the database - the alumni table decides whether you see anything.
//
// Difference from schools: an alumnus is an adult, so where a mentor has
// agreed to it they get the mentor's own contact details and take it from
// there. Nobody supervises that, which is the point.
// ===========================================================================
(function () {
  function el(id) { return document.getElementById(id); }

  function setLoginStatus(msg, kind) {
    var n = el("loginStatus");
    if (!n) return;
    n.textContent = msg;
    n.className = "form-status" + (kind ? " " + kind : "");
  }

  function showScreen(name) {
    el("mainSite").classList.toggle("hidden", name !== "site");
    el("loginPage").classList.toggle("active", name === "login");
    el("directoryPage").classList.toggle("active", name === "directory");
  }

  var SCAlumni = {
    openLogin: function () { showScreen("login"); },
    goBack: function () { showScreen("site"); },

    signOut: function () {
      if (window.SC && window.SC.ready) window.SC.client.auth.signOut();
      window.SC.viewer = null;
      showScreen("site");
      history.replaceState(null, "", window.location.pathname);
    },

    sendLink: function (event) {
      if (event) event.preventDefault();
      var email = (el("loginEmail").value || "").trim().toLowerCase();
      if (!email) { setLoginStatus("Enter your email address.", "error"); return; }
      if (!window.SC || !window.SC.ready) {
        setLoginStatus("Sign-in isn't connected yet.", "error"); return;
      }

      var btn = el("loginForm").querySelector("[type=submit]");
      btn.disabled = true; btn.textContent = "Sending…";
      setLoginStatus("", "");

      window.SC.client.auth
        .signInWithOtp({
          email: email,
          options: { emailRedirectTo: window.location.origin + window.location.pathname }
        })
        .then(function (r) {
          if (r.error) throw r.error;
          setLoginStatus("Check your inbox. The link lasts an hour.", "ok");
        })
        .catch(function (e) {
          console.error("[Social Capital] alumni sign-in failed", e);
          setLoginStatus("That didn't send. Try again shortly.", "error");
        })
        .then(function () {
          btn.disabled = false; btn.textContent = "Email me a sign-in link";
        });
    },

    init: function () {
      if (!window.SC || !window.SC.ready) return;

      window.SC.client.auth.getSession().then(function (res) {
        var session = res.data && res.data.session;
        if (!session) return;

        window.SC.client.rpc("is_approved_alumnus").then(function (check) {
          if (check.error || check.data !== true) {
            window.SC.client.auth.signOut();
            showScreen("login");
            setLoginStatus(
              "That email isn't registered. Sign up with your school code first — " +
              "or if you already did, use the same address you used then.",
              "error"
            );
            return;
          }

          // Tells the directory to offer contact details.
          window.SC.viewer = "alumnus";

          window.SC.client
            .from("alumni")
            .select("email")
            .limit(1)
            .then(function (r) {
              var row = r.data && r.data[0];
              if (row && el("schoolName")) el("schoolName").textContent = row.email;
              showScreen("directory");
              if (window.SCDirectory) window.SCDirectory.start();
            });
        });
      });
    }
  };

  window.SCAlumni = SCAlumni;

  document.addEventListener("DOMContentLoaded", function () {
    var f = el("loginForm");
    if (f) f.addEventListener("submit", SCAlumni.sendLink);
    SCAlumni.init();
  });
})();
