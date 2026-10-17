-- ===========================================================================
-- YOUR MENTOR SHEET
-- ===========================================================================
-- Fill in a line per person. Run the whole file, or one line at a time -
-- running the same line twice would add them twice, so delete a line once it
-- has gone in.
--
-- BEFORE YOU RUN THIS, ONCE: run add-mentor-function.sql.
--
-- BEFORE YOU ADD ANYBODY: have their written yes. An email saying "list me"
-- is enough. You are publishing their name, job title and employer, which is
-- personal data, and some people need their employer's permission before
-- being publicly attached to a scheme.
--
-- NOBODY GOES LIVE UNTIL YOU SAY SO. Every line below stages the person
-- hidden. Look at the cards first, then publish. See the bottom of the file.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- THE ONLY VALUES THAT ARE FUSSY
-- ---------------------------------------------------------------------------
-- industry  must be exactly one of:
--             technology  healthcare  law      finance   trades
--             media       education   engineering  public_sector  other
--
-- level     must be exactly:  junior   or   senior
--
-- public_contact_kind, if you use it:  linkedin   email   other
--
-- Everything else is free text. An apostrophe in a name needs doubling:
--   'O''Brien'  not  'O'Brien'
-- ---------------------------------------------------------------------------


-- ===========================================================================
-- MENTOR 1
-- ===========================================================================
select public.add_mentor(
  full_name        => 'FULL NAME',
  role_title       => 'Job Title, Employer',
  industry         => 'technology',
  level            => 'junior',
  contact_email    => 'their@email.com',
  experience_label => '3 years in industry',
  open_to_talks    => false,
  employer         => 'Employer',
  notes            => 'Met 2026-10-00. What they agreed to.'
);

-- ===========================================================================
-- MENTOR 2
-- ===========================================================================
select public.add_mentor(
  full_name        => 'FULL NAME',
  role_title       => 'Job Title, Employer',
  industry         => 'other',
  level            => 'senior',
  contact_email    => 'their@email.com',
  experience_label => '',
  open_to_talks    => false,
  employer         => '',
  notes            => ''
);

-- ===========================================================================
-- MENTOR 3
-- ===========================================================================
select public.add_mentor(
  full_name        => 'FULL NAME',
  role_title       => 'Job Title, Employer',
  industry         => 'other',
  level            => 'junior',
  contact_email    => 'their@email.com',
  experience_label => '',
  open_to_talks    => false,
  employer         => '',
  notes            => ''
);

-- ===========================================================================
-- MENTOR 4
-- ===========================================================================
select public.add_mentor(
  full_name        => 'FULL NAME',
  role_title       => 'Job Title, Employer',
  industry         => 'other',
  level            => 'junior',
  contact_email    => 'their@email.com',
  experience_label => '',
  open_to_talks    => false,
  employer         => '',
  notes            => ''
);

-- ===========================================================================
-- MENTOR 5
-- ===========================================================================
select public.add_mentor(
  full_name        => 'FULL NAME',
  role_title       => 'Job Title, Employer',
  industry         => 'other',
  level            => 'junior',
  contact_email    => 'their@email.com',
  experience_label => '',
  open_to_talks    => false,
  employer         => '',
  notes            => ''
);


-- ---------------------------------------------------------------------------
-- SOMEBODY WHO WENT TO A DEIS SCHOOL THEMSELVES
-- ---------------------------------------------------------------------------
-- Worth flagging, because their card then reads differently to a student from
-- that school. Add alumni_contact_ok and a public_contact only if they have
-- actually agreed that over-18s may contact them directly.
-- ---------------------------------------------------------------------------
-- select public.add_mentor(
--   full_name           => 'FULL NAME',
--   role_title          => 'Job Title, Employer',
--   industry            => 'law',
--   level               => 'junior',
--   contact_email       => 'their@email.com',
--   experience_label    => '4 years qualified',
--   open_to_talks       => true,
--   is_alumnus          => true,
--   alumnus_school_name => 'Their school',
--   alumni_contact_ok   => true,
--   public_contact      => 'https://www.linkedin.com/in/them',
--   public_contact_kind => 'linkedin',
--   employer            => 'Employer',
--   notes               => 'Met 2026-10-00. Agreed to direct contact from over-18s.'
-- );


-- ===========================================================================
-- AFTERWARDS
-- ===========================================================================

-- 1. See everybody, published or not:
--      select full_name, role_title, industry, level, is_published
--        from public.mentors order by is_published, industry, full_name;

-- 2. Check their private record went in too:
--      select m.full_name, c.email, c.company, c.notes
--        from public.mentors m
--        join public.mentor_contacts c on c.mentor_id = m.id
--       order by m.full_name;

-- 3. Publish one person:
--      update public.mentors set is_published = true
--       where full_name = 'FULL NAME';

-- 4. Publish everybody at once, when you are happy:
--      update public.mentors set is_published = true where is_published = false;

-- 5. Hide somebody again - never delete, they may come back:
--      update public.mentors set is_published = false
--       where full_name = 'FULL NAME';

-- 6. Link an alumnus to a school that has registered, so their card says
--    "went to your school" to that school's students:
--      update public.mentors
--         set alumnus_school_id = (select id from public.schools
--                                   where school_name = 'St Mary''s CBS')
--       where full_name = 'FULL NAME';

-- 7. What a school sees on the sector cards:
--      select industry, count(*) from public.mentors
--       where is_published group by 1 order by 2 desc;

-- 8. Added somebody twice by mistake:
--      delete from public.mentors where full_name = 'FULL NAME';
--    Their private contact record goes with them automatically.
-- ===========================================================================
