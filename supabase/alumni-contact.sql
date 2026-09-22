-- ===========================================================================
-- CLOSING A GAP: make sure only alumni can read a mentor's shared contact
-- ===========================================================================
-- The previous file let alumni read the mentors table, which includes the
-- public_contact column. But signed-in SCHOOLS can read that table too - so
-- a guidance counsellor could have read the contact detail, which is not what
-- we promised the mentor.
--
-- This removes that column from everyone's reach and hands it out only
-- through a function that checks you are a verified alumnus.
--
-- Run after alumni-network.sql. Safe to run more than once.
-- ===========================================================================

-- 1. Nobody signed in can select this column directly any more.
revoke select (public_contact, public_contact_kind)
  on public.mentors from anon, authenticated;

-- 2. The only way to get it: ask, and be an alumnus.
create or replace function public.mentor_contact(p_mentor uuid)
returns table (contact text, kind text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_approved_alumnus() then
    return;               -- no rows, no error, nothing leaked
  end if;

  return query
    select m.public_contact, m.public_contact_kind
      from public.mentors m
     where m.id = p_mentor
       and m.is_published
       and m.alumni_contact_ok
       and m.public_contact is not null;
end;
$$;

revoke all on function public.mentor_contact(uuid) from public, anon;
grant execute on function public.mentor_contact(uuid) to authenticated;

-- 3. The directory needs mentor ids to be able to ask. Harmless on its own.
--    (Already selectable - this is just a note that it is deliberate.)


-- ===========================================================================
-- Worth testing after you run this, in the SQL editor:
--
--   -- should fail, which is the point:
--   set role authenticated;
--   select public_contact from public.mentors limit 1;
--   reset role;
-- ===========================================================================
