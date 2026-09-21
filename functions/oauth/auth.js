// ===========================================================================
// Step one of signing into the CMS: send the user to GitHub.
//
// This replaces the service Netlify was providing. It runs on Cloudflare's
// network, not in the browser, because exchanging a GitHub code for a token
// needs a secret that must never reach a visitor.
//
// Needs two environment variables set in the Cloudflare dashboard:
//   GITHUB_CLIENT_ID
//   GITHUB_CLIENT_SECRET
// ===========================================================================
export function onRequest(context) {
  const { request, env } = context;
  const url = new URL(request.url);

  if (!env.GITHUB_CLIENT_ID) {
    return new Response(
      "GITHUB_CLIENT_ID is not set. Add it in Cloudflare: your Pages project " +
      "→ Settings → Environment variables.",
      { status: 500, headers: { "content-type": "text/plain" } }
    );
  }

  // Random value echoed back by GitHub, so we can tell a real callback from
  // someone else's forged one.
  const state = crypto.randomUUID();

  const authorize = new URL("https://github.com/login/oauth/authorize");
  authorize.searchParams.set("client_id", env.GITHUB_CLIENT_ID);
  authorize.searchParams.set("redirect_uri", `${url.origin}/oauth/callback`);
  authorize.searchParams.set("scope", "repo,user");
  authorize.searchParams.set("state", state);

  return new Response(null, {
    status: 302,
    headers: {
      Location: authorize.toString(),
      "Set-Cookie": `cms_oauth_state=${state}; Path=/oauth; HttpOnly; Secure; SameSite=Lax; Max-Age=600`,
      "Cache-Control": "no-store"
    }
  });
}
