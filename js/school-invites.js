// ===========================================================================
// A school giving its own students access.
//
// The counsellor creates an invitation for one named address and gets back a
// link to send themselves, from their own school address. We never hold a
// list of student addresses: only the invitations the school chose to create.
//
// As everywhere else on this site, none of the checking here is the security.
// school_issue_invite, school_list_invites and school_revoke_invite each work
// out which school is asking from the signed-in email and refuse anybody who
// is not a registered school. This file only decides what the page says.
// ===========================================================================
(function () {
  function el(id) { return document.getElementById(id); }

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function status(message, kind) {
    var n = el("inviteStatus");
    if (!n) return;
    n.textContent = message;
    n.className = "form-status" + (kind ? " " + kind : "");
  }

  var WORDS = {
    waiting: "Waiting for them",
    joined:  "Joined",
    expired: "Expired",
    revoked: "Removed"
  };

  function when(value) {
    var d = new Date(value);
    return isNaN(d) ? "" : d.toLocaleDateString("en-IE",
      { day: "numeric", month: "short", year: "numeric" });
  }

  function render(rows) {
    var box = el("inviteList");
    if (!rows.length) {
      box.innerHTML = '<p class="dir-empty">Nobody invited yet.</p>';
      return;
    }

    box.innerHTML =
      '<p class="dir-section-title">Invitations</p>' +
      rows.map(function (r) {
        // Only a live invitation can usefully be taken back, and only a
        // joined one can have its access removed. Expired and revoked rows
        // are history and get no button.
        var canRevoke = r.state === "waiting" || r.state === "joined";
        return '' +
          '<div class="invite-item is-' + esc(r.state) + '" data-token="' + esc(r.token) + '">' +
            '<div>' +
              '<strong>' + esc(r.email) + '</strong>' +
              '<span class="invite-meta">' +
                esc(WORDS[r.state] || r.state) +
                " · sent " + esc(when(r.issued_at)) +
                (r.state === "waiting" ? " · expires " + esc(when(r.expires_at)) : "") +
              '</span>' +
            '</div>' +
            (canRevoke
              ? '<button type="button" class="btn-outline admin-small" data-revoke>' +
                (r.state === "joined" ? "Remove access" : "Cancel") + '</button>'
              : '') +
          '</div>';
      }).join("");
  }

  function load() {
    return window.SC.client.rpc("school_list_invites").then(function (r) {
      if (r.error) throw r.error;
      render(r.data || []);
    });
  }

  function create(event) {
    event.preventDefault();

    var email = (el("inviteEmail").value || "").trim().toLowerCase();
    if (!email) { status("Enter their email address.", "error"); return; }
    if (!el("inviteAttest").checked) {
      status("Tick the box to confirm they are 18 or over.", "error");
      return;
    }

    var button = el("inviteSubmit");
    button.disabled = true;
    button.textContent = "Creating…";
    status("", "");
    el("inviteLink").hidden = true;

    window.SC.client
      .rpc("school_issue_invite", { p_email: email, p_age_attested: true })
      .then(function (r) {
        if (r.error) throw r.error;

        var link = window.location.origin + "/alumni?invite=" + encodeURIComponent(r.data);
        el("inviteLinkValue").value = link;
        el("inviteLink").hidden = false;

        el("inviteForm").reset();
        status("Invitation created for " + email + ".", "ok");
        return load();
      })
      .catch(function (e) {
        console.error("[Social Capital] invite failed", e);
        status(e && e.message ? e.message : "That didn't work. Try again.", "error");
      })
      .then(function () {
        button.disabled = false;
        button.textContent = "Create invitation";
      });
  }

  function onListClick(event) {
    var button = event.target.closest("[data-revoke]");
    if (!button) return;

    var item = button.closest(".invite-item");
    var token = item.getAttribute("data-token");
    var who = item.querySelector("strong").textContent;
    var joined = item.classList.contains("is-joined");

    if (!window.confirm(
      joined ? "Remove " + who + "'s access to the directory?"
             : "Cancel the invitation for " + who + "?")) return;

    button.disabled = true;
    window.SC.client.rpc("school_revoke_invite", { p_token: token })
      .then(function (r) { if (r.error) throw r.error; return load(); })
      .catch(function (e) {
        console.error("[Social Capital] revoke failed", e);
        alert("That didn't work: " + (e && e.message ? e.message : "unknown error"));
        button.disabled = false;
      });
  }

  function copyLink() {
    var box = el("inviteLinkValue");
    box.select();
    var done = function () {
      var b = el("inviteCopy");
      b.textContent = "Copied";
      setTimeout(function () { b.textContent = "Copy"; }, 1800);
    };
    // Clipboard API needs a secure context and permission; select-and-copy is
    // the fallback that works everywhere, including an older school laptop.
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(box.value).then(done, function () {
        try { document.execCommand("copy"); done(); } catch (e) {}
      });
    } else {
      try { document.execCommand("copy"); done(); } catch (e) {}
    }
  }

  window.SCInvites = {
    // Called by auth.js once a school is confirmed, same as the directory.
    start: function () {
      if (!el("invitePanel") || !window.SC || !window.SC.ready) return;
      load().catch(function (e) {
        console.error("[Social Capital] invite list failed", e);
        el("inviteList").innerHTML =
          '<p class="dir-empty">Couldn\'t load your invitations. Refresh to try again.</p>';
      });
    }
  };

  document.addEventListener("DOMContentLoaded", function () {
    var f = el("inviteForm");
    if (!f) return;
    f.addEventListener("submit", create);
    el("inviteList").addEventListener("click", onListClick);
    el("inviteCopy").addEventListener("click", copyLink);
  });
})();
