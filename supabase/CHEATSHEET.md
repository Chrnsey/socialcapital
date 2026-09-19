# The only SQL you actually need

Everything runs in the same place:
**Supabase dashboard → SQL Editor → New query → paste → Run**

---

## Setup files — run once, then forget

| File | Status |
|---|---|
| `schema.sql` | ✅ **Done.** Built your database. Never run again. |
| `notifications.sql` | ⬅️ **Run this one.** Emails you when someone submits. |
| `test-data.sql` | ✅ Done. Was only for testing. |
| `cleanup-test-data.sql` | ⬜ Run whenever. Deletes the `ZZ TEST` rows. |

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

That's the lot. Anything else, ask.
