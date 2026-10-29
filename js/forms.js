// ===========================================================================
// Makes the public forms actually submit into the "pending" tables.
//
// A form opts in by carrying  data-sc-form="school_registration"  (or one of
// the other names below). Every input inside it is read by its `name`.
// ===========================================================================
(function () {
  // Both mentor signup forms take an optional photo. It goes up before the
  // signup row, so the row can point at it. If it fails the signup still goes
  // through: losing a willing mentor over a photo is not worth it, and the
  // thank-you message says so.
  function uploadPhoto(v) {
    var file = v.photo;
    if (!file || !file.size || !window.SC_photo) return Promise.resolve({});
    return window.SC_photo.upload(file, "pending").then(
      function (path) { return { photo_path: path }; },
      function (e) {
        console.warn("[Social Capital] photo not uploaded", e);
        return { _photoFailed: true };
      }
    );
  }
  var NO_PHOTO = "Thanks, we've got your details. Your photo didn't upload, so please email it to registration@socialcapital.ie.";

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
          role_title: (v.role_title || "").trim() || null,
          industry: v.industry || null,
          experience_level: v.experience_level || null,
          // Not asked at signup any more. A mentor has no idea what a school
          // talk involves until they have done something smaller first, so
          // asking here just collects a cautious no. It arrives null and is
          // ticked per mentor on the admin page once they are in.
          is_alumnus: v.is_alumnus === "yes",
          alumnus_school_name: v.alumnus_school_name || null,
          member_contact_ok: v.member_contact_ok === "yes",
          public_contact: v.public_contact || null,
          public_email: (v.public_email || "").trim().toLowerCase() || null,
          source: "mentors_page"
        };
      },
      prepare: uploadPhoto,
      success: "Thanks — we'll be in touch before you're listed anywhere.",
      successNoPhoto: NO_PHOTO
    },

    // Not a plain insert: this redeems a one-time invitation issued by the
    // school, checking the token, the address it was issued to, and the date
    // of birth, without the browser ever seeing the list of invitations.
    //
    // "invalid" covers a token that does not exist, a token issued to a
    // different address, and a revoked one. Deliberately the same answer for
    // all three: telling somebody that their token is real but their email is
    // wrong confirms the token is real.
    alumni_signup: {
      rpc: "accept_invite",
      args: function (v) {
        return {
          p_token: (v.code || "").trim(),
          p_email: (v.email || "").trim().toLowerCase(),
          p_dob: v.date_of_birth || null
        };
      },
      outcomes: {
        ok: ["You're set up. Use \u201CSign in\u201D and we'll email you a link.", "ok"],
        invalid: ["That invitation isn't valid for this email address. Use the exact address your school sent it to, or ask them to send a new one.", "error"],
        already_used: ["That invitation has already been used. If it wasn't you, tell your school.", "error"],
        expired: ["That invitation has expired. Ask your school for a new one \u2014 it takes them a moment.", "error"],
        under_18: ["You need to be 18 or over to sign up here. Have a look at the guides in the meantime \u2014 they're open to everyone.", "error"]
      }
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
      prepare: uploadPhoto,
      success: "Thanks — we'll be in touch before anyone is listed.",
      successNoPhoto: NO_PHOTO
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

      // Fields the database may not have yet, if a migration hasn't been run.
      // Losing a willing mentor to a schema mismatch is not acceptable, so if
      // the insert is rejected for an unknown column we drop the optional
      // fields and try again. The submission matters more than the extras.
      // Every column added by a migration after the original schema belongs
      // here. role_title was added to the form on 21 October and left off
      // this list, so when its migration had not been run the retry dropped
      // the other extras and failed again on the same column - a week of
      // mentor signups rejected, by the one safety net meant to prevent it.
      var OPTIONAL = ["role_title", "is_alumnus", "alumnus_school_name",
                      "left_school_year", "member_contact_ok", "public_contact",
                      "public_email", "photo_path"];

      function insert(row) {
        return window.SC.client.from(config.table).insert(row);
      }
      function looksLikeMissingColumn(error) {
        var t = ((error && error.message) || "") + " " + ((error && error.code) || "");
        return /column|schema cache|PGRST204|42703/i.test(t);
      }

      // Function-backed forms (the alumni signup) take a different path.
      if (config.rpc) {
        window.SC.client
          .rpc(config.rpc, config.args(values))
          .then(function (result) {
            if (result.error) throw result.error;
            var outcome = config.outcomes[result.data] ||
              ["Something went wrong there. Please email registration@socialcapital.ie.", "error"];
            setStatus(form, outcome[0], outcome[1]);
            if (outcome[1] === "ok") form.reset();
          })
          .catch(function (error) {
            console.error("[Social Capital] signup failed", error);
            setStatus(form, "Sorry \u2014 that didn't work. Please try again, or email registration@socialcapital.ie.", "error");
          })
          .then(function () {
            if (button) { button.disabled = false; button.textContent = originalLabel; }
          });
        return;
      }

      var row = config.build(values);
      var photoFailed = false;

      (config.prepare ? config.prepare(values) : Promise.resolve({}))
        .then(function (extra) {
          photoFailed = !!extra._photoFailed;
          delete extra._photoFailed;
          Object.keys(extra).forEach(function (k) { row[k] = extra[k]; });
          return insert(row);
        })
        .then(function (result) {
          if (!result.error) return result;
          if (!looksLikeMissingColumn(result.error)) throw result.error;
          console.warn(
            "[Social Capital] database is missing a newer column — " +
            "submitting without the optional fields. Run the latest SQL " +
            "migration to capture them.", result.error.message
          );
          var trimmed = {};
          Object.keys(row).forEach(function (k) {
            if (OPTIONAL.indexOf(k) === -1) trimmed[k] = row[k];
          });
          return insert(trimmed);
        })
        .then(function (result) {
          if (result.error) throw result.error;
          setStatus(form, photoFailed ? config.successNoPhoto : config.success, "ok");
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
