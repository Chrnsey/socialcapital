-- ===========================================================================
-- TWO approve_mentor FUNCTIONS. REMOVE THE OBSOLETE ONE.
-- ===========================================================================
-- Symptom:
--   ERROR: function public.approve_mentor(uuid, text, mentor_level, text)
--          is not unique
--   ...when approving somebody from the pending queue.
--
-- Cause, and it was mine. schema.sql created approve_mentor with four
-- arguments. alumni.sql then added a fifth (the alumnus's school id) using
-- "create or replace", with a comment claiming the old command would still
-- work. It does not: create-or-replace only replaces when the argument list
-- matches EXACTLY, so that added a SECOND function beside the first.
--
-- After that, a four-argument call matches both - the five-argument version
-- has a default on its fifth - and Postgres refuses to guess.
--
-- The five-argument version is the one to keep. It carries is_alumnus,
-- alumnus_school_id, alumnus_school_name and left_school_year across to the
-- live directory; the four-argument one predates those columns and would
-- silently drop them.
-- ===========================================================================

begin;

-- Drop ONLY the obsolete four-argument version. Named explicitly rather than
-- dropped in a loop, because here the two versions are not interchangeable
-- and the wrong one surviving would lose alumni data without erroring.
drop function if exists public.approve_mentor(uuid, text, mentor_level, text);

commit;


-- ===========================================================================
-- CHECK IT
-- ===========================================================================
-- Exactly one row, with five arguments ending in "alumnus_school uuid":
--
--   select pg_get_function_identity_arguments(oid) as arguments
--     from pg_proc
--    where pronamespace = 'public'::regnamespace
--      and proname = 'approve_mentor';
--
-- Then approve your friend from the page again. Nothing else needs changing:
-- admin_approve_mentor passes four arguments and the surviving function takes
-- a fifth that defaults to null.
-- ===========================================================================
