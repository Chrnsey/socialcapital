// ===========================================================================
// School sign-in, using Supabase "magic links" — no passwords anywhere.
//
// The visitor types their email, gets a link, clicks it, and lands back here
// signed in.
//
// IMPORTANT — how the gate really works:
//   Supabase will send a login link to ANY email address that asks for one.
//   That is not the security boundary and cannot be turned off.
//
//   The real boundary is in the database: the rule on the `mentors` table
//   only returns rows if the signed-in email appears in the approved
//   `schools` table. Someone who signs in without being approved gets a
//   valid session and sees nothing at all.
//
//   The check below is a COURTESY, so that person sees a clear explanation
//   rather than a mysteriously empty page. Removing it would not expose
//   any data.
// ===========================================================================
(function () {
  function el(id) { return document.getElementById(id); }

  function setLoginStatus(message, kind) {
    var node = el("loginStatus");
    if (!node) return;
    node.textContent = message;
    node.className = "form-status" + (kind ? " " + kind : "");
  }

  function showScreen(name) {
    el("mainSite").classList.toggle("hidden", name !== "site");
    el("loginPage").classList.toggle("active", name === "login");
    el("directoryPage").classList.toggle("active", name === "directory");
  }

  var SCAuth = {
    // Called when the sign-in form is submitted.
    sendLink: function (event) {
      if (event) event.preventDefault();

      var form = el("loginForm");
      var email = (el("loginEmail").value || "").trim().toLowerCase();
      if (!email) { setLoginStatus("Please enter your school email.", "error"); return; }

      if (!window.SC || !window.SC.ready) {
        setLoginStatus("Sign-in isn't connected yet.", "error");
        return;
      }

      var button = form.querySelector("[type=submit]");
      button.disabled = true;
      button.textContent = "Sending…";
      setLoginStatus("", "");

      window.SC.client.auth
        .signInWithOtp({
          email: email,
          options: { emailRedirectTo: window.location.origin + window.location.pathname }
        })
        .then(function (result) {
          if (result.error) throw result.error;
          setLoginStatus(
            "Check your inbox — we've sent a sign-in link to " + email +
            ". It expires in an hour.",
            "ok"
          );
        })
        .catch(function (error) {
          console.error("[Social Capital] sign-in failed", error);
          setLoginStatus("Sorry — that didn't send. Please try again shortly.", "error");
        })
        .then(function () {
          button.disabled = false;
          button.textContent = "Email me a sign-in link";
        });
    },

    signOut: function () {
      if (window.SC && window.SC.ready) window.SC.client.auth.signOut();
      showScreen("site");
      history.replaceState(null, "", window.location.pathname);
    },

    // Runs on every page load: if we already have a session, decide whether
    // this person is allowed into the directory.
    init: function () {
      if (!window.SC || !window.SC.ready) return;

      window.SC.client.auth.getSession().then(function (result) {
        var session = result.data && result.data.session;
        if (!session) return;

        window.SC.client.rpc("is_approved_school").then(function (check) {
          if (check.error || check.data !== true) {
            // Signed in, but this email is not on the approved list.
            window.SC.client.auth.signOut();
            showScreen("login");
            setLoginStatus(
              "That email isn't registered yet. If your school has applied, " +
              "we may still be reviewing it — or register below.",
              "error"
            );
            return;
          }

          // Approved. Fetch this school's own row for the name in the header.
          window.SC.client
            .from("schools")
            .select("school_name")
            .limit(1)
            .then(function (res) {
              var row = res.data && res.data[0];
              if (row && el("schoolName")) el("schoolName").textContent = row.school_name;
              showScreen("directory");
              if (window.SCDirectory) window.SCDirectory.start();
            });
        });
      });
    }
  };

  window.SCAuth = SCAuth;
  document.addEventListener("DOMContentLoaded", SCAuth.init);
})();
