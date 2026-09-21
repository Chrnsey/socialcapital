-- ===========================================================================
-- ALUMNI: let mentors say which school they went to
-- ===========================================================================
-- Why this matters: "I went to your school" carries more weight with a
-- student than any job title. It is also the easiest mentor to recruit,
-- because they have a reason to say yes.
--
-- Run this in the SQL Editor. Safe to run more than once.
-- ===========================================================================

-- 1. On the public profile.
alter table public.mentors
  add column if not exists is_alumnus boolean not null default false,
  add column if not exists alumnus_school_id uuid references public.schools(id),
  add column if not exists alumnus_school_name text,
  add column if not exists left_school_year int;

comment on column public.mentors.is_alumnus is
  'Went to a DEIS school themselves.';
comment on column public.mentors.alumnus_school_id is
  'Set only when their school is registered with us, so we can show "mentors from your school".';
comment on column public.mentors.alumnus_school_name is
  'What they typed. Kept even when the school is not registered.';

create index if not exists mentors_alumnus_school_idx
  on public.mentors (alumnus_school_id) where is_published;

-- 2. On the signup form submissions.
alter table public.pending_mentors
  add column if not exists is_alumnus boolean not null default false,
  add column if not exists alumnus_school_name text,
  add column if not exists left_school_year int;


-- 3. Teach approve_mentor about it.
--    Same first four arguments as before, so your old command still works.
create or replace function public.approve_mentor(
  pending_id       uuid,
  role_title       text,
  level            mentor_level,
  experience_label text default null,
  alumnus_school   uuid default null   -- optional: id from the schools table
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.pending_mentors%rowtype;
  new_id uuid;
begin
  select * into p from public.pending_mentors where id = pending_id;
  if not found then
    raise exception 'No pending mentor with id %', pending_id;
  end if;

  insert into public.mentors
    (full_name, role_title, industry, level, experience_label, open_to_talks,
     is_alumnus, alumnus_school_id, alumnus_school_name, left_school_year)
  values
    (p.full_name, role_title, coalesce(p.industry, 'other'), level,
     experience_label, coalesce(p.open_to_talks ilike 'yes%', false),
     p.is_alumnus, alumnus_school, p.alumnus_school_name, p.left_school_year)
  returning id into new_id;

  insert into public.mentor_contacts (mentor_id, email, company)
  values (new_id, lower(p.email), p.company);

  update public.pending_mentors set status = 'approved' where id = pending_id;
  return new_id;
end;
$$;

revoke all on function public.approve_mentor(uuid, text, mentor_level, text, uuid)
  from public, anon, authenticated;


-- ===========================================================================
-- HOW TO USE IT
-- ===========================================================================
-- A mentor who went to a school that is registered with us. Get the school's
-- id from the schools table first, then pass it as the fifth argument:
--
--   select public.approve_mentor(
--     'pending-mentor-id',
--     'Software Engineer, Dublin',
--     'junior',
--     '3 years in industry',
--     'the-school-id-from-the-schools-table'
--   );
--
-- A mentor whose old school is not registered with us - leave it off. Their
-- school name is still recorded, so it links up if that school joins later:
--
--   select public.approve_mentor('pending-mentor-id', 'Electrician', 'senior', '16 years in trade');
--
-- To link them up later:
--
--   update public.mentors
--      set alumnus_school_id = (select id from schools where school_name = 'St Mary''s CBS')
--    where full_name = 'Their Name';
-- ===========================================================================
