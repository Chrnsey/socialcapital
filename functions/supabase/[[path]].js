// Working notes aren't part of the public site. _redirects can't return a
// 404 status on Cloudflare Pages, so this does.
export function onRequest() {
  return new Response("Not found", {
    status: 404,
    headers: { "content-type": "text/plain", "X-Robots-Tag": "noindex" }
  });
}
