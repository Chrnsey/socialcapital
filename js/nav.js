// ===========================================================================
// The phone menu.
//
// Every page's nav is the same three things in the HTML: the logo, a list of
// links, and a "Sign in" button. On a desktop all of that fits in one row.
// On a phone it was stacking to 136px tall and breaking labels mid-phrase,
// so this script collapses the list of links behind a menu button.
//
// WHY THIS IS JAVASCRIPT AND NOT JUST CSS
// ---------------------------------------
// The class "js-nav" is added by this file, and the CSS only hides the links
// when that class is present. So if this file ever fails to load, the nav
// falls back to the old long version - tall, but completely working. Nobody
// ever gets a menu button that does nothing.
//
// The button itself is built here rather than pasted into all ten pages,
// so there is one copy of it to change.
// ===========================================================================
(function () {
  var PHONE = 640;

  document.addEventListener("DOMContentLoaded", function () {
    var nav = document.querySelector("nav");
    if (!nav) return;

    var links = nav.querySelector(".nav-links");
    if (!links) return;

    if (!links.id) links.id = "navLinks";

    var button = document.createElement("button");
    button.className = "nav-toggle";
    button.type = "button";
    button.setAttribute("aria-expanded", "false");
    button.setAttribute("aria-controls", links.id);
    button.setAttribute("aria-label", "Menu");
    button.innerHTML = '<span class="nav-toggle-bars" aria-hidden="true"></span>';

    nav.appendChild(button);
    nav.classList.add("js-nav");

    function setOpen(open) {
      if (open) links.setAttribute("data-open", "");
      else links.removeAttribute("data-open");
      button.setAttribute("aria-expanded", open ? "true" : "false");
    }

    function isOpen() { return links.hasAttribute("data-open"); }

    button.addEventListener("click", function (event) {
      event.stopPropagation();
      setOpen(!isOpen());
    });

    // Tapping anywhere else closes it, which is what people expect.
    document.addEventListener("click", function (event) {
      if (isOpen() && !nav.contains(event.target)) setOpen(false);
    });

    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && isOpen()) {
        setOpen(false);
        button.focus();
      }
    });

    // Following a link should not leave the menu hanging open behind the
    // new page, and on same-page anchors nothing else would close it.
    links.addEventListener("click", function (event) {
      if (event.target.closest("a")) setOpen(false);
    });

    // Turning the phone sideways can cross the breakpoint, at which point
    // the links are visible anyway and the open state is meaningless.
    window.addEventListener("resize", function () {
      if (window.innerWidth > PHONE && isOpen()) setOpen(false);
    });
  });
})();
