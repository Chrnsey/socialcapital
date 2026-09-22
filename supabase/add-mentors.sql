-- ===========================================================================
-- ADDING MENTORS BY HAND
-- ===========================================================================
-- Use this once you have people who have said yes. Duplicate the block below
-- for each one, fill in the details, and run the whole thing.
--
-- This is for mentors you recruited directly, where there is no form
-- submission to approve. If somebody used the signup form instead, use
-- approve_mentor() from CHEATSHEET.md - it is less typing.
--
-- Everything inserts in one transaction, so if one row is wrong, none of
-- them land and you can fix it and re-run without creating duplicates.
-- ===========================================================================

begin;

-- ---------------------------------------------------------------------------
-- ONE MENTOR. Copy this whole block for each additional person.
-- ---------------------------------------------------------------------------
with new_mentor as (
  insert into public.mentors (
    full_name,
    role_title,           -- exactly as it should read on the card
    industry,             -- technology healthcare law finance trades
                          -- media education engineering public_sector other
    level,                -- 'junior' or 'senior' only
    experience_label,     -- the small grey line, e.g. '3 years in industry'
    open_to_talks,        -- will they come into a school?
    is_alumnus,           -- did they go to a DEIS school themselves?
    alumnus_school_name,  -- which one (free text, or NULL)
    alumni_contact_ok,    -- may over-18s contact them directly?
    public_contact,       -- what to share - usually a LinkedIn URL. NULL if not.
    public_contact_kind,  -- 'linkedin' 'email' or 'other'
    is_published          -- false to stage them without going live
  )
  values (
    'Full Name',
    'Job Title, Employer',
    'technology',
    'junior',
    '3 years in industry',
    true,
    false,
    null,
    false,
    null,
    null,
    true
  )
  returning id
)
insert into public.mentor_contacts (mentor_id, email, phone, company, notes)
select id,
       'their@email.com',   -- private. Never shown on the website.
       null,                -- phone, if you have it
       'Employer',
       'Met 2026-09-22. Happy to do one talk a year.'   -- your vetting record
  from new_mentor;

-- ---------------------------------------------------------------------------
-- Paste more blocks above this line, then:
-- ---------------------------------------------------------------------------

commit;


-- ===========================================================================
-- AFTERWARDS
-- ===========================================================================
-- See what's live:
--   select full_name, role_title, industry, level, is_published from mentors
--    order by industry, full_name;
--
-- Link a mentor to a registered school so their profile shows
-- "Went to your school" to that school's students:
--   update mentors
--      set alumnus_school_id = (select id from schools where school_name = 'St Mary''s CBS')
--    where full_name = 'Full Name';
--
-- Stage someone without publishing, then release them later:
--   update mentors set is_published = false where full_name = 'Full Name';
--   update mentors set is_published = true  where full_name = 'Full Name';
--
-- Counts per sector, which is what a school sees on the industry cards:
--   select industry, count(*) from mentors where is_published group by 1 order by 2 desc;
-- ===========================================================================
