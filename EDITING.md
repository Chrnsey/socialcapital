# Editing the site yourself

Everything a visitor can read is now editable without code, at:

**https://socialcapital.ie/admin/**

Sign in with GitHub. Save, and the site updates itself in about 30 seconds.

---

## What's where

| In the CMS sidebar | What it controls |
|---|---|
| **Page wording → Homepage** | The front page |
| **Page wording → For schools page** | Including the founding-schools offer and its number |
| **Page wording → Become a mentor page** | Including your founder statement |
| **Page wording → Left school? page** | The alumni signup page |
| **Page wording → For businesses page** | |
| **Documents → About page** | Edited like a Word document |
| **Documents → Terms of use** | ⚠️ Legal — see below |
| **Documents → Privacy notice** | ⚠️ Legal — see below |
| **Ways in / Paying for it / Careers** | The guide pages |
| **Industry descriptions** | Blurbs schools see in the directory |

---

## Two kinds of editor

**Most pages are a set of boxes.** Each heading and paragraph has its own box. Lists — like "What a school gets" — have **Add**, delete and drag-to-reorder buttons, so you can add a sixth point or remove one.

**About, Terms and Privacy are one big text area**, like a document. A toolbar gives you headings, bold, lists and links. A few things worth knowing:

- Start a line with `>` to make a **green highlighted box**
- `## Heading` makes a section heading
- `**word**` makes it bold
- `[words](https://link)` makes a link
- A blank line between paragraphs is what makes them separate

There's a toggle between **rich text** and **markdown** at the top of that box. Rich text is easier; markdown shows you exactly what's there.

---

## Terms and Privacy — take care

These aren't just wording. **They describe what you're legally committing to.**

- **Change the date at the top** whenever you change anything
- **Privacy must match what you actually do.** If you start collecting anything new about people, it has to be added. If you stop, take it out.
- **Get a solicitor to look at anything substantial** before relying on it
- Rewording for tone is fine. Changing what's promised is not a tone edit.

---

## Things that are safe to try

**You can't break the site by editing text.** Every page keeps a copy of its last wording built in, so if a save goes wrong the page shows the old version rather than going blank. And every change is kept in history — nothing is ever truly lost.

To see what changed and when: https://github.com/Chrnsey/socialcapital/commits/main
Your own edits show up there as "Update Page wording …".

---

## Things NOT to change

- Fields labelled **"Internal code"** or **"Web address"** in the guides and industries. They link things together, and changing them breaks those links.
- Anything with `<strong>` tags in it — you can change the words between them, but leave the tags.

---

## If something looks wrong after you save

1. Wait a minute — the site takes about 30 seconds to update
2. Hard-refresh the page: **⌘ + Shift + R**
3. Still wrong? The history link above shows exactly what changed, and anything can be put back.
