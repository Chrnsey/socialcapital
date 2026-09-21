# Moving from Netlify to Cloudflare Pages

Everything static moves with no effort. The only awkward part is the CMS
login, which currently goes through Netlify. That is already built and waiting
in `functions/oauth/` — it just needs switching on at the right moment.

**Do not point socialcapital.ie at Cloudflare until step 5 passes.** The site
stays up on Netlify the whole time.

---

## Before you start

Check what actually ran out on Netlify. A site with no build step uses seconds
of build time per deploy. If it says build minutes, something is misconfigured
and this migration may be unnecessary. If it is bandwidth, it is real.

---

## 1. Create the Pages project

1. **dash.cloudflare.com** → sign up or log in
2. **Workers & Pages** → **Create** → **Pages** → **Connect to Git**
3. Authorise GitHub, pick **Chrnsey/socialcapital**
4. Build settings:
   - **Framework preset:** None
   - **Build command:** leave empty
   - **Build output directory:** `/`
   - **Production branch:** `main`
5. **Save and Deploy**

You get a URL like `socialcapital.pages.dev`.

---

## 2. Add the GitHub OAuth credentials

The CMS sign-in needs these. They are secrets and belong here, never in the
repository.

1. **github.com/settings/developers** → **OAuth Apps** → **New OAuth App**
   - Application name: `Social Capital CMS (Cloudflare)`
   - Homepage URL: `https://socialcapital.ie`
   - Authorization callback URL: `https://socialcapital.ie/oauth/callback`
2. Register it, copy the **Client ID**, generate a **Client Secret**
3. In Cloudflare: your Pages project → **Settings** → **Environment variables**
   → add both, for **Production**:
   - `GITHUB_CLIENT_ID`
   - `GITHUB_CLIENT_SECRET`
4. Redeploy so the variables take effect

> Keep the existing Netlify OAuth app alone until the move is finished. Two
> apps can coexist; you are not breaking the old one.

---

## 3. Test on the pages.dev URL

Before touching DNS, check on `socialcapital.pages.dev`:

- [ ] Homepage loads and looks right
- [ ] `/guides.html` shows all three groups
- [ ] `/routes/plc` loads — **this is the important one.** It proves the clean
      URLs work, which rely on `_redirects`
- [ ] `/funding/hear` loads
- [ ] `/pathways/electrician` redirects to `/careers/electrician`
- [ ] A form submits and you get the alert email
- [ ] School login sends a link

For the login to work on that URL you will need to add
`https://socialcapital.pages.dev/**` to Supabase's redirect list temporarily.

---

## 4. Point the domain

1. Cloudflare Pages project → **Custom domains** → **Set up a domain** →
   `socialcapital.ie`
2. Cloudflare tells you what DNS record to create. Add it at **Blacknight**,
   replacing the `A` record currently pointing at `75.2.60.5`
3. Add `www.socialcapital.ie` the same way, replacing the existing CNAME

⚠️ Do not change your nameservers away from Blacknight unless Cloudflare
insists. Your MX records for email live there, and moving DNS badly is the one
step in this whole project that could take your email down.

---

## 5. Switch the CMS over

1. In `admin/config.yml`, uncomment these two lines:
   ```
   base_url: https://socialcapital.ie
   auth_endpoint: oauth/auth
   ```
2. Push
3. Go to `https://socialcapital.ie/admin/` and sign in with GitHub

If it fails, the likely causes in order: the environment variables are not set
or the project was not redeployed after adding them; the callback URL in the
GitHub app does not exactly match `https://socialcapital.ie/oauth/callback`;
or popups are blocked.

---

## 6. Tidy up

- [ ] Update Supabase **Site URL** and redirect list if anything changed
- [ ] Remove the temporary `pages.dev` entry from Supabase
- [ ] Delete `netlify.toml` once you are confident (it is ignored by Cloudflare,
      so there is no rush)
- [ ] Turn off the old Netlify site, or leave it as a fallback

---

## What each file does

| File | Purpose |
|---|---|
| `_redirects` | Clean URLs and old-link redirects. Cloudflare's version of netlify.toml |
| `_headers` | Security headers, and noindex on /admin |
| `_routes.json` | Keeps the OAuth function from shadowing the static site |
| `functions/oauth/auth.js` | Sends you to GitHub to sign in |
| `functions/oauth/callback.js` | Swaps GitHub's code for a token, hands it to the CMS |
| `404.html` | Shown for anything missing |
