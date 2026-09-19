# Social Capital Ireland — how this site works

A plain-language guide to running the site. Written for someone who isn't a
developer. Nothing here needs you to write code.

---

## What the files are

| Folder / file | What it is |
|---|---|
| `index.html` etc. | The four web pages. The design lives inside these. |
| `content/*.json` | **The words on the pages.** This is what the CMS edits. |
| `js/` | The code that makes forms, login and the directory work. |
| `js/config.js` | Your Supabase keys. |
| `supabase/schema.sql` | The database setup. Already run — you shouldn't need it again. |
| `supabase/test-data.sql` | Temporary test entries. Delete them once you're happy. |
| `admin/` | The CMS you log into to edit text. |
| `docs/` | Design notes. Not part of the public site. |

---

## Looking at the site on your own computer

```bash
cd /Users/jack/Downloads/SocialCapital && python3 -m http.server 8765
```

Then open <http://localhost:8765>. Press `Ctrl+C` in the terminal to stop it.

You need this running for the site to work properly on your machine — opening
the HTML files by double-clicking mostly works, but the editable text and the
login won't.

---

## Setup checklist

- [x] **Supabase** — project created, database set up
- [ ] **GitHub** — account + a repository named `socialcapital`
- [ ] **Netlify** — connected to that repository
- [ ] **Decap CMS** — GitHub login enabled so you can edit text
- [ ] **Email sending** — proper email provider (see warning below)

---

## ⚠️ The one thing that will break your launch

Supabase sends your sign-in emails using a **shared testing address**. It is
limited to a handful of emails per hour and very often lands in spam.

It is fine for testing. It is **not** fine for real guidance counsellors — they
will simply never receive their sign-in link, and you will have no way of
knowing.

Before you tell a single school about the site, set up a real email sender
(Resend has a free tier that's more than enough) and plug it into
**Supabase → Project Settings → Authentication → SMTP Settings**. This needs
you to add a few DNS records to socialcapital.ie to prove you own it.

---

## Day-to-day: approving a school

1. Supabase dashboard → **Table Editor** → `pending_schools`
2. Read the new entry. Check the school is really a DEIS school and the email
   looks like it belongs to them.
3. Copy its `id` (the long code in the first column).
4. Go to **SQL Editor** and run:

```sql
select public.approve_school('paste-the-id-here');
```

That's it. They can now sign in with that email address.

**To remove a school's access later**, set `is_active` to false on their row in
the `schools` table. Don't delete the row — keeping it means you have a record.

---

## Day-to-day: approving a mentor

Same idea, but you add a couple of details the signup form doesn't collect —
their job title as you want it displayed, and whether they count as junior or
senior.

1. **Table Editor** → `pending_mentors`, copy the `id`
2. **SQL Editor**:

```sql
select public.approve_mentor(
  'paste-the-id-here',
  'Software Engineer, Google Dublin',   -- job title, exactly as it should appear
  'junior',                             -- 'junior' or 'senior', nothing else
  '3 years in industry'                 -- the small grey line on their card
);
```

This puts their public profile in `mentors` and files their email away
privately in `mentor_contacts`.

**To hide a mentor without deleting them**, untick `is_published` on their row.

---

## Day-to-day: editing the words on the site

Go to `https://your-site-address/admin/` and sign in with GitHub.

You can edit every heading and paragraph on all four pages, the three homepage
cards, and the industry descriptions shown in the directory. Save, and the
site updates itself within a minute or two.

**One rule:** in the industry descriptions, don't change the "internal code"
field (`technology`, `trades`, etc.). That's what links a sector to its
mentors. The "name shown on screen" field next to it is the one to edit.

---

## Rules that keep this safe

**Never share the `service_role` / `sb_secret_` key.** It's on the same
Supabase page as the key already in `js/config.js`. That one ignores every
security rule in the database — anyone holding it can read every school's
details, every mentor's email, and delete the lot. It must never go into any
file here, any email, or any chat.

**The key that IS in `js/config.js` is fine.** It's the publishable key. It's
designed to be public and is sent to every visitor's browser. The database's
own rules are what protect your data, not that key.

**Mentor emails and phone numbers are in `mentor_contacts`,** which nothing on
the website can read — not even a logged-in school. This is deliberate: it
backs up the promise on your own pages that students never get a mentor's
personal contact details. You make the introductions yourself.

---

## If something goes wrong

**A form says "isn't connected yet"** — the keys in `js/config.js` are missing
or wrong.

**Sign-in emails never arrive** — check spam first, then read the warning above.
This is the most likely problem you'll hit.

**Someone approved can't get in** — check their row in `schools`: is the email
spelled exactly right, and is `is_active` ticked?

**The directory is empty** — that's correct until you've approved mentors.

**The site looks right but text changes don't show** — the CMS saves to GitHub,
and Netlify then rebuilds. Give it two minutes.
