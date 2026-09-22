-- ===========================================================================
-- FIX: alumni-contact.sql did not actually hide the contact column
-- ===========================================================================
-- In Postgres, revoking ONE column does nothing while the WHOLE table is
-- still granted - and Supabase grants every table to signed-in users by
-- default. So the previous revoke was silently a no-op.
--
-- The fix: take the whole table away, then grant back every column EXCEPT
-- the two contact fields. Anything not on this list is refused.
--
-- If a column is ever added to mentors, it is NOT visible until added here.
-- That is deliberate: a new column fails closed rather than leaking.
--
-- Safe to run more than once.
-- ===========================================================================

revoke select on public.mentors from anon, authenticated;

grant select (
  id,
  created_at,
  full_name,
  role_title,
  industry,
  level,
  experience_label,
  open_to_talks,
  is_published,
  is_alumnus,
  alumnus_school_id,
  alumnus_school_name,
  left_school_year,
  alumni_contact_ok
  -- deliberately NOT: public_contact, public_contact_kind
) on public.mentors to authenticated;

-- mentor_contact() and approve_mentor() run as the database owner, so they
-- are unaffected by these grants and still work.
