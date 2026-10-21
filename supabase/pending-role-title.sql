-- ===========================================================================
-- ASK MENTORS FOR THEIR OWN JOB TITLE
-- ===========================================================================
-- The signup form never collected one, so approving somebody meant typing it
-- from whatever the email said. Now they write it themselves and the approval
-- form is pre-filled - still editable, because people describe their own job
-- in ways that do not always read well on a card.
--
-- Safe to run twice. Run it in the Supabase SQL editor.
-- ===========================================================================

begin;

alter table public.pending_mentors
  add column if not exists role_title text;


-- Hand it to the admin page alongside everything else that is waiting.
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
  raw_talks     text,
  role_title    text
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
           coalesce(m.company, ''), m.industry, m.experience_level,
           m.open_to_talks, m.role_title
      from public.pending_mentors m
     where m.status = 'pending'
    union all
    select 'school'::text, s.id, s.created_at, s.contact_name, s.email,
           s.school_name || coalesce(' · ' || s.county, ''),
           null::industry_slug, null::text, null::text, null::text
      from public.pending_schools s
     where s.status = 'pending'
     order by 3 desc;
end;
$$;

revoke all on function public.admin_list_pending from public, anon;
grant execute on function public.admin_list_pending to authenticated;

commit;
