// ===========================================================================
// The mentor directory, built from real database rows.
//
// Everything here runs only for a signed-in, approved school. If the database
// rules say otherwise, these queries simply come back empty — the page cannot
// talk its way past them.
// ===========================================================================
(function () {
  var sectors = [];   // from content/sectors.json
  var counts = {};    // how many mentors per sector
  var started = false;

  function initials(name) {
    return (name || "")
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map(function (part) { return part[0].toUpperCase(); })
      .join("");
  }

  function escapeHtml(value) {
    return String(value == null ? "" : value).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function renderSectorCards() {
    var container = document.getElementById("industryCards");
    if (!container) return;

    container.innerHTML = sectors
      .map(function (sector) {
        var n = counts[sector.slug] || 0;
        var label =
          n === 0 ? "No mentors listed yet" :
          n === 1 ? "1 mentor available" :
          n + " mentors available";
        return (
          '<div class="industry-card" data-sector="' + escapeHtml(sector.slug) + '">' +
            '<div class="industry-card-left">' +
              "<h4>" + escapeHtml(sector.title) + "</h4>" +
              "<span>" + label + "</span>" +
            "</div>" +
            '<span class="industry-card-arrow">›</span>' +
          "</div>"
        );
      })
      .join("");

    container.querySelectorAll("[data-sector]").forEach(function (card) {
      card.addEventListener("click", function () {
        openSector(card.getAttribute("data-sector"));
      });
    });
  }

  // Someone who went to the school the student actually attends is worth
  // more than any job title, so they go to the top and get said so.
  function sortMentors(rows) {
    var mySchool = window.SC && window.SC.school && window.SC.school.id;
    return rows.slice().sort(function (a, b) {
      var aMine = mySchool && a.alumnus_school_id === mySchool ? 1 : 0;
      var bMine = mySchool && b.alumnus_school_id === mySchool ? 1 : 0;
      if (aMine !== bMine) return bMine - aMine;
      var aAlum = a.is_alumnus ? 1 : 0, bAlum = b.is_alumnus ? 1 : 0;
      if (aAlum !== bAlum) return bAlum - aAlum;
      return (a.full_name || "").localeCompare(b.full_name || "");
    });
  }

  function alumniBadge(m) {
    var mySchool = window.SC && window.SC.school && window.SC.school.id;
    if (mySchool && m.alumnus_school_id === mySchool) {
      return '<span class="mentor-alum mentor-alum-own">Went to your school</span>';
    }
    if (m.is_alumnus) {
      var where = m.alumnus_school_name
        ? " \u00B7 " + escapeHtml(m.alumnus_school_name) : "";
      return '<span class="mentor-alum">Went to a DEIS school' + where + "</span>";
    }
    return "";
  }

  function renderMentors(rows) {
    var list = document.getElementById("mentorList");
    if (!list) return;
    rows = sortMentors(rows);

    if (!rows.length) {
      list.innerHTML =
        '<p class="dir-empty">No mentors listed in this sector yet. ' +
        'We\'re adding them as they join — ' +
        '<a href="mailto:registration@socialcapital.ie">tell us what you\'re looking for</a> ' +
        "and we'll try to find someone.</p>";
      return;
    }

    list.innerHTML = rows
      .map(function (m) {
        var badge = m.level === "junior" ? "Junior mentor" : "Senior mentor";
        var detail = m.experience_label ? " · " + escapeHtml(m.experience_label) : "";
        var talks = m.open_to_talks
          ? '<span class="mentor-talks">Open to school talks</span>' : "";
        var alum = alumniBadge(m);
        // Only adults signed in as alumni are offered contact details, and
        // only where the mentor agreed to it. The detail itself is fetched
        // on demand - it is never in the page until asked for.
        var contact = (window.SC && window.SC.viewer === "alumnus" && m.alumni_contact_ok)
          ? '<span class="mentor-contact"><button type="button" data-contact="' +
            escapeHtml(m.id) + '">How to reach them</button></span>'
          : "";
        return (
          '<div class="mentor-card">' +
            '<div class="mentor-avatar">' + escapeHtml(initials(m.full_name)) + "</div>" +
            '<div class="mentor-info">' +
              "<h4>" + escapeHtml(m.full_name) + "</h4>" +
              "<p>" + escapeHtml(m.role_title) + "</p>" +
              '<span class="mentor-badge ' + (m.level === "junior" ? "junior" : "") + '">' +
                badge + detail +
              "</span>" +
              talks + alum + contact +
            "</div>" +
          "</div>"
        );
      })
      .join("");

    list.querySelectorAll("[data-contact]").forEach(function (btn) {
      btn.addEventListener("click", function () {
        var id = btn.getAttribute("data-contact");
        btn.disabled = true;
        btn.textContent = "Looking…";
        window.SC.client.rpc("mentor_contact", { p_mentor: id }).then(function (res) {
          var row = res.data && res.data[0];
          if (res.error || !row || !row.contact) {
            btn.textContent = "Not shared";
            return;
          }
          var wrap = btn.parentNode;
          var value = row.contact;
          var isLink = /^https?:\/\//i.test(value);
          var isEmail = value.indexOf("@") !== -1 && !isLink;
          wrap.innerHTML = isLink
            ? '<a class="revealed" href="' + escapeHtml(value) + '" rel="noopener" target="_blank">' + escapeHtml(value) + "</a>"
            : isEmail
              ? '<a class="revealed" href="mailto:' + escapeHtml(value) + '">' + escapeHtml(value) + "</a>"
              : '<span class="revealed">' + escapeHtml(value) + "</span>";
        });
      });
    });
  }

  function openSector(slug) {
    var sector = sectors.filter(function (s) { return s.slug === slug; })[0];
    if (!sector) return;

    document.getElementById("mentorViewTitle").textContent = sector.title;
    document.getElementById("sectorSummary").textContent = sector.summary || "";
    document.getElementById("mentorList").innerHTML =
      '<p class="dir-empty">Loading…</p>';
    document.getElementById("mentorView").classList.add("active");
    document.getElementById("industryCards").style.display = "none";

    window.SC.client
      .from("mentors")
      .select("id, full_name, role_title, level, experience_label, open_to_talks, alumni_contact_ok, is_alumnus, alumnus_school_id, alumnus_school_name")
      .eq("industry", slug)
      .eq("is_published", true)
      .then(function (res) {
        if (res.error) throw res.error;
        renderMentors(res.data || []);
      })
      .catch(function (error) {
        console.error("[Social Capital] mentor query failed", error);
        document.getElementById("mentorList").innerHTML =
          '<p class="dir-empty">Couldn\'t load mentors just now. Please refresh.</p>';
      });
  }

  function closeSector() {
    document.getElementById("mentorView").classList.remove("active");
    document.getElementById("industryCards").style.display = "flex";
  }

  window.SCDirectory = {
    closeSector: closeSector,

    // Called by auth.js once a school is confirmed as approved.
    start: function () {
      if (started) return;
      started = true;

      fetch("content/sectors.json", { cache: "no-cache" })
        .then(function (r) { return r.json(); })
        .then(function (data) { sectors = data.sectors || []; })
        .catch(function () { sectors = []; })
        .then(function () {
          return window.SC.client
            .from("mentors")
            .select("industry")
            .eq("is_published", true);
        })
        .then(function (res) {
          counts = {};
          (res && res.data ? res.data : []).forEach(function (row) {
            counts[row.industry] = (counts[row.industry] || 0) + 1;
          });
          renderSectorCards();
          closeSector();
        })
        .catch(function (error) {
          console.error("[Social Capital] directory failed to load", error);
        });
    }
  };
})();
