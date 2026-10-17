-- ===========================================================================
-- THE PENDING QUEUE, ON THE ADMIN PAGE
-- ===========================================================================
-- When somebody fills in the mentor form, or a school registers, the row
-- lands in pending_mentors or pending_schools and you get an email. Nothing
-- else happens: they are not in the directory and the school cannot sign in
-- until you approve them.
--
-- That part was always right. What was missing is a way to approve without
-- writing SQL. These functions are what the admin page calls.
--
-- Run this whole file once, AFTER admin-page.sql.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- 1. What is waiting.
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_pending()
returns table (
  kind          text,
  id            uuid,
  created_at    timestamptz,
  name          text,
  email         text,
  detail        text,
  industry      industry_slug,
  raw_level     text,
  raw_talks     text
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
           coalesce(m.company, ''), m.industry, m.experience_level, m.open_to_talks
      from public.pending_mentors m
     where m.status = 'pending'
    union all
    select 'school'::text, s.id, s.created_at, s.contact_name, s.email,
           s.school_name || coalesce(' · ' || s.county, ''), null::industry_slug, null::text, null::text
      from public.pending_schools s
     where s.status = 'pending'
     order by 3 desc;
end;
$$;

revoke all on function public.admin_list_pending from public, anon;
grant execute on function public.admin_list_pending to authenticated;


-- ---------------------------------------------------------------------------
-- 2. Approve a mentor.
--    Wraps approve_mentor(), then hides them. The existing function publishes
--    straight away, which is inconsistent with everything else on the page -
--    you should see the card before a school does.
-- ---------------------------------------------------------------------------
create or replace function public.admin_approve_mentor(
  p_pending_id       uuid,
  p_role_title       text,
  p_level            mentor_level,
  p_experience_label text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Not permitted' using errcode = '42501';
  end if;

  if coalesce(trim(p_role_title), '') = '' then
    raise exception 'A job title is required' using errcode = '22023';
  end if;

  new_id := public.approve_mentor(
    p_pending_id,
    trim(p_role_title),
    p_level,
    nullif(trim(coalesce(p_experience_label, '')), '')
  );

  update public.mentors set is_published = false where id = new_id;
  return new_id;
end;
$$;

revoke all on function public.admin_approve_mentor from public, anon;
grant execute on function public.admin_approve_mentor to authenticated;


-- ---------------------------------------------------------------------------
-- 3. Approve a school. This one DOES take effect immediately - approving a
--    school is what lets them sign in, which is the whole point of doing it.
-- ---------------------------------------------------------------------------
create or replace function public.admin_approve_school(p_pending_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Not permitted' using errcode = '42501';
  end if;

  return public.approve_school(p_pending_id);
end;
$$;

revoke all on function public.admin_approve_school from public, anon;
grant execute on function public.admin_approve_school to authenticated;


-- ---------------------------------------------------------------------------
-- 4. Turn somebody down. Nothing is deleted - the row stays, marked, so you
--    can see later that it was dealt with rather than missed.
-- ---------------------------------------------------------------------------
create or replace function public.admin_reject_pending(
  p_kind       text,
  p_pending_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Not permitted' using errcode = '42501';
  end if;

  if p_kind = 'mentor' then
    update public.pending_mentors set status = 'rejected' where id = p_pending_id;
  elsif p_kind = 'school' then
    update public.pending_schools set status = 'rejected' where id = p_pending_id;
  else
    raise exception 'Unknown kind %', p_kind using errcode = '22023';
  end if;

  return found;
end;
$$;

revoke all on function public.admin_reject_pending from public, anon;
grant execute on function public.admin_reject_pending to authenticated;


-- ===========================================================================
-- CHECKING IT
-- ===========================================================================
-- What is waiting right now, straight from the tables:
--   select 'mentor' as kind, full_name, email, company, status, created_at
--     from public.pending_mentors where status = 'pending'
--   union all
--   select 'school', contact_name, email, school_name, status, created_at
--     from public.pending_schools where status = 'pending';
-- ===========================================================================
