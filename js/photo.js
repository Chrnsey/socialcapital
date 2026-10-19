// ===========================================================================
// Mentor photos: shrink in the browser, then upload to the private bucket.
//
// Every photo becomes a 600px square JPEG, cropped from the centre, before
// it leaves the device. That keeps files small, makes every card the same
// shape, and drops the hidden details a phone camera stores in the file
// (location among them), because redrawing an image keeps only the pixels.
//
// Used by the mentor signup form (pending/...) and the admin page
// (mentors/...). The bucket and its rules are in supabase/mentor-photos.sql.
// ===========================================================================
(function () {
  var BUCKET = "mentor-photos";
  var SIZE = 600;

  function decode(file) {
    // createImageBitmap respects the phone's "this way up" flag where it can.
    if (window.createImageBitmap) {
      return createImageBitmap(file, { imageOrientation: "from-image" })
        .catch(function () { return createImageBitmap(file); });
    }
    return new Promise(function (resolve, reject) {
      var url = URL.createObjectURL(file);
      var img = new Image();
      img.onload = function () { URL.revokeObjectURL(url); resolve(img); };
      img.onerror = function () { URL.revokeObjectURL(url); reject(new Error("unreadable")); };
      img.src = url;
    });
  }

  function toJpeg(file) {
    if (!file || !/^image\//.test(file.type || "image/")) {
      return Promise.reject(new Error("not an image"));
    }
    return decode(file).then(function (img) {
      var w = img.width, h = img.height;
      var side = Math.min(w, h);
      var canvas = document.createElement("canvas");
      canvas.width = SIZE;
      canvas.height = SIZE;
      canvas.getContext("2d").drawImage(
        img, (w - side) / 2, (h - side) / 2, side, side, 0, 0, SIZE, SIZE
      );
      return new Promise(function (resolve, reject) {
        canvas.toBlob(function (blob) {
          blob ? resolve(blob) : reject(new Error("could not encode"));
        }, "image/jpeg", 0.85);
      });
    });
  }

  // A random name, so nobody can guess one photo's address from another's.
  function newName(folder) {
    var id;
    if (crypto.randomUUID) {
      id = crypto.randomUUID();
    } else {
      var b = crypto.getRandomValues(new Uint8Array(16));
      b[6] = (b[6] & 15) | 64;   // version 4
      b[8] = (b[8] & 63) | 128;  // variant
      var hex = Array.prototype.map.call(b, function (x) {
        return (x + 256).toString(16).slice(1);
      }).join("");
      id = [hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16),
            hex.slice(16, 20), hex.slice(20)].join("-");
    }
    return folder + "/" + id + ".jpg";
  }

  // Resolves to the stored path, e.g. "pending/<uuid>.jpg".
  function upload(file, folder) {
    return toJpeg(file).then(function (blob) {
      var path = newName(folder);
      return window.SC.client.storage
        .from(BUCKET)
        .upload(path, blob, { contentType: "image/jpeg", upsert: false })
        .then(function (res) {
          if (res.error) throw res.error;
          return path;
        });
    });
  }

  // Short-lived links for a set of paths. Resolves to { path: url }.
  // Missing or refused photos are simply absent from the result.
  function links(paths) {
    paths = (paths || []).filter(Boolean);
    if (!paths.length) return Promise.resolve({});
    return window.SC.client.storage
      .from(BUCKET)
      .createSignedUrls(paths, 3600)
      .then(function (res) {
        var out = {};
        (res.data || []).forEach(function (r) {
          if (r && r.signedUrl && !r.error) out[r.path] = r.signedUrl;
        });
        return out;
      }, function () { return {}; });
  }

  function remove(path) {
    if (!path) return Promise.resolve();
    return window.SC.client.storage.from(BUCKET).remove([path]).then(function (res) {
      if (res.error) console.warn("[Social Capital] old photo not deleted", res.error);
    });
  }

  window.SC_photo = { toJpeg: toJpeg, upload: upload, links: links, remove: remove };
})();
