// ===========================================================================
// Makes the public forms actually submit into the "pending" tables.
//
// A form opts in by carrying  data-sc-form="school_registration"  (or one of
// the other names below). Every input inside it is read by its `name`.
// ===========================================================================
(function () {
  var FORMS = {
    school_registration: {
      table: "pending_schools",
      build: function (v) {
        return {
          school_name: v.school_name,
          contact_name: v.contact_name,
          email: (v.email || "").trim().toLowerCase(),
          county: v.county || null
        };
      },
      success: "Thanks — we'll be in touch within two working days."
    },

    mentor_signup: {
      table: "pending_mentors",
      build: function (v) {
        return {
          full_name: [v.first_name, v.last_name].filter(Boolean).join(" ").trim(),
          email: (v.email || "").trim().toLowerCase(),
          industry: v.industry || null,
          experience_level: v.experience_level || null,
          open_to_talks: v.open_to_talks || null,
          is_alumnus: v.is_alumnus === "yes",
          alumnus_school_name: v.alumnus_school_name || null,
          source: "mentors_page"
        };
      },
      success: "Thanks — we'll be in touch before you're listed anywhere."
    },

    business_mentor: {
      table: "pending_mentors",
      build: function (v) {
        return {
          full_name: (v.full_name || "").trim(),
          email: (v.email || "").trim().toLowerCase(),
          company: v.company || null,
          industry: v.industry || null,
          source: "business_modal"
        };
      },
      success: "Thanks — we'll be in touch before anyone is listed."
    }
  };

  function setStatus(form, message, kind) {
    var el = form.querySelector("[data-sc-status]");
    if (!el) return;
    el.textContent = message;
    el.className = "form-status" + (kind ? " " + kind : "");
  }

  function wire(form) {
    var config = FORMS[form.getAttribute("data-sc-form")];
    if (!config) return;

    form.addEventListener("submit", function (event) {
      event.preventDefault();

      // If something's missing, say WHICH field in plain words. The browser's
      // own tooltip is easy to miss and reads like a fault rather than a
      // prompt, which had people thinking the form was broken.
      var invalid = form.querySelector("input:invalid, select:invalid, textarea:invalid");
      if (invalid) {
        var label = form.querySelector('label[for="' + invalid.id + '"]');
        var name = label ? label.textContent.replace(/\s*\?$/, "") : "a required field";
        setStatus(form, "Please fill in your " + name.toLowerCase() + ".", "error");
        invalid.focus();
        return;
      }

      var values = {};
      new FormData(form).forEach(function (value, key) {
        values[key] = typeof value === "string" ? value.trim() : value;
      });

      // Honeypot: a field hidden from people but often filled by spam bots.
      // If it has anything in it, quietly pretend everything went fine.
      if (values._hp) {
        setStatus(form, config.success, "ok");
        form.reset();
        return;
      }

      if (!window.SC || !window.SC.ready) {
        setStatus(
          form,
          "This form isn't connected yet. Please email registration@socialcapital.ie.",
          "error"
        );
        return;
      }

      var button = form.querySelector("[type=submit]");
      var originalLabel = button ? button.textContent : "";
      if (button) {
        button.disabled = true;
        button.textContent = "Sending…";
      }
      setStatus(form, "", "");

      window.SC.client
        .from(config.table)
        .insert(config.build(values))
        .then(function (result) {
          if (result.error) throw result.error;
          setStatus(form, config.success, "ok");
          form.reset();
        })
        .catch(function (error) {
          console.error("[Social Capital] submission failed", error);
          setStatus(
            form,
            "Sorry — that didn't send. Please try again, or email registration@socialcapital.ie.",
            "error"
          );
        })
        .then(function () {
          if (button) {
            button.disabled = false;
            button.textContent = originalLabel;
          }
        });
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    document.querySelectorAll("[data-sc-form]").forEach(wire);
  });
})();
