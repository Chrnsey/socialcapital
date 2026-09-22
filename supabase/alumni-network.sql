-- ===========================================================================
-- THE 18+ ALUMNI NETWORK
-- ===========================================================================
-- Former students of registered schools, who sign themselves up once they
-- turn 18, and can then contact mentors directly.
--
-- Two deliberate choices worth understanding before you run this:
--
-- 1. WE HOLD NO DATA ABOUT ANYONE UNDER 18. The school hands out a card with
--    a code. The student signs up themselves, later, as an adult. There is no
--    guardian consent to collect and no children's data to protect, because
--    there isn't any.
--
-- 2. MENTORS CHOOSE WHETHER TO BE CONTACTABLE, and what to share. Their
--    personal email stays in mentor_contacts, which nothing on the website
--    can read. What an alumnus sees is a separate field holding only what the
--    mentor consciously offered - usually a LinkedIn profile.
--
-- Run this in the SQL Editor. Safe to run more than once.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. What a mentor has agreed to share with adults
-- ---------------------------------------------------------------------------
alter table public.mentors
  add column if not exists alumni_contact_ok boolean not null default false,
  add column if not exists public_contact text,
  add column if not exists public_contact_kind text
    check (public_contact_kind is null
           or public_contact_kind in ('linkedin','email','other'));

comment on column public.mentors.alumni_contact_ok is
  'The mentor agreed that verified over-18s may contact them directly.';
comment on column public.mentors.public_contact is
  'Only what the mentor chose to share. NOT their private email - that stays in mentor_contacts.';

alter table public.pending_mentors
  add column if not exists alumni_contact_ok boolean not null default false,
  add column if not exists public_contact text,
  add column if not exists public_contact_kind text;


-- ---------------------------------------------------------------------------
-- 2. One code per school, printed on the card they hand to leavers
-- ---------------------------------------------------------------------------
create table if not exists public.school_codes (
  code        text primary key
                check (code = upper(code) and char_length(code) between 6 and 16),
  school_id   uuid not null references public.schools(id) on delete cascade,
  created_at  timestamptz not null default now(),
  is_active   boolean not null default true,
  notes       text
);

comment on table public.school_codes is
  'Give the card to sixth years as they leave, not to Transition Year. A code
   held by a leaving student is held by someone who turns 18 within months.';


-- ---------------------------------------------------------------------------
-- 3. The alumni themselves
-- ---------------------------------------------------------------------------
create table if not exists public.alumni (
  id             uuid primary key default gen_random_uuid(),
  created_at     timestamptz not null default now(),
  email          text not null,
  school_id      uuid references public.schools(id),
  used_code      text references public.school_codes(code),
  date_of_birth  date not null,
  declared_adult boolean not null default true,
  is_active      boolean not null default true,
  -- Belt and braces: the database itself refuses anyone under 18.
  constraint alumni_must_be_adult
    check (date_of_birth <= (current_date - interval '18 years'))
);

create unique index if not exists alumni_email_lower_idx
  on public.alumni (lower(email));

comment on constraint alumni_must_be_adult on public.alumni is
  'Enforced here as well as in the form, so a tampered request still fails.';


-- ---------------------------------------------------------------------------
-- 4. Signing up. Runs as the database, so it can check the code without
--    letting anyone read the list of codes.
-- ---------------------------------------------------------------------------
create or replace function public.register_alumnus(
  p_code  text,
  p_email text,
  p_dob   date
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  sc public.school_codes%rowtype;
begin
  if p_dob > (current_date - interval '18 years') then
    return 'under_18';
  end if;

  select * into sc from public.school_codes
   where code = upper(trim(p_code)) and is_active;
  if not found then
    return 'bad_code';
  end if;

  insert into public.alumni (email, school_id, used_code, date_of_birth)
  values (lower(trim(p_email)), sc.school_id, sc.code, p_dob)
  on conflict (lower(email)) do update
    set is_active = true, school_id = excluded.school_id;

  return 'ok';
end;
$$;

revoke all on function public.register_alumnus(text, text, date) from public;
grant execute on function public.register_alumnus(text, text, date) to anon, authenticated;


-- ---------------------------------------------------------------------------
-- 5. The gate, alongside the existing one for schools
-- ---------------------------------------------------------------------------
create or replace function public.is_approved_alumnus()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.alumni
    where lower(email) = lower(auth.jwt() ->> 'email')
      and is_active
  );
$$;

revoke all on function public.is_approved_alumnus() from public;
grant execute on function public.is_approved_alumnus() to authenticated;


-- ---------------------------------------------------------------------------
-- 6. Let alumni read the directory too
-- ---------------------------------------------------------------------------
alter table public.alumni enable row level security;
alter table public.school_codes enable row level security;
-- No policies on school_codes: nobody reads the code list through the site.
-- No select policy on alumni either; the function above answers yes/no.

drop policy if exists "approved schools read mentors" on public.mentors;
create policy "approved schools and alumni read mentors"
  on public.mentors for select
  to authenticated
  using (
    is_published
    and (public.is_approved_school() or public.is_approved_alumnus())
  );

-- An alumnus may read their own row, so the site can greet them.
drop policy if exists "alumnus reads own record" on public.alumni;
create policy "alumnus reads own record"
  on public.alumni for select
  to authenticated
  using (lower(email) = lower(auth.jwt() ->> 'email'));


-- ===========================================================================
-- CREATING A CODE FOR A SCHOOL
-- ===========================================================================
--   insert into public.school_codes (code, school_id, notes)
--   select 'MARYS24', id, 'Cards given to 2024 leavers'
--     from public.schools where school_name = 'St Mary''s CBS';
--
-- Codes must be UPPERCASE. Use something a student can type from a card
-- without mistakes - no O/0 or I/1 confusion.
--
-- To stop a code being used again:
--   update public.school_codes set is_active = false where code = 'MARYS24';
-- ===========================================================================
