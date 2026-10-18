// ===========================================================================
// The mentor admin page.
//
// This is the first page on the site that WRITES to the database while
// somebody is signed in, so a word about where the safety actually is.
//
// It is NOT in this file. Everything here is a convenience. The real checks
// live in the database: admin_add_mentor, admin_list_mentors,
// admin_set_published and admin_update_mentor each call is_admin() as their
// first statement and raise "Not permitted" otherwise. Deleting the whole of
// this file would not let anybody change a single row.
//
// In particular, a signed-in SCHOOL gets a perfectly valid session and is
// refused by every one of those functions. Being allowed to read the
// directory is not permission to change it.
//
// So: no check in here is load-bearing, and none of them should be trusted
// to be. They exist so that the page says something useful instead of
// throwing errors at you.
// ===========================================================================
(function () {
  function el(id) { return document.getElementById(id); }
  function val(id) { return (el(id).value || "").trim(); }
  function checked(id) { return !!el(id).checked; }

  var SECTORS = {
    technology: "Technology", healthcare: "Healthcare", law: "Law",
    finance: "Finance", trades: "Trades", media: "Media",
    education: "Education", engineering: "Engineering",
    public_sector: "Public sector", other: "Other"
  };

  // These must match the check constraints in study-and-route.sql. If they
  // drift, saving fails with a constraint violation.
  var ROUTES = {
    college: "school to college", plc_then_college: "PLC then college",
    apprenticeship: "apprenticeship", traineeship: "traineeship",
    work_from_school: "work from school", mature_student: "mature student",
    abroad: "studied abroad", other: "other route"
  };
  var FIELDS = {
    business: "Business", law: "Law", engineering: "Engineering",
    computing: "Computing", science: "Science", health_care: "Health and care",
    education: "Education", arts_humanities: "Arts and humanities",
    social_science: "Social science",
    construction_property: "Construction and property",
    trades_craft: "Trades and craft", media_design: "Media and design",
    agriculture_environment: "Agriculture and environment",
    hospitality_tourism: "Hospitality and tourism",
    sport_fitness: "Sport and fitness", other: "Other"
  };

  // A bio must not carry a way to reach somebody directly. Students have no
  // login, but a counsellor shows them the screen, and a handle copied off it
  // routes a student around the school entirely - which is the one control
  // the safeguarding statement actually rests on.
  //
  // This WARNS, it does not block. Jack is the check; the warning only makes
  // sure he looks. "@" appears in legitimate sentences and a false positive
  // that refused to save would be worse than a sentence he reads twice.
  function contactish(text) {
    var found = [];
    if (/\bhttps?:\/\/|\bwww\.|\.(com|ie|org|net|co\.uk)\b/i.test(text)) found.push("a web address");
    if (/(^|\s)@[A-Za-z0-9._]{2,}/.test(text)) found.push("an @ handle");
    if (/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/.test(text)) found.push("an email address");
    if (/(\+?\d[\d\s-]{7,}\d)/.test(text)) found.push("something phone-shaped");
    if (/\b(instagram|snapchat|tiktok|whatsapp|twitter|facebook|discord|telegram)\b/i.test(text))
      found.push("a social network");
    return found;
  }

  function checkBio() {
    var box = el("m_bio");
    var text = box.value || "";
    var count = el("bioCount");
    count.textContent = text.length + " / 500";
    count.className = "bio-count" + (text.length > 500 ? " over" : "");

    var found = contactish(text);
    var warn = el("bioWarn");
    if (found.length) {
      warn.hidden = false;
      warn.innerHTML = "This looks like it contains " + found.join(", ") +
        ". Contact goes through the school \u2014 a student copying this off " +
        "a counsellor's screen gets round that. Take it out unless you are sure.";
    } else {
      warn.hidden = true;
    }
  }

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function screen(name) {
    ["adminLogin", "adminChecking", "adminApp"].forEach(function (id) {
      el(id).hidden = id !== name;
    });
  }

  function status(node, message, kind) {
    var n = el(node);
    n.textContent = message;
    n.className = "form-status" + (kind ? " " + kind : "");
  }

  // -------------------------------------------------------------------------
  // Sign in
  // -------------------------------------------------------------------------
  function sendLink(event) {
    event.preventDefault();
    var email = val("adminEmail").toLowerCase();
    if (!email) { status("adminLoginStatus", "Enter your email address.", "error"); return; }
    if (!window.SC || !window.SC.ready) {
      status("adminLoginStatus", "Sign-in isn't connected yet.", "error"); return;
    }

    var button = el("adminLoginSubmit");
    button.disabled = true;
    button.textContent = "Sending…";
    status("adminLoginStatus", "", "");

    window.SC.client.auth
      .signInWithOtp({
        email: email,
        options: { emailRedirectTo: window.location.origin + window.location.pathname }
      })
      .then(function (r) {
        if (r.error) throw r.error;
        status("adminLoginStatus", "Check your inbox. The link lasts an hour.", "ok");
      })
      .catch(function (e) {
        // Say WHY. The usual cause is Supabase's built-in email sender, which
        // allows only a couple of messages an hour - "try again shortly" sent
        // Jack looking in his inbox for a mail that was never sent.
        console.error("[Social Capital] admin sign-in failed", e);
        var why = (e && e.message) || "";
        status("adminLoginStatus",
          /rate|limit|seconds|security purposes/i.test(why)
            ? "Supabase won't send another one yet: " + why +
              " Its built-in sender allows about two an hour. Connecting " +
              "Resend as custom SMTP removes that."
            : "That didn't send" + (why ? " \u2014 " + why : "") + ".",
          "error");
      })
      .then(function () {
        button.disabled = false;
        button.textContent = "Email me a sign-in link";
      });
  }

  // -------------------------------------------------------------------------
  // The pending queue - people who used a form on the site.
  //
  // A mentor form gives us a name, an email, an employer, a sector and two
  // free-text answers ("Junior (0-5 years)", "Yes, happy to"). The card needs
  // a tidy job title and a junior/senior value, which only Jack can decide,
  // so approving a mentor asks for those rather than guessing from the text.
  //
  // A school needs nothing extra: approving one is what lets them sign in.
  // -------------------------------------------------------------------------
  function pendingRow(p) {
    var said = [];
    if (p.raw_level) said.push("said: " + esc(p.raw_level));
    if (p.raw_talks) said.push("talks: " + esc(p.raw_talks));

    var guessLevel = /senior|lead|head|director|partner|manager/i.test(p.raw_level || "")
      ? "senior" : "junior";

    var fields = p.kind === "mentor"
      ? '<div class="pending-fields">' +
          // Deliberately empty. Pre-filling ", Employer" started the field
          // with a comma, which reads like a bug, and the employer is already
          // on the line above.
          '<input type="text" data-f="role" placeholder="Job title, employer \u2014 as it should read">' +
          '<select data-f="level">' +
            '<option value="junior"' + (guessLevel === "junior" ? " selected" : "") + '>Junior</option>' +
            '<option value="senior"' + (guessLevel === "senior" ? " selected" : "") + '>Senior</option>' +
          '</select>' +
          '<input type="text" data-f="exp" placeholder="Small grey line (optional)">' +
        '</div>'
      : "";

    return '' +
      '<div class="pending-row" data-id="' + esc(p.id) + '" data-kind="' + esc(p.kind) + '">' +
        '<div class="pending-head">' +
          '<div>' +
            '<strong>' + esc(p.name || "No name given") + '</strong>' +
            '<div class="pending-meta">' + esc(p.email) +
              (p.detail ? " \u00b7 " + esc(p.detail) : "") +
              (p.industry ? " \u00b7 " + esc(SECTORS[p.industry] || p.industry) : "") +
            '</div>' +
            (said.length ? '<div class="pending-said">' + said.join(" \u00b7 ") + '</div>' : "") +
          '</div>' +
          '<span class="pending-kind">' + (p.kind === "mentor" ? "Mentor" : "School") + '</span>' +
        '</div>' +
        fields +
        '<div class="pending-actions">' +
          '<button type="button" class="btn admin-small" data-act="approve">' +
            (p.kind === "mentor" ? "Approve, hidden" : "Approve \u2014 they can sign in") +
          '</button>' +
          '<button type="button" class="btn-outline admin-small" data-act="reject">Turn down</button>' +
          '<span class="pending-status" data-role="status"></span>' +
        '</div>' +
      '</div>';
  }

  // How often each mentor was shown, and how many people asked to contact
  // them. Impressions are exposure; requests are work.
  function loadLoad() {
    return window.SC.client.rpc("admin_mentor_load", { p_days: 14 }).then(function (r) {
      if (r.error) throw r.error;
      var rows = r.data || [];

      var busy = rows.filter(function (m) { return m.requests > 0; });
      if (!rows.length) {
        el("loadList").innerHTML = '<p class="dir-empty">Nobody on the list yet.</p>';
        return;
      }
      if (!busy.length) {
        el("loadList").innerHTML =
          '<p class="dir-empty">No contact requests yet. Numbers appear here once ' +
          'schools start using the directory.</p>';
        return;
      }

      el("loadList").innerHTML = busy.map(function (m) {
        return '' +
          '<div class="load-row">' +
            '<div>' +
              '<strong>' + esc(m.full_name) + '</strong>' +
              '<span class="load-meta">' + esc(SECTORS[m.industry] || m.industry) +
                (m.is_published ? '' : ' \u00b7 hidden') + '</span>' +
            '</div>' +
            '<div class="load-figures">' +
              '<span><b>' + m.requests + '</b> request' + (m.requests === 1 ? '' : 's') + '</span>' +
              '<span>' + m.impressions + ' shown</span>' +
            '</div>' +
          '</div>';
      }).join("");
    });
  }

  function loadPending() {
    return window.SC.client.rpc("admin_list_pending").then(function (r) {
      if (r.error) throw r.error;
      var rows = r.data || [];
      el("pendingPanel").hidden = rows.length === 0;
      el("pendingList").innerHTML = rows.map(pendingRow).join("");
    });
  }

  function onPendingClick(event) {
    var button = event.target.closest("button[data-act]");
    if (!button) return;

    var card = button.closest(".pending-row");
    var id = card.getAttribute("data-id");
    var kind = card.getAttribute("data-kind");
    var note = card.querySelector('[data-role="status"]');
    var act = button.getAttribute("data-act");

    function fail(message) {
      note.textContent = message;
      note.className = "pending-status error";
      card.querySelectorAll("button").forEach(function (b) { b.disabled = false; });
    }

    if (act === "reject") {
      if (!window.confirm("Turn down " + (card.querySelector("strong").textContent) + "?")) return;
      card.querySelectorAll("button").forEach(function (b) { b.disabled = true; });
      note.textContent = "Saving\u2026";
      note.className = "pending-status";
      window.SC.client.rpc("admin_reject_pending", { p_kind: kind, p_pending_id: id })
        .then(function (r) { if (r.error) throw r.error; return Promise.all([loadPending(), load()]); })
        .catch(function (e) { console.error(e); fail(e.message || "Didn't save"); });
      return;
    }

    var args;
    if (kind === "mentor") {
      var role = (card.querySelector('[data-f="role"]').value || "").trim();
      if (!role) { fail("A job title is needed before this can go on a card."); return; }
      args = {
        p_pending_id: id,
        p_role_title: role,
        p_level: card.querySelector('[data-f="level"]').value,
        p_experience_label: (card.querySelector('[data-f="exp"]').value || "").trim()
      };
    } else {
      args = { p_pending_id: id };
    }

    card.querySelectorAll("button").forEach(function (b) { b.disabled = true; });
    note.textContent = "Saving\u2026";
    note.className = "pending-status";

    window.SC.client
      .rpc(kind === "mentor" ? "admin_approve_mentor" : "admin_approve_school", args)
      .then(function (r) {
        if (r.error) throw r.error;
        return Promise.all([loadPending(), load()]);
      })
      .catch(function (e) { console.error(e); fail(e.message || "Didn't save"); });
  }

  // -------------------------------------------------------------------------
  // The list
  // -------------------------------------------------------------------------
  function row(m) {
    var bits = [];
    if (m.experience_label) bits.push(esc(m.experience_label));
    if (m.open_to_talks) bits.push("does school talks");
    if (m.is_alumnus) bits.push("past pupil" + (m.alumnus_school_name ? ", " + esc(m.alumnus_school_name) : ""));
    if (m.member_contact_ok) bits.push("over-18s may contact");
    if (m.bio) bits.push("has a bio");
    if (m.route_in) bits.push(esc(ROUTES[m.route_in] || m.route_in));
    if (m.study_detail) bits.push(esc(m.study_detail));
    else if (m.study_field) bits.push(esc(FIELDS[m.study_field] || m.study_field));

    return '' +
      '<div class="admin-row' + (m.is_published ? " is-live" : "") + '" data-id="' + esc(m.id) + '">' +
        '<div class="admin-row-main">' +
          '<strong>' + esc(m.full_name) + '</strong>' +
          '<span class="admin-row-role">' + esc(m.role_title) + '</span>' +
          '<span class="admin-row-meta">' +
            esc(SECTORS[m.industry] || m.industry) + " · " + esc(m.level) +
            (bits.length ? " · " + bits.join(" · ") : "") +
          '</span>' +
          '<span class="admin-row-private">' + esc(m.contact_email || "no email on file") +
            (m.notes ? " · " + esc(m.notes) : "") + '</span>' +
        '</div>' +
        '<div class="admin-row-actions">' +
          '<span class="admin-badge">' + (m.is_published ? "Live" : "Hidden") + '</span>' +
          '<button type="button" class="btn-outline admin-small" data-act="edit">Edit</button>' +
          '<button type="button" class="btn-outline admin-small" data-act="toggle">' +
            (m.is_published ? "Hide" : "Publish") + '</button>' +
        '</div>' +
      '</div>';
  }

  var cache = [];

  function load() {
    return window.SC.client.rpc("admin_list_mentors").then(function (r) {
      if (r.error) throw r.error;
      cache = r.data || [];

      var live = cache.filter(function (m) { return m.is_published; }).length;
      el("adminCounts").textContent =
        cache.length === 0
          ? "Nobody on the list yet."
          : cache.length + " on the list, " + live + " live, " + (cache.length - live) + " hidden.";

      el("mentorList").innerHTML = cache.length
        ? cache.map(row).join("")
        : '<p class="dir-empty">Add the first person above.</p>';
    });
  }

  // -------------------------------------------------------------------------
  // Add and edit share one form. m_id decides which.
  // -------------------------------------------------------------------------
  function resetForm() {
    el("mentorForm").reset();
    el("m_id").value = "";
    checkBio();
    el("formHeading").textContent = "Add a mentor";
    el("formNote").textContent =
      "New people are saved hidden. Nothing reaches a school until you publish it below.";
    el("mentorSubmit").textContent = "Save, hidden";
    el("mentorCancel").hidden = true;
    el("privateFields").hidden = false;
    el("m_contact_email").required = true;
    status("mentorStatus", "", "");
  }

  function startEdit(id) {
    var m = cache.filter(function (x) { return x.id === id; })[0];
    if (!m) return;

    el("m_id").value = m.id;
    el("m_full_name").value = m.full_name || "";
    el("m_role_title").value = m.role_title || "";
    el("m_industry").value = m.industry || "other";
    el("m_level").value = m.level || "junior";
    el("m_experience_label").value = m.experience_label || "";
    el("m_open_to_talks").checked = !!m.open_to_talks;
    el("m_is_alumnus").checked = !!m.is_alumnus;
    el("m_member_contact_ok").checked = !!m.member_contact_ok;
    el("m_alumnus_school_name").value = m.alumnus_school_name || "";
    el("m_public_contact").value = m.public_contact || "";
    el("m_route_in").value = m.route_in || "";
    el("m_study_field").value = m.study_field || "";
    el("m_study_detail").value = m.study_detail || "";
    el("m_qualification").value = m.qualification || "";
    el("m_bio").value = m.bio || "";
    checkBio();

    // The update function deliberately does not touch the private record.
    el("privateFields").hidden = true;
    el("m_contact_email").required = false;

    el("formHeading").textContent = "Editing " + m.full_name;
    el("formNote").textContent =
      "Changing the public details only. Their email, employer and your notes are " +
      "edited in the Supabase dashboard, which keeps that record harder to change by accident.";
    el("mentorSubmit").textContent = "Save changes";
    el("mentorCancel").hidden = false;
    status("mentorStatus", "", "");
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  function submit(event) {
    event.preventDefault();

    if (!val("m_full_name") || !val("m_role_title")) {
      status("mentorStatus", "A name and a job title are needed.", "error");
      return;
    }

    var editing = !!val("m_id");
    if (!editing && !val("m_contact_email")) {
      status("mentorStatus", "Their email is needed. It is never shown on the site.", "error");
      return;
    }

    var button = el("mentorSubmit");
    var label = button.textContent;
    button.disabled = true;
    button.textContent = "Saving…";
    status("mentorStatus", "", "");

    var shared = {
      p_full_name: val("m_full_name"),
      p_role_title: val("m_role_title"),
      p_industry: val("m_industry"),
      p_level: val("m_level"),
      p_experience_label: val("m_experience_label"),
      p_open_to_talks: checked("m_open_to_talks"),
      p_is_alumnus: checked("m_is_alumnus"),
      p_alumnus_school_name: val("m_alumnus_school_name"),
      p_member_contact_ok: checked("m_member_contact_ok"),
      p_public_contact: val("m_public_contact"),
      p_public_contact_kind: val("m_public_contact_kind"),
      p_route_in: val("m_route_in"),
      p_study_field: val("m_study_field"),
      p_study_detail: val("m_study_detail"),
      p_qualification: val("m_qualification"),
      p_bio: val("m_bio")
    };

    var call;
    if (editing) {
      shared.p_mentor_id = val("m_id");
      call = window.SC.client.rpc("admin_update_mentor", shared);
    } else {
      shared.p_contact_email = val("m_contact_email");
      shared.p_employer = val("m_employer");
      shared.p_phone = val("m_phone");
      shared.p_notes = val("m_notes");
      call = window.SC.client.rpc("admin_add_mentor", shared);
    }

    call
      .then(function (r) {
        if (r.error) throw r.error;
        var name = val("m_full_name");
        resetForm();
        return load().then(function () {
          status("mentorStatus",
            editing ? "Saved." : name + " added, hidden. Publish them below when you are ready.",
            "ok");
        });
      })
      .catch(function (e) {
        console.error("[Social Capital] save failed", e);
        status("mentorStatus",
          e && e.message ? "Didn't save: " + e.message : "Didn't save. Try again.",
          "error");
      })
      .then(function () {
        button.disabled = false;
        if (button.textContent === "Saving…") button.textContent = label;
      });
  }

  // -------------------------------------------------------------------------
  function onListClick(event) {
    var button = event.target.closest("button[data-act]");
    if (!button) return;
    var id = button.closest(".admin-row").getAttribute("data-id");

    if (button.getAttribute("data-act") === "edit") { startEdit(id); return; }

    var m = cache.filter(function (x) { return x.id === id; })[0];
    if (!m) return;
    if (m.is_published && !window.confirm("Hide " + m.full_name + " from schools?")) return;

    button.disabled = true;
    window.SC.client
      .rpc("admin_set_published", { p_mentor_id: id, p_published: !m.is_published })
      .then(function (r) {
        if (r.error) throw r.error;
        return load();
      })
      .catch(function (e) {
        console.error("[Social Capital] publish toggle failed", e);
        alert("That didn't work: " + (e && e.message ? e.message : "unknown error"));
        button.disabled = false;
      });
  }

  // -------------------------------------------------------------------------
  function init() {
    if (!window.SC || !window.SC.ready) {
      status("adminLoginStatus", "Sign-in isn't connected yet.", "error");
      return;
    }

    window.SC.client.auth.getSession().then(function (res) {
      var session = res.data && res.data.session;
      if (!session) return;

      screen("adminChecking");

      window.SC.client.rpc("is_admin").then(function (check) {
        // Two different failures, which used to share one message and sent
        // Jack hunting for the wrong problem. An ERROR means is_admin() isn't
        // there - the setup SQL has not been run. FALSE means it ran fine and
        // this address simply is not on the list. Say which.
        if (check.error) {
          console.error("[Social Capital] is_admin failed", check.error);
          window.SC.client.auth.signOut();
          screen("adminLogin");
          status("adminLoginStatus",
            "This page isn't set up yet \u2014 run supabase/admin-page.sql in the " +
            "Supabase SQL Editor, then sign in again. (" +
            (check.error.message || "no detail") + ")", "error");
          return;
        }

        if (check.data !== true) {
          window.SC.client.auth.signOut();
          screen("adminLogin");
          status("adminLoginStatus",
            "That address isn't on the admin list. Check the email in the " +
            "admins table matches the one you just used.", "error");
          return;
        }

        el("adminWho").textContent = session.user.email;
        screen("adminApp");

        loadLoad().catch(function (e) {
          // Missing function means mentor-load.sql has not been run. The rest
          // of the page is unaffected, so say so quietly and carry on.
          console.error("[Social Capital] load panel failed", e);
          el("loadList").innerHTML =
            '<p class="dir-empty">Can\'t read the figures \u2014 run ' +
            'supabase/mentor-load.sql in Supabase, then refresh.</p>';
        });

        loadPending().catch(function (e) {
          // A missing function here means admin-pending.sql has not been run.
          // The rest of the page still works, so say so and carry on.
          console.error("[Social Capital] pending queue failed", e);
          el("pendingPanel").hidden = false;
          el("pendingList").innerHTML =
            '<p class="dir-empty">Can\'t read the queue \u2014 run ' +
            'supabase/admin-pending.sql in Supabase, then refresh.</p>';
        });

        load().catch(function (e) {
          console.error("[Social Capital] list failed", e);
          el("mentorList").innerHTML =
            '<p class="dir-empty">Couldn\'t load the list. Refresh to try again.</p>';
        });
      });
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    el("adminLoginForm").addEventListener("submit", sendLink);
    el("mentorForm").addEventListener("submit", submit);
    el("mentorCancel").addEventListener("click", resetForm);
    el("mentorList").addEventListener("click", onListClick);
    el("m_bio").addEventListener("input", checkBio);
    el("pendingList").addEventListener("click", onPendingClick);
    el("adminSignOut").addEventListener("click", function () {
      window.SC.client.auth.signOut().then(function () {
        window.location.replace("index.html");
      });
    });
    init();
  });
})();
