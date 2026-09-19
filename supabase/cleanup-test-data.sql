-- ===========================================================================
-- REMOVE THE TEST DATA
-- Run this in the Supabase SQL Editor once you're happy everything works.
--
-- Note: this deliberately does NOT delete your own school row - that is what
-- lets you sign in. It renames it instead, so you keep access to the
-- directory for checking things.
-- ===========================================================================

-- 1. Remove the three placeholder mentors.
--    (Their private contact rows are removed automatically alongside them.)
delete from public.mentors where full_name like 'ZZ TEST%';

-- 2. Remove the test registration submissions.
delete from public.pending_schools where school_name like 'ZZ %';

-- 3. Keep your own access, but give it a sensible name.
update public.schools
   set school_name  = 'Social Capital (admin)',
       contact_name = 'Jack'
 where school_name like 'ZZ TEST%';

-- 4. Show what's left, so you can see the result.
select 'schools'         as table_name, count(*) from public.schools
union all
select 'mentors',                       count(*) from public.mentors
union all
select 'pending_schools',               count(*) from public.pending_schools
union all
select 'pending_mentors',               count(*) from public.pending_mentors;
