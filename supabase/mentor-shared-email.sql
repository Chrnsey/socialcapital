-- ===========================================================================
-- MENTORS CAN SHARE A LINKEDIN AND AN EMAIL WITH OVER-18 MEMBERS
-- ===========================================================================
-- Until now a mentor had ONE shared contact (public_contact), usually a
-- LinkedIn URL, with a kind of linkedin / email / other. Some mentors would
-- rather be emailed, some want both. This adds a second field, public_email,
-- for an address the mentor CHOOSES to share with over-18 members.
--
-- It is not their private email. That stays in mentor_contacts, which the
-- website cannot read at all. Mentors are told the difference on the form.
--
-- WHO CAN SEE public_email
--   Only an approved member (18 or over, invited by their school), only for a
--   published mentor who has agreed to be contacted, and only through
--   mentor_contact(), which logs the request. Schools cannot read it: select
--   on mentors is granted column by column, and this column is never granted.
--   Section 6 refuses to finish if that is not true.
--
-- TWO BUGS FIXED ON THE WAY
--   1. rename-to-members.sql renamed alumni_contact_ok on mentors but not on
--      pending_mentors. The signup form sends member_contact_ok, the insert
--      was rejected for an unknown column, and the form's fallback resent it
--      without the optional fields. No signup was lost, but since 18 October
--      every one has arrived without its contact opt-in, its LinkedIn and its
--      "went to a DEIS school" answer. Confirmed against the live database on
--      19 October 2026.
--   2. approve_mentor() never copied the contact opt-in or the shared contact
--      from the signup to the mentor. They had to be typed in again by hand.
--
-- Also: admin_list_mentors did not return public_contact_kind, so editing a
-- mentor on the admin page reset it. The kind is now worked out from the
-- link itself, and the admin page no longer asks for it.
--
-- SAFE TO RUN TWICE. The Supabase SQL editor does not reliably roll back a
-- failed run, so every step checks whether it has already been done.
--
-- Run after mentor-load.sql and rename-to-members.sql.
-- Then run test-the-gate.sql.
-- ===========================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. The signup queue: the missed rename, and the new field.
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'pending_mentors'
       and column_name = 'alumni_contact_ok'
  ) and not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'pending_mentors'
       and column_name = 'member_contact_ok'
  ) then
    alter table public.pending_mentors
      rename column alumni_contact_ok to member_contact_ok;
  end if;
end $$;

alter table public.pending_mentors
  add column if not exists member_contact_ok boolean not null default false,
  add column if not exists public_contact    text,
  add column if not exists public_email      text;


-- ---------------------------------------------------------------------------
-- 2. The mentor record.
-- ---------------------------------------------------------------------------
alter table public.mentors
  add column if not exists public_email text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'mentors_public_email_check'
       and conrelid = 'public.mentors'::regclass
  ) then
    alter table public.mentors add constraint mentors_public_email_check
      check (public_email is null
             or (public_email like '%_@_%' and char_length(public_email) <= 200));
  end if;
end $$;

comment on column public.mentors.public_email is
  'An email the mentor chose to share with over-18 members. NOT their private
   email, which stays in mentor_contacts. Read only through mentor_contact().';

-- Never granted, and revoked in case anything ever did. A column-level revoke
-- would do nothing against a table-level grant, which is why section 7 checks
-- the outcome rather than trusting this line.
revoke select (public_email) on public.mentors from anon, authenticated;

-- Mentors whose one shared contact was already an email: move it across, so
-- public_contact means "link" from now on.
update public.mentors
   set public_email        = lower(trim(public_contact)),
       public_contact      = null,
       public_contact_kind = null
 where public_email is null
   and public_contact like '%_@_%'
   and public_contact not ilike 'http%';


-- ---------------------------------------------------------------------------
-- 3. The contact gate. Same signature and return shape as before, so nothing
--    calling it breaks: it now returns up to two rows, the link and the email,
--    and still logs one request when it hands anything over.
-- ---------------------------------------------------------------------------
create or replace function public.mentor_contact(p_mentor uuid)
returns table (contact text, kind text)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  who text := lower(auth.jwt() ->> 'email');
begin
  if not public.is_approved_member() then
    return;               -- no rows, no error, nothing leaked
  end if;

  return query
    select x.contact, x.kind
      from public.mentors m
      cross join lateral (values
        (1, m.public_contact, coalesce(m.public_contact_kind, 'other')),
        (2, m.public_email,   'email')
      ) as x(ord, contact, kind)
     where m.id = p_mentor
       and m.is_published
       and m.member_contact_ok
       and x.contact is not null
     order by x.ord;

  if found then
    insert into public.mentor_contact_log (mentor_id, member_email)
    values (p_mentor, who);
  end if;
end;
$$;

revoke all on function public.mentor_contact(uuid) from public, anon;
grant execute on function public.mentor_contact(uuid) to authenticated;


-- ---------------------------------------------------------------------------
-- 4. The mentor functions gain public_email. Their argument lists change, so
--    "create or replace" would make a SECOND copy beside each one rather than
--    replacing it. Drop every version by oid first, then recreate.
--    Every old argument is kept, so the admin page keeps working between
--    running this and the new page going live.
-- ---------------------------------------------------------------------------
do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as signature
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('add_mentor', 'admin_add_mentor',
                         'admin_update_mentor', 'admin_list_mentors')
  loop
    execute 'drop function ' || f.signature;
  end loop;
end $$;


-- What kind of link is it. Used wherever a link is saved.
create or replace function public.contact_kind_of(p_link text)
returns text
language sql
immutable
as $$
  select case
    when nullif(trim(coalesce(p_link, '')), '') is null then null
    when p_link ilike '%linkedin.com%' then 'linkedin'
    else 'other'
  end;
$$;


create or replace function public.add_mentor(
  full_name            text,
  role_title           text,
  industry             industry_slug,
  level                mentor_level,
  contact_email        text,
  experience_label     text    default null,
  open_to_talks        boolean default false,
  is_alumnus           boolean default false,
  alumnus_school_name  text    default null,
  member_contact_ok    boolean default false,
  public_contact       text    default null,
  public_contact_kind  text    default null,
  employer             text    default null,
  phone                text    default null,
  notes                text    default null,
  publish              boolean default false,
  route_in             text    default null,
  study_field          text    default null,
  study_detail         text    default null,
  qualification        text    default null,
  bio                  text    default null,
  public_email         text    default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
begin
  insert into public.mentors (
    full_name, role_title, industry, level, experience_label,
    open_to_talks, is_alumnus, alumnus_school_name, member_contact_ok,
    public_contact, public_contact_kind, public_email, is_published,
    route_in, study_field, study_detail, qualification, bio
  )
  values (
    add_mentor.full_name, add_mentor.role_title, add_mentor.industry,
    add_mentor.level, add_mentor.experience_label, add_mentor.open_to_talks,
    add_mentor.is_alumnus, add_mentor.alumnus_school_name,
    add_mentor.member_contact_ok, add_mentor.public_contact,
    coalesce(add_mentor.public_contact_kind,
             public.contact_kind_of(add_mentor.public_contact)),
    add_mentor.public_email, add_mentor.publish,
    add_mentor.route_in, add_mentor.study_field,
    add_mentor.study_detail, add_mentor.qualification, add_mentor.bio
  )
  returning id into new_id;

  insert into public.mentor_contacts (mentor_id, email, phone, company, notes)
  values (new_id, add_mentor.contact_email, add_mentor.phone,
          add_mentor.employer, add_mentor.notes);

  return new_id;
end;
$$;

revoke execute on function public.add_mentor from public, anon, authenticated;


create or replace function public.admin_add_mentor(
  p_full_name            text,
  p_role_title           text,
  p_industry             industry_slug,
  p_level                mentor_level,
  p_contact_email        text,
  p_experience_label     text    default null,
  p_open_to_talks        boolean default false,
  p_is_alumnus           boolean default false,
  p_alumnus_school_name  text    default null,
  p_member_contact_ok    boolean default false,
  p_public_contact       text    default null,
  p_public_contact_kind  text    default null,
  p_employer             text    default null,
  p_phone                text    default null,
  p_notes                text    default null,
  p_route_in             text    default null,
  p_study_field          text    default null,
  p_study_detail         text    default null,
  p_qualification        text    default null,
  p_bio                  text    default null,
  p_public_email         text    default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  shared_email text := lower(nullif(trim(coalesce(p_public_email, '')), ''));
begin
  if not public.is_admin() then
    raise exception 'Not permitted' using errcode = '42501';
  end if;
  if coalesce(trim(p_full_name), '') = '' then
    raise exception 'A name is required' using errcode = '22023';
  end if;
  if coalesce(trim(p_contact_email), '') = '' then
    raise exception 'A contact email is required' using errcode = '22023';
  end if;
  if char_length(coalesce(p_bio, '')) > 500 then
    raise exception 'That bio is % characters. The limit is 500.',
      char_length(p_bio) using errcode = '22023';
  end if;
  if shared_email is not null and shared_email not like '%_@_%' then
    raise exception 'The email to share does not look like an email address'
      using errcode = '22023';
  end if;

  return public.add_mentor(
    full_name           => trim(p_full_name),
    role_title          => trim(p_role_title),
    industry            => p_industry,
    level               => p_level,
    contact_email       => lower(trim(p_contact_email)),
    experience_label    => nullif(trim(coalesce(p_experience_label, '')), ''),
    open_to_talks       => p_open_to_talks,
    is_alumnus          => p_is_alumnus,
    alumnus_school_name => nullif(trim(coalesce(p_alumnus_school_name, '')), ''),
    member_contact_ok   => p_member_contact_ok,
    public_contact      => nullif(trim(coalesce(p_public_contact, '')), ''),
    public_contact_kind => nullif(trim(coalesce(p_public_contact_kind, '')), ''),
    employer            => nullif(trim(coalesce(p_employer, '')), ''),
    phone               => nullif(trim(coalesce(p_phone, '')), ''),
    notes               => nullif(trim(coalesce(p_notes, '')), ''),
    publish             => false,
    route_in            => nullif(trim(coalesce(p_route_in, '')), ''),
    study_field         => nullif(trim(coalesce(p_study_field, '')), ''),
    study_detail        => nullif(trim(coalesce(p_study_detail, '')), ''),
    qualification       => nullif(trim(coalesce(p_qualification, '')), ''),
    bio                 => nullif(trim(coalesce(p_bio, '')), ''),
    public_email        => shared_email
  );
end;
$$;

revoke all on function public.admin_add_mentor from public, anon;
grant execute on function public.admin_add_mentor to authenticated;


create or replace function public.admin_update_mentor(
  p_mentor_id            uuid,
  p_full_name            text,
  p_role_title           text,
  p_industry             industry_slug,
  p_level                mentor_level,
  p_experience_label     text    default null,
  p_open_to_talks        boolean default false,
  p_is_alumnus           boolean default false,
  p_alumnus_school_name  text    default null,
  p_member_contact_ok    boolean default false,
  p_public_contact       text    default null,
  p_public_contact_kind  text    default null,
  p_route_in             text    default null,
  p_study_field          text    default null,
  p_study_detail         text    default null,
  p_qualification        text    default null,
  p_bio                  text    default null,
  p_public_email         text    default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  link         text := nullif(trim(coalesce(p_public_contact, '')), '');
  shared_email text := lower(nullif(trim(coalesce(p_public_email, '')), ''));
begin
  if not public.is_admin() then
    raise exception 'Not permitted' using errcode = '42501';
  end if;
  if char_length(coalesce(p_bio, '')) > 500 then
    raise exception 'That bio is % characters. The limit is 500.',
      char_length(p_bio) using errcode = '22023';
  end if;
  if shared_email is not null and shared_email not like '%_@_%' then
    raise exception 'The email to share does not look like an email address'
      using errcode = '22023';
  end if;

  update public.mentors
     set full_name           = trim(p_full_name),
         role_title          = trim(p_role_title),
         industry            = p_industry,
         level               = p_level,
         experience_label    = nullif(trim(coalesce(p_experience_label, '')), ''),
         open_to_talks       = p_open_to_talks,
         is_alumnus          = p_is_alumnus,
         alumnus_school_name = nullif(trim(coalesce(p_alumnus_school_name, '')), ''),
         member_contact_ok   = p_member_contact_ok,
         public_contact      = link,
         public_contact_kind = coalesce(nullif(trim(coalesce(p_public_contact_kind, '')), ''),
                                        public.contact_kind_of(link)),
         public_email        = shared_email,
         route_in            = nullif(trim(coalesce(p_route_in, '')), ''),
         study_field         = nullif(trim(coalesce(p_study_field, '')), ''),
         study_detail        = nullif(trim(coalesce(p_study_detail, '')), ''),
         qualification       = nullif(trim(coalesce(p_qualification, '')), ''),
         bio                 = nullif(trim(coalesce(p_bio, '')), '')
   where id = p_mentor_id;

  return found;
end;
$$;

revoke all on function public.admin_update_mentor from public, anon;
grant execute on function public.admin_update_mentor to authenticated;


create or replace function public.admin_list_mentors()
returns table (
  id                  uuid,
  full_name           text,
  role_title          text,
  industry            industry_slug,
  level               mentor_level,
  experience_label    text,
  open_to_talks       boolean,
  is_alumnus          boolean,
  alumnus_school_name text,
  member_contact_ok   boolean,
  public_contact      text,
  public_email        text,
  is_published        boolean,
  contact_email       text,
  employer            text,
  notes               text,
  created_at          timestamptz,
  route_in            text,
  study_field         text,
  study_detail        text,
  qualification       text,
  bio                 text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Not permitted' using errcode = '42501';
  end if;

  return query
    select m.id, m.full_name, m.role_title, m.industry, m.level,
           m.experience_label, m.open_to_talks, m.is_alumnus,
           m.alumnus_school_name, m.member_contact_ok, m.public_contact,
           m.public_email, m.is_published, c.email, c.company, c.notes,
           m.created_at, m.route_in, m.study_field, m.study_detail,
           m.qualification, m.bio
      from public.mentors m
      left join public.mentor_contacts c on c.mentor_id = m.id
     order by m.is_published, m.created_at desc;
end;
$$;

revoke all on function public.admin_list_mentors from public, anon;
grant execute on function public.admin_list_mentors to authenticated;


-- ---------------------------------------------------------------------------
-- 5. Approving a signup now carries the contact opt-in and what they chose
--    to share. Same five arguments with the same names as the version in
--    alumni.sql, so this replaces it rather than adding a second one.
--
--    Older signups put a link OR an email in one box. If that box holds an
--    email and the new email box is empty, it goes across as the email.
-- ---------------------------------------------------------------------------
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
  p          public.pending_mentors%rowtype;
  new_id     uuid;
  v_shared   text;
  v_link     text;
  v_email    text;
begin
  select * into p from public.pending_mentors where id = pending_id;
  if not found then
    raise exception 'No pending mentor with id %', pending_id;
  end if;

  v_shared := nullif(trim(coalesce(p.public_contact, '')), '');
  v_email  := lower(nullif(trim(coalesce(p.public_email, '')), ''));

  if v_shared like '%_@_%' and v_shared not ilike 'http%' then
    v_email := coalesce(v_email, lower(v_shared));
    v_link  := null;
  else
    v_link  := v_shared;
  end if;

  -- Never let a typo in a signup stop the approval: a bad address is dropped,
  -- and you can add it on the admin page.
  if v_email is not null and (v_email not like '%_@_%' or char_length(v_email) > 200) then
    v_email := null;
  end if;

  insert into public.mentors
    (full_name, role_title, industry, level, experience_label, open_to_talks,
     is_alumnus, alumnus_school_id, alumnus_school_name, left_school_year,
     member_contact_ok, public_contact, public_contact_kind, public_email)
  values
    (p.full_name, role_title, coalesce(p.industry, 'other'), level,
     experience_label, coalesce(p.open_to_talks ilike 'yes%', false),
     p.is_alumnus, alumnus_school, p.alumnus_school_name, p.left_school_year,
     coalesce(p.member_contact_ok, false), v_link,
     public.contact_kind_of(v_link), v_email)
  returning id into new_id;

  insert into public.mentor_contacts (mentor_id, email, company)
  values (new_id, lower(p.email), p.company);

  update public.pending_mentors set status = 'approved' where id = pending_id;
  return new_id;
end;
$$;

revoke all on function public.approve_mentor(uuid, text, mentor_level, text, uuid)
  from public, anon, authenticated;


-- ---------------------------------------------------------------------------
-- 6. Refuse to finish in a broken or leaky state.
-- ---------------------------------------------------------------------------
do $$
begin
  if has_column_privilege('authenticated', 'public.mentors', 'public_email', 'select')
     or has_column_privilege('anon', 'public.mentors', 'public_email', 'select') then
    raise exception
      'Stopping: a signed-in school could read mentors.public_email directly. '
      'Check for a table-level grant on public.mentors.';
  end if;

  if has_column_privilege('authenticated', 'public.mentors', 'public_contact', 'select') then
    raise exception
      'Stopping: a signed-in school could read mentors.public_contact directly.';
  end if;

  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'mentors'
       and policyname = 'approved schools and members read mentors'
  ) then
    raise exception 'Stopping: the mentors read policy is missing.';
  end if;

  if to_regclass('public.mentor_contact_log') is null then
    raise exception 'Stopping: mentor_contact_log is missing. Run mentor-load.sql first.';
  end if;

  if (select count(*) from pg_proc
       where pronamespace = 'public'::regnamespace
         and proname = 'approve_mentor') <> 1 then
    raise exception 'Stopping: there is not exactly one approve_mentor.';
  end if;

  if (select count(*) from pg_proc
       where pronamespace = 'public'::regnamespace
         and proname in ('add_mentor', 'admin_add_mentor',
                         'admin_update_mentor', 'admin_list_mentors')) <> 4 then
    raise exception 'Stopping: a mentor function is missing or duplicated.';
  end if;
end $$;

commit;


-- ===========================================================================
-- CHECK IT
-- ===========================================================================
-- 1. Run test-the-gate.sql. Every row should say PASS.
-- 2. On the admin page, edit a mentor: there are now two boxes, LinkedIn and
--    email to share. Save one with both filled in.
-- 3. Signups that arrived between 18 October and running this came in without
--    the optional fields (contact opt-in, LinkedIn, DEIS school). Ask those
--    mentors directly before approving them.
-- ===========================================================================
