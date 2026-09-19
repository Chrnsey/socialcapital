# Social Capital Ireland — the road to launch

A sequenced plan, in the order things actually need doing. Nothing here
requires code unless it says so.

---

## Where you are now

The platform works. Verified end to end on socialcapital.ie:

- [x] Site live on your own domain with SSL
- [x] School registration, mentor signup and business forms saving to the database
- [x] Passwordless school login, gated to approved schools only
- [x] Mentor directory querying real data
- [x] Mentor contact details unreadable by the website — only by you
- [x] You can edit all site text yourself at /admin/
- [x] Every change deploys automatically
- [x] Email receiving at registration@ and partnerships@
- [x] Privacy notice and consent wording

**What you do not have yet: any mentors, any schools, and the paperwork a
charity working near children needs.** That is what follows.

---

## Stage 1 — Before you contact a single school

These are the things that would be embarrassing, or worse, to be asked about
and not have.

### Legal and governance

- [ ] **Incorporate the CLG.** Register with the CRO. You need this before you
      can apply for charitable status, open a bank account, or sign anything.
- [ ] **Apply for charitable status** with the Charities Regulator. Slow —
      start early. Ask about CHY tax exemption with Revenue at the same time.
- [ ] **Add your registered name, address and company number** to the privacy
      notice and the site footer. There are marked placeholders waiting.
- [ ] **Appoint at least two other directors.** A CLG needs them, and a board
      of one is a red flag to funders.

### Child protection — this gates student access entirely

- [ ] **Write a Child Safeguarding Statement.** Required under the Children
      First Act 2015 for organisations providing services to children. Tusla
      publishes templates.
- [ ] **Do the Children First e-learning module.** Free, online, an afternoon.
- [ ] **Decide your mentor vetting process and write it down.** Garda vetting
      through the National Vetting Bureau is the standard where adults have
      contact with children. At minimum: you meet every mentor before listing
      them, and you record that you did.
- [ ] **Appoint a Designated Liaison Person** for child protection concerns.
      At your size this is you — but it must be named.

### Data protection

- [x] Privacy notice published
- [ ] **Confirm your Supabase region is in the EU** and state it in the privacy
      notice. If it is outside the EU, say so and explain the safeguards.
- [ ] **Write down your retention practice** and actually follow it — delete
      rejected registrations within twelve months.

> Why this stage comes first: a guidance counsellor is a mandated person under
> Children First. If they ask what your safeguarding arrangements are and the
> answer is "none yet", you will not get a second conversation.

---

## Stage 2 — Fill the directory

**This is the real bottleneck.** Everything else is ready; the directory is
empty. A school that logs in and finds nobody will not come back.

- [ ] **Set a target: 15–20 mentors before approaching any school.** Enough
      that two or three sectors look genuinely populated.
- [ ] **Start with people you already know.** Personal contacts convert far
      better than cold outreach, and they will tolerate a rough early version.
- [ ] **Deliberately over-recruit trades and apprenticeships.** Easy to fill
      the directory with office jobs; the routes that need no degree are the
      ones your students can least easily find out about, and the ones that
      most distinguish you from a careers website.
- [ ] **Aim for a mix of junior and senior.** Someone three years out is more
      relatable than a director, and easier to recruit.
- [ ] **Meet each one, however briefly.** It doubles as your vetting record and
      gets you a better profile write-up.
- [ ] **Approve them** into the directory (see README for the SQL command).

### A rough sector target

| Sector | First target |
|---|---|
| Trades and apprenticeships | 4 |
| Technology | 3 |
| Healthcare | 3 |
| Finance / business | 2 |
| Law | 2 |
| Media and communications | 2 |
| Public sector / education | 2 |

---

## Stage 3 — Your first school

- [ ] **Write your founder statement** on the mentors page. Still a placeholder.
- [ ] **Delete the remaining test data** (`supabase/cleanup-test-data.sql`).
- [ ] **Approach one school you have a personal connection to.** Not a cold
      list. One school that will tell you honestly what is wrong.
- [ ] **Sit with the guidance counsellor while they log in.** You will learn
      more in ten minutes than from any amount of guessing.
- [ ] **Fix what they tell you** before approaching a second school.
- [ ] Then a small handful more — five schools, not fifty.

---

## Stage 4 — Student access

Only once Stage 1's child protection items are genuinely done.

- [ ] Child Safeguarding Statement published
- [ ] Mentor vetting process operating
- [ ] Guardian consent process for under-16s decided
- [ ] **Then** the student login gets built and switched on

The technical design: schools add their own students' email addresses,
restricted to the school's own domain. Students get read-only access to the
directory. No contact details, no messaging, and the school can revoke access
at any time. Every actual conversation still goes through the school and you.

---

## Ongoing, once running

- **Check `pending_schools` and `pending_mentors` weekly.** Nothing notifies
  you yet — it is a habit, not a feature.
- **Reply to registration@ promptly.** A slow reply to a guidance counsellor in
  September costs you the whole school year.
- **Keep a note of every mentor you met and when.** This is your vetting record.

---

## Worth fixing when there is time

- **Self-host the fonts.** The site loads them from Google, which sends every
  visitor's IP address to Google. European case law has gone against this.
  It is also faster.
- **Email notifications on new submissions**, so you stop having to remember.
- **An admin approval page**, replacing the SQL commands.
- **Accessibility audit.** Some students use screen readers, and DEIS schools
  serve a higher share of students with additional needs.
- **Richer mentor profiles** — the route someone took matters far more to a
  student than their job title. Filter by route, not just sector.
