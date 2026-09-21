// ===========================================================================
// Step two: GitHub sends the user back here with a short-lived code. We swap
// it for an access token and hand that to the CMS window that opened us.
// ===========================================================================
function page(message) {
  // The CMS listens for a postMessage from this popup. It first says hello
  // ("authorizing:github"), then we reply with the token.
  return new Response(
    `<!DOCTYPE html><html><head><meta charset="utf-8"><title>Signing in…</title></head>
<body><p style="font-family:system-ui;padding:2rem">Signing you in…</p>
<script>
(function () {
  var payload = ${JSON.stringify(message)};
  function send(e) {
    if (!window.opener) return;
    window.opener.postMessage(payload, e && e.origin ? e.origin : "*");
  }
  window.addEventListener("message", send, false);
  if (window.opener) {
    window.opener.postMessage("authorizing:github", "*");
  } else {
    document.body.innerHTML =
      "<p style='font-family:system-ui;padding:2rem'>Open the CMS at /admin/ and sign in from there.</p>";
  }
})();
</script></body></html>`,
    { headers: { "content-type": "text/html; charset=utf-8", "Cache-Control": "no-store" } }
  );
}

function failure(reason) {
  return page("authorization:github:error:" + JSON.stringify({ message: reason }));
}

export async function onRequest(context) {
  const { request, env } = context;
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");

  if (!code) return failure("GitHub did not send a code back.");

  // Check the state matches the cookie we set on the way out.
  const cookies = request.headers.get("Cookie") || "";
  const expected = (cookies.match(/(?:^|;\s*)cms_oauth_state=([^;]+)/) || [])[1];
  if (!expected || expected !== state) {
    return failure("Sign-in request could not be verified. Please try again.");
  }

  if (!env.GITHUB_CLIENT_ID || !env.GITHUB_CLIENT_SECRET) {
    return failure("GitHub credentials are not configured on the server.");
  }

  let token;
  try {
    const res = await fetch("https://github.com/login/oauth/access_token", {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({
        client_id: env.GITHUB_CLIENT_ID,
        client_secret: env.GITHUB_CLIENT_SECRET,
        code: code,
        redirect_uri: `${url.origin}/oauth/callback`
      })
    });
    const data = await res.json();
    if (data.error || !data.access_token) {
      return failure(data.error_description || data.error || "GitHub refused the sign-in.");
    }
    token = data.access_token;
  } catch (e) {
    return failure("Could not reach GitHub. Try again in a moment.");
  }

  return page(
    "authorization:github:success:" +
      JSON.stringify({ token: token, provider: "github" })
  );
}
