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

  function renderMentors(rows) {
    var list = document.getElementById("mentorList");
    if (!list) return;

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
        return (
          '<div class="mentor-card">' +
            '<div class="mentor-avatar">' + escapeHtml(initials(m.full_name)) + "</div>" +
            '<div class="mentor-info">' +
              "<h4>" + escapeHtml(m.full_name) + "</h4>" +
              "<p>" + escapeHtml(m.role_title) + "</p>" +
              '<span class="mentor-badge ' + (m.level === "junior" ? "junior" : "") + '">' +
                badge + detail +
              "</span>" +
              talks +
            "</div>" +
          "</div>"
        );
      })
      .join("");
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
      .select("full_name, role_title, level, experience_label, open_to_talks")
      .eq("industry", slug)
      .eq("is_published", true)
      .order("level", { ascending: true })
      .order("full_name", { ascending: true })
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
