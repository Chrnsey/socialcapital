# Social Capital Ireland

Connects students and past pupils of DEIS schools to volunteer professionals
who agreed to answer questions about their job and how they got it. Founding
line: *your network is your net worth*. Jack is the sole founder, a
non-developer, and builds this in his spare time. A Company Limited by
Guarantee, charitable status pending.

Live at socialcapital.ie. Repo is **public**, so nothing secret goes in it.

## Stack

Static HTML + vanilla JS, no framework. Supabase (Postgres, RLS, Auth).
Decap CMS at `/admin`. Cloudflare Pages. Resend for email. `node build.mjs`
runs as the Cloudflare build command.

## Rules that are not obvious from the code

- **Never invent people.** No fabricated mentors, quotes or testimonials. The
  original demo had fake mentors attributed to real employers; that was
  removed and must not come back. An empty directory beats a fictional one.
- **Don't rewrite Jack's copy.** He found earlier drafts inauthentic and now
  writes it himself. Build structure, let him fill it. Fixing copy that is
  factually wrong (describing a removed feature) is a correction, not a
  rewrite — do that, and say so. Voice notes are in the memory file
  `social-capital-writing-voice`. After a typo fix in one of his lines, add
  the commit hash to `.git-blame-ignore-revs` so `check-voice.mjs` still
  credits the line to him.
- **Never label students by school type.** DEIS appears on schools.html,
  businesses.html and privacy.md only. Never on student-facing pages.
- **DEIS gating is the point, not a gap.** Access requires affiliation with a
  registered school. Don't propose opening it up.
- **Jack verifies nothing.** Schools vouch for their own people. Keep it that
  way; it is what keeps the data footprint small.

## Where things live

| | |
|---|---|
| Copy | `content/*.json` (per-page fields), `content/pages/*.md` (About, Terms, Privacy, Safeguarding) |
| Styles | `css/site.css` — one file, tokens in the `:root` block at the top |
| Nav and footer | `partials/` — the only copies, injected by build.mjs |
| Database | `supabase/*.sql`, run by hand in the Supabase SQL editor |
| Guides | generated into `routes/`, `funding/`, `careers/` from `guide.html` |

Detail: `README.md`, `EDITING.md` (Jack's CMS guide), `LAUNCH.md` (the
sequenced plan and what is verified), `docs/CLG-SETUP.md`.

## Gotchas that have each cost real time

1. **build.mjs overwrites HTML.** It refreshes fallback text from JSON,
   rebuilds the markdown documents, regenerates the guide pages and stamps
   `?v=<hash>` on assets. Generated files carry a DO NOT EDIT banner. Never
   hand-edit one.
2. **The Supabase SQL editor does not honour `begin`/`commit`** the way psql
   does — a failed migration can leave earlier statements applied. Write
   migrations to be **re-runnable**, not merely transactional.
3. **`create or replace function` with a different argument list creates a
   second function**, it does not replace the first. Drop old versions by oid
   first. This broke `add_mentor` and `approve_mentor`.
4. **`select` on `mentors` is granted column by column.** A new column is
   unreadable by schools until it is named in a `grant select (col)`. Fails
   silently as nulls.
5. **RLS policies depend on gate functions.** Dropping `is_approved_*` needs
   the policy dropped and recreated. Never `cascade` — that drops the policy
   without replacing it and the directory reads as empty with no error.
6. **Cloudflare ignores `Cache-Control` from `_headers`** for static files.
   Asset freshness comes from the `?v=` fingerprints, not from headers.

## How to check your work

- `node build.mjs` then confirm it builds twice with no change but the stamp
- `supabase/test-the-gate.sql` — proves a signed-in school cannot read mentor
  contact details, the signup queue, or publish. Re-run after any change to
  the admin functions
- Tag-balance the HTML after any structural edit
- `curl -s https://socialcapital.ie/ | grep built-by-build.mjs` — proves the
  deploy ran

## What is actually blocking the project

Not the code. In order: the guide pages are live and **nobody has
fact-checked them**; no second and third director, which blocks the CLG,
which blocks charitable status, which blocks funding; the Child Safeguarding
Statement is drafted but unadopted; and there is one mentor in the directory.

## Open design work

Colour and "punch" across the pages (awaiting Jack's call: second accent
colour, or push the green harder), sector icons from an open set, and a
metro-map diagram of the routes. Mentor rotation and auto-pause are designed
and logged for but deliberately not built — there is nothing to tune yet.
