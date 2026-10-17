-- ===========================================================================
-- WHO CAN GET INTO /admin-mentors
-- ===========================================================================

-- 1. See the list. If this errors with "relation does not exist", you have
--    not run admin-page.sql yet - that is the whole problem.
select email, full_name, is_active, created_at
  from public.admins
 order by created_at;

-- 2. Add another address - your own Gmail, say, if that is what you actually
--    sign in with. Run on its own.
--      insert into public.admins (email, full_name)
--      values ('you@example.com', 'Your name')
--      on conflict (email) do update set is_active = true;

-- 3. Take access away without losing the record:
--      update public.admins set is_active = false
--       where email = 'them@example.com';

-- 4. Sanity check: does the address you are signing in with match? Case does
--    not matter - the gate lowercases both sides - but a typo does.
