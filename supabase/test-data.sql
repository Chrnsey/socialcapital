-- ===========================================================================
-- TEMPORARY TEST DATA
-- Lets you check the login and directory work before any real data exists.
-- Everything here is named "ZZ TEST" so it is obvious and easy to remove.
--
-- BEFORE RUNNING: replace YOUR-EMAIL-HERE below with the email address you
-- want to sign in with. That is the only edit needed.
-- ===========================================================================

-- 1. Approve yourself as a school, so you can get past the gate.
insert into public.schools (school_name, contact_name, email, county)
values ('ZZ TEST School', 'Jack', lower('YOUR-EMAIL-HERE'), 'Dublin')
on conflict (lower(email)) do update set is_active = true;

-- 2. A few placeholder mentors so the directory isn't empty.
--    Deliberately named so they could never be mistaken for real people.
insert into public.mentors
  (full_name, role_title, industry, level, experience_label, open_to_talks)
values
  ('ZZ TEST Mentor One',   'Test role - delete me', 'technology', 'junior', '3 years in industry',  true),
  ('ZZ TEST Mentor Two',   'Test role - delete me', 'technology', 'senior', '15 years in industry', false),
  ('ZZ TEST Mentor Three', 'Test role - delete me', 'trades',     'senior', '16 years in trade',    true);


-- ===========================================================================
-- CLEAN UP — run these four lines once you're happy everything works.
-- (Remove the -- from the start of each line first.)
-- ===========================================================================
-- delete from public.mentors        where full_name   like 'ZZ TEST%';
-- delete from public.schools        where school_name like 'ZZ TEST%';
-- delete from public.pending_schools where school_name like 'ZZ %';
