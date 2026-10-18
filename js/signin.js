// ===========================================================================
// One sign-in for everybody.
//
// Until now there were two separate logins: one inside schools.html for
// staff, one inside alumni.html for former students. Same code in both,
// which meant visitors had to work out which one they were before they
// could type their email.
//
// This page asks nobody anything. You type your email, you get a link, and
// when you come back the DATABASE decides where you belong:
//
//   is_approved_school()   true -> the school directory
//   is_approved_member()  true -> the former-students directory
//   neither                     -> told so, and shown how to get access
//
// A side effect worth knowing: somebody who is both - a teacher who went to
// the school themselves - lands in the school directory, because that check
// runs first. That is the richer of the two views, so it is the right way
// round.
//
// SECURITY NOTE
// -------------
// Supabase will email a sign-in link to ANY address that asks for one. That
// is not the gate and cannot be switched off. The gate is the database: an
// unapproved email gets a perfectly valid session and can read nothing.
// The message below is a courtesy so that person sees an explanation rather
// than an empty page.
//
// The "we don't recognise that address" wording is deliberately vague. It
// does not say whether a given school is registered, because that would let
// anyone check which schools use the platform by guessing addresses.
// ===========================================================================
(function () {
  function el(id) { return document.getElementById(id); }

  function show(which) {
    ["signinForm", "signinChecking", "signinUnknown"].forEach(function (id) {
      var node = el(id);
      if (node) node.hidden = id !== which;
    });
  }

  function setStatus(message, kind) {
    var node = el("loginStatus");
    if (!node) return;
    node.textContent = message;
    node.className = "form-status" + (kind ? " " + kind : "");
  }

  var SCSignIn = {
    sendLink: function (event) {
      if (event) event.preventDefault();

      var email = (el("loginEmail").value || "").trim().toLowerCase();
      if (!email) { setStatus("Enter your email address.", "error"); return; }

      if (!window.SC || !window.SC.ready) {
        setStatus("Sign-in isn't connected yet.", "error");
        return;
      }

      var button = el("signinSubmit");
      button.disabled = true;
      button.textContent = "Sending…";
      setStatus("", "");

      window.SC.client.auth
        .signInWithOtp({
          email: email,
          options: { emailRedirectTo: window.location.origin + window.location.pathname }
        })
        .then(function (result) {
          if (result.error) throw result.error;
          setStatus(
            "Check your inbox — we've sent a sign-in link to " + email +
            ". It lasts an hour.",
            "ok"
          );
        })
        .catch(function (error) {
          console.error("[Social Capital] sign-in failed", error);
          var why = (error && error.message) || "";
          setStatus(
            /rate|limit|seconds|security purposes/i.test(why)
              ? "We can't send another link just yet: " + why
              : "Sorry — that didn't send" + (why ? ": " + why : "") + ".",
            "error"
          );
        })
        .then(function () {
          button.disabled = false;
          button.textContent = "Email me a sign-in link";
        });
    },

    // Runs on load. Only does anything if we came back from a link.
    init: function () {
      if (!window.SC || !window.SC.ready) return;

      window.SC.client.auth.getSession().then(function (result) {
        var session = result.data && result.data.session;
        if (!session) return;

        show("signinChecking");

        window.SC.client.rpc("is_approved_school").then(function (school) {
          if (!school.error && school.data === true) {
            window.location.replace("schools.html");
            return;
          }

          window.SC.client.rpc("is_approved_member").then(function (alumnus) {
            if (!alumnus.error && alumnus.data === true) {
              window.location.replace("alumni.html");
              return;
            }

            // Signed in, but on neither list. Drop the session so a stale
            // one cannot sit around, and explain.
            window.SC.client.auth.signOut();
            show("signinUnknown");
            history.replaceState(null, "", window.location.pathname);
          });
        });
      });
    }
  };

  window.SCSignIn = SCSignIn;

  document.addEventListener("DOMContentLoaded", function () {
    var form = el("loginForm");
    if (form) form.addEventListener("submit", SCSignIn.sendLink);
    SCSignIn.init();
  });
})();
