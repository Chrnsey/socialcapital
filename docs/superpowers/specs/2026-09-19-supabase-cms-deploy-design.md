# Social Capital Ireland — making the demo real

Date: 2026-09-19
Status: approved

## Goal

Turn four self-contained demo HTML files into a working platform: real form
submissions, real gated login, a real mentor directory, editable site text,
and automatic deploys.

## Decisions taken

1. **CMS without a build step.** Editable text is extracted into `content/*.json`.
   Each page fetches its JSON on load and fills itself in. The four HTML files
   stay standalone. Decap CMS edits the JSON via a GitHub backend.
2. **Approvals happen by hand** in the Supabase dashboard, assisted by two SQL
   helper functions. No admin UI is built.
3. **Mentor contact details are split into a separate table** that no browser
   session can read, matching the site's own promise that contact stays on the
   platform.
4. **No speaker-booking feature.** Directory copy points at a mailto link.
5. **No fabricated people anywhere public.** Homepage teasers become
   role-archetype recruitment cards; the invented pull-quote on mentors.html
   becomes a founder statement.

## Data model

| Table | Purpose | Who can read it from the website |
|---|---|---|
| `pending_schools` | school registration submissions | nobody |
| `pending_mentors` | mentor signups, both sources | nobody |
| `schools` | approved schools; the access gate | only your own row |
| `mentors` | public-ish directory profile | approved schools only |
| `mentor_contacts` | mentor email/phone/company | nobody |

All five are writable only as specified; everything else is reachable solely
via the Supabase dashboard (service role).

## The access gate

Supabase magic-link auth will issue a session to any email that requests one.
That cannot be prevented and is not the security boundary.

The boundary is a row-level-security policy on `mentors` requiring that the
caller's JWT email exists in `schools` with `is_active = true`, evaluated
server-side via a `security definer` function `is_approved_school()`. The
function exists so the policy can consult `schools` without granting the caller
read access to it.

An unapproved signed-in user therefore sees zero mentors. A UI check calls the
same function and shows a clear message plus sign-out, as a courtesy only.

Consequence: one approved email = one login. Two counsellors at one school =
two rows sharing a school name.

## Key handling

`js/config.js` holds the Supabase project URL and the **anon/public** key, is
committed, and ships to every visitor. This is correct: the anon key is an
identifier, not a credential, and RLS is what protects the data. The
`service_role` key must never appear in this repository.

## Spam control

Anon-insertable tables carry length constraints. Each public form carries a
hidden honeypot field; submissions with it filled are dropped client-side.

## Out of scope

- Speaker booking / scheduling
- Admin approval UI
- Multi-user school accounts
- Student-facing accounts
