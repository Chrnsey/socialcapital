// ===========================================================================
// Sector and route icons.
//
// Lucide (ISC licence), with the path data copied in rather than the library
// loaded. Three reasons: a guidance counsellor opens this on an old laptop
// sharing a room's wifi with thirty students, so one fewer network request
// matters; the icons never change, so there is nothing to keep up to date;
// and nothing breaks if a CDN is blocked on the school network, which plenty
// are.
//
// Each entry is the INNER markup of a 24x24 Lucide icon. SCIcons.svg() wraps
// it in the stroke settings Lucide uses, so an icon drawn here looks the same
// as one from the library.
//
// Adding one: find it at lucide.dev, copy the paths out of the SVG, and give
// it a key. Keep stroke attributes off the paths - they are set on the <svg>.
// ===========================================================================
(function () {
  var P = {
    // --- sectors, keyed to the slugs in content/sectors.json ---------------
    technology:    '<rect width="16" height="16" x="4" y="4" rx="2"/><rect width="6" height="6" x="9" y="9" rx="1"/><path d="M15 2v2M15 20v2M2 15h2M2 9h2M20 15h2M20 9h2M9 2v2M9 20v2"/>',
    healthcare:    '<path d="M11 2v2a1 1 0 0 1-1 1H9a1 1 0 0 0-1 1v1a4 4 0 0 0 8 0V6a1 1 0 0 0-1-1h-1a1 1 0 0 1-1-1V2"/><path d="M8 15a6 6 0 0 0 12 0v-3"/><circle cx="20" cy="10" r="2"/><path d="M11 9v6a5 5 0 0 1-5 5 3 3 0 0 1-3-3v-3"/>',
    law:           '<path d="m16 16 3-8 3 8c-.87.65-1.92 1-3 1s-2.13-.35-3-1Z"/><path d="m2 16 3-8 3 8c-.87.65-1.92 1-3 1s-2.13-.35-3-1Z"/><path d="M7 21h10M12 3v18M3 7h2c2 0 5-1 7-2 2 1 5 2 7 2h2"/>',
    finance:       '<circle cx="8" cy="8" r="6"/><path d="M18.09 10.37A6 6 0 1 1 10.34 18M7 6h1v4M16.71 13.88l.7.71-2.82 2.82"/>',
    trades:        '<path d="M15 12l-8.5 8.5a2.12 2.12 0 1 1-3-3L12 9"/><path d="M17.64 15 22 10.64"/><path d="m20.91 11.7-1.25-1.25c-.6-.6-.93-1.4-.93-2.25v-.86L16.01 4.6a5.56 5.56 0 0 0-3.94-1.64H9l.92.82A6.18 6.18 0 0 1 12 8.4v1.56l2 2h2.47l2.26 1.91"/>',
    media:         '<path d="M20.2 6 3 11l-.9-2.4c-.3-1.1.3-2.2 1.3-2.5l13.5-4c1.1-.3 2.2.3 2.5 1.3Z"/><path d="m6.2 5.3 3.1 3.9M12.4 3.4l3.1 4M3 11h18v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z"/>',
    education:     '<path d="M21.42 10.922a1 1 0 0 0-.019-1.838L12.83 5.18a2 2 0 0 0-1.66 0L2.6 9.08a1 1 0 0 0 0 1.832l8.57 3.908a2 2 0 0 0 1.66 0z"/><path d="M22 10v6"/><path d="M6 12.5V16a6 3 0 0 0 12 0v-3.5"/>',
    engineering:   '<path d="m12.99 6.74 1.93 3.44"/><path d="M19.136 12a10 10 0 0 1-14.271 0"/><path d="m21 21-2.16-3.84"/><path d="m3 21 8.02-14.26"/><circle cx="12" cy="5" r="2"/>',
    public_sector: '<path d="M10 18v-7M11.12 2.198a2 2 0 0 1 1.76.006l7.866 3.847c.476.233.31.949-.22.949H3.474c-.53 0-.695-.716-.22-.949z"/><path d="M14 18v-7M18 18v-7M3 22h18M6 18v-7"/>',
    other:         '<path d="M8.3 10a.7.7 0 0 1-.626-1.079L11.4 3a.7.7 0 0 1 1.198-.043L16.3 8.9a.7.7 0 0 1-.6 1.1Z"/><rect x="3" y="14" width="7" height="7" rx="1"/><circle cx="17.5" cy="17.5" r="3.5"/>',

    // --- guide sections, used on the public hub ----------------------------
    routes:        '<circle cx="6" cy="19" r="3"/><path d="M9 19h8.5a3.5 3.5 0 0 0 0-7h-11a3.5 3.5 0 0 1 0-7H15"/><circle cx="18" cy="5" r="3"/>',
    funding:       '<rect width="20" height="12" x="2" y="6" rx="2"/><circle cx="12" cy="12" r="2"/><path d="M6 12h.01M18 12h.01"/>',
    careers:       '<path d="M16 20V4a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16"/><rect width="20" height="14" x="2" y="6" rx="2"/>'
  };

  window.SCIcons = {
    has: function (name) { return Object.prototype.hasOwnProperty.call(P, name); },

    // Returns an <svg> string. aria-hidden because every icon here sits beside
    // its own text label - announcing it again would just be noise.
    svg: function (name, cls) {
      var inner = P[name] || P.other;
      return '<svg class="sc-icon' + (cls ? " " + cls : "") + '" viewBox="0 0 24 24" ' +
        'fill="none" stroke="currentColor" stroke-width="1.75" ' +
        'stroke-linecap="round" stroke-linejoin="round" ' +
        'aria-hidden="true" focusable="false">' + inner + "</svg>";
    }
  };
})();
