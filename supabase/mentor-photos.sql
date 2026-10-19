-- ===========================================================================
-- MENTOR PHOTOS
-- ===========================================================================
-- A mentor can add a photo when they sign up. It sits in the signup queue
-- with everything else, Jack sees it before anybody else does, and approving
-- the mentor carries it onto their card. Jack can also add, replace or
-- remove a photo from the admin page (for anyone who emails one in).
--
-- WHERE THE PHOTOS LIVE
--   A PRIVATE storage bucket, mentor-photos. Nothing in it has a public link.
--     pending/<uuid>.jpg   uploaded from the signup form, by anyone
--     mentors/<uuid>.jpg   uploaded by Jack from the admin page
--   The browser shrinks every photo to a 600px square JPEG before upload,
--   which also strips the camera's hidden details (location and so on).
--
-- WHO CAN DO WHAT
--   Anyone (the signup form): ADD a file under pending/. Not read it back,
--     not list the bucket, not replace or delete anything.
--   Approved schools and members: READ a photo, only if it belongs to a
--     published mentor. The site asks for a link that expires after an hour.
--   Jack (is_admin): read, add under mentors/, and delete.
--
-- SAFE TO RUN TWICE. The Supabase SQL editor does not reliably roll back a
-- failed run, so every step checks whether it has already been done.
--
-- Run after mentor-shared-email.sql. Then run test-the-gate.sql.
-- ===========================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. The bucket. Private, JPEG only, 1 MB at most (a shrunk photo is about
--    a tenth of that).
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('mentor-photos', 'mentor-photos', false, 1048576, array['image/jpeg'])
on conflict (id) do update
  set public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;


-- ---------------------------------------------------------------------------
-- 2. Where each photo is recorded.
-- ---------------------------------------------------------------------------
alter table public.pending_mentors add column if not exists photo_path text;
alter table public.mentors         add column if not exists photo_path text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'pending_mentors_photo_path_check'
       and conrelid = 'public.pending_mentors'::regclass
  ) then
    alter table public.pending_mentors add constraint pending_mentors_photo_path_check
      check (photo_path is null
             or photo_path ~ '^pending/[0-9a-f-]{36}\.jpg$');
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'mentors_photo_path_check'
       and conrelid = 'public.mentors'::regclass
  ) then
    alter table public.mentors add constraint mentors_photo_path_check
      check (photo_path is null
             or photo_path ~ '^(pending|mentors)/[0-9a-f-]{36}\.jpg$');
  end if;
end $$;

comment on column public.mentors.photo_path is
  'Path of the mentor''s photo in the private mentor-photos bucket, or null.';

-- The directory needs the path to ask for a link. The path on its own shows
-- nothing: the bucket is private and the read rule below still applies.
grant select (photo_path) on public.mentors to authenticated;


-- ---------------------------------------------------------------------------
-- 3. Who may see a given photo. One function, so the storage rule and the
--    gate test ask exactly the same question.
-- ---------------------------------------------------------------------------
create or replace function public.can_view_mentor_photo(p_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin()
      or (
        (public.is_approved_school() or public.is_approved_member())
        and exists (
          select 1 from public.mentors m
           where m.photo_path = p_name
             and m.is_published
        )
      );
$$;

revoke all on function public.can_view_mentor_photo(text) from public, anon;
grant execute on function public.can_view_mentor_photo(text) to authenticated;


-- ---------------------------------------------------------------------------
-- 4. The storage rules. Dropped and recreated so a re-run leaves exactly
--    these four. There is deliberately no UPDATE rule: nothing is ever
--    overwritten, a new photo gets a new name.
-- ---------------------------------------------------------------------------
drop policy if exists "mentor photo: signup form adds"      on storage.objects;
drop policy if exists "mentor photo: approved viewers read" on storage.objects;
drop policy if exists "mentor photo: admin adds"            on storage.objects;
drop policy if exists "mentor photo: admin deletes"         on storage.objects;

create policy "mentor photo: signup form adds"
  on storage.objects for insert
  to anon, authenticated
  with check (
    bucket_id = 'mentor-photos'
    and name ~ '^pending/[0-9a-f-]{36}\.jpg$'
  );

create policy "mentor photo: approved viewers read"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'mentor-photos'
    and public.can_view_mentor_photo(name)
  );

create policy "mentor photo: admin adds"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'mentor-photos'
    and public.is_admin()
    and name ~ '^mentors/[0-9a-f-]{36}\.jpg$'
  );

create policy "mentor photo: admin deletes"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'mentor-photos'
    and public.is_admin()
  );


-- ---------------------------------------------------------------------------
-- 5. Approving a signup carries the photo across. Same five arguments with
--    the same names, so this replaces the version in mentor-shared-email.sql
--    rather than adding a second one. Only the photo lines are new.
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

  if v_email is not null and (v_email not like '%_@_%' or char_length(v_email) > 200) then
    v_email := null;
  end if;

  insert into public.mentors
    (full_name, role_title, industry, level, experience_label, open_to_talks,
     is_alumnus, alumnus_school_id, alumnus_school_name, left_school_year,
     member_contact_ok, public_contact, public_contact_kind, public_email,
     photo_path)
  values
    (p.full_name, role_title, coalesce(p.industry, 'other'), level,
     experience_label, coalesce(p.open_to_talks ilike 'yes%', false),
     p.is_alumnus, alumnus_school, p.alumnus_school_name, p.left_school_year,
     coalesce(p.member_contact_ok, false), v_link,
     public.contact_kind_of(v_link), v_email,
     p.photo_path)
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
-- 6. The admin lists gain a photo column. A different set of columns cannot
--    be "create or replace"d, so each is dropped first. Neither takes any
--    arguments, so there is only ever one of each.
-- ---------------------------------------------------------------------------
drop function if exists public.admin_list_pending();

create function public.admin_list_pending()
returns table (
  kind          text,
  id            uuid,
  created_at    timestamptz,
  name          text,
  email         text,
  detail        text,
  industry      industry_slug,
  raw_level     text,
  raw_talks     text,
  photo_path    text
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
    select 'mentor'::text, m.id, m.created_at, m.full_name, m.email,
           coalesce(m.company, ''), m.industry, m.experience_level, m.open_to_talks,
           m.photo_path
      from public.pending_mentors m
     where m.status = 'pending'
    union all
    select 'school'::text, s.id, s.created_at, s.contact_name, s.email,
           s.school_name || coalesce(' · ' || s.county, ''), null::industry_slug,
           null::text, null::text, null::text
      from public.pending_schools s
     where s.status = 'pending'
     order by 3 desc;
end;
$$;

revoke all on function public.admin_list_pending from public, anon;
grant execute on function public.admin_list_pending to authenticated;


drop function if exists public.admin_list_mentors();

create function public.admin_list_mentors()
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
  bio                 text,
  photo_path          text
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
           m.qualification, m.bio, m.photo_path
      from public.mentors m
      left join public.mentor_contacts c on c.mentor_id = m.id
     order by m.is_published, m.created_at desc;
end;
$$;

revoke all on function public.admin_list_mentors from public, anon;
grant execute on function public.admin_list_mentors to authenticated;


-- ---------------------------------------------------------------------------
-- 7. Jack sets or clears a mentor's photo. Returns the photo it replaced, so
--    the admin page can delete that file rather than leave it lying about.
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_mentor_photo(
  p_mentor_id  uuid,
  p_photo_path text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  old_path text;
begin
  if not public.is_admin() then
    raise exception 'Not permitted' using errcode = '42501';
  end if;

  select photo_path into old_path from public.mentors where id = p_mentor_id;
  if not found then
    raise exception 'No mentor with id %', p_mentor_id using errcode = '22023';
  end if;

  update public.mentors
     set photo_path = nullif(trim(coalesce(p_photo_path, '')), '')
   where id = p_mentor_id;

  return old_path;
end;
$$;

revoke all on function public.admin_set_mentor_photo(uuid, text) from public, anon;
grant execute on function public.admin_set_mentor_photo(uuid, text) to authenticated;


-- ---------------------------------------------------------------------------
-- 8. Refuse to finish in a broken or leaky state.
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from storage.buckets where id = 'mentor-photos' and public) then
    raise exception 'Stopping: the mentor-photos bucket is public.';
  end if;

  if (select count(*) from pg_policies
       where schemaname = 'storage' and tablename = 'objects'
         and policyname like 'mentor photo:%') <> 4 then
    raise exception 'Stopping: the four mentor photo storage rules are not all in place.';
  end if;

  if exists (
    select 1 from pg_policies
     where schemaname = 'storage' and tablename = 'objects'
       and policyname like 'mentor photo:%'
       and cmd = 'SELECT' and 'anon' = any(roles)
  ) then
    raise exception 'Stopping: anonymous visitors could read mentor photos.';
  end if;

  if (select count(*) from pg_proc
       where pronamespace = 'public'::regnamespace
         and proname = 'approve_mentor') <> 1 then
    raise exception 'Stopping: there is not exactly one approve_mentor.';
  end if;

  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'mentors'
       and policyname = 'approved schools and members read mentors'
  ) then
    raise exception 'Stopping: the mentors read policy is missing.';
  end if;
end $$;

commit;

-- Tell Supabase's API to look at the database again. Without this it can go
-- on serving its old picture of the tables for a while, and the new photo
-- columns read as "not found" even though they exist.
notify pgrst, 'reload schema';


-- ===========================================================================
-- CHECK IT
-- ===========================================================================
-- 1. Run test-the-gate.sql. Every row should say PASS.
-- 2. In Supabase, Storage: a bucket called mentor-photos, marked private.
-- 3. On the admin page, edit a mentor, add a photo, save. It should show on
--    their card in the directory once they are published.
--
-- TIDYING UP
-- Turning someone down from the admin page deletes their photo too. A photo
-- can still be left behind if somebody uploaded one and their signup then
-- failed. To see any, in Storage > mentor-photos > pending, compare against:
--
--   select photo_path from public.pending_mentors where photo_path is not null
--   union
--   select photo_path from public.mentors where photo_path is not null;
-- ===========================================================================
