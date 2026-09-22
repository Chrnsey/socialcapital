# The only SQL you actually need

Everything runs in the same place:
**Supabase dashboard → SQL Editor → New query → paste → Run**

---

## Setup files — all done, never run again

| File | Status |
|---|---|
| `schema.sql` | ✅ The database |
| `notifications.sql` | ✅ Emails you on every submission |
| `alumni.sql` | ✅ Alumni columns on mentors |
| `alumni-network.sql` | ✅ School codes, alumni accounts, the 18+ gate |
| `alumni-contact.sql` | ✅ The mentor_contact() function |
| `alumni-contact-fix.sql` | ✅ Actually hides the contact column |
| `test-data.sql` / `cleanup-test-data.sql` | ✅ Finished with |

**Adding mentors you recruited yourself:** `add-mentors.sql` — one block per person.

---

## Day to day — the only three you'll ever use

### See what's waiting for you

```sql
select id, created_at, school_name, contact_name, email, county
from pending_schools where status = 'pending' order by created_at;
```

```sql
select id, created_at, full_name, email, company, industry, experience_level, source
from pending_mentors where status = 'pending' order by created_at;
```

### Approve a school

Copy its `id` from above, then:

```sql
select approve_school('paste-the-id-here');
```

They can now sign in with that email.

### Approve a mentor

```sql
select approve_mentor(
  'paste-the-id-here',
  'Software Engineer, Google Dublin',   -- job title as it should appear
  'junior',                             -- 'junior' or 'senior' only
  '3 years in industry'                 -- the small grey line on their card
);
```

Their profile goes live; their email is filed privately.

---

## Occasionally useful

**Hide a mentor without deleting them** — untick `is_published` on their row in
the Table Editor.

**Remove a school's access** — set `is_active` to false on their row in
`schools`. Don't delete it; you lose the record.

**Add a school by hand** (skipping the form):

```sql
insert into schools (school_name, contact_name, email, county)
values ('St Mary''s CBS', 'Ms Murphy', 'murphy@stmarys.ie', 'Dublin');
```

Note the doubled apostrophe in `Mary''s` — that's how SQL escapes quotes.

---

### Give a school a code for its leavers

```sql
insert into school_codes (code, school_id, notes)
select 'MARYS26', id, 'Cards for 2026 leavers'
  from schools where school_name = 'St Mary''s CBS';
```

Uppercase only. Avoid O/0 and I/1 — people type these off a card.

### Stop a code working

```sql
update school_codes set is_active = false where code = 'MARYS26';
```

### Remove someone who turned out to be under 18

```sql
delete from alumni where lower(email) = lower('their@email.com');
```

---

That's the lot. Anything else, ask.
