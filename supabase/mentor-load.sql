-- ===========================================================================
-- TWO LOGS: HOW OFTEN A MENTOR IS SHOWN, AND WHO ASKED TO CONTACT THEM
-- ===========================================================================
-- These are different things with different purposes, so they are different
-- tables with deliberately different shapes.
--
--   IMPRESSIONS - how often a mentor's card was shown. A daily counter per
--   mentor and NOTHING ELSE. For spreading exposure evenly you need to know
--   how often, never who saw them, so this stores no identity at all. The
--   feature that needs the most counting turns out to need none of the
--   identifying kind.
--
--   CONTACT REQUESTS - which member asked for which mentor's details, and
--   when. This one does need the identity, because its purpose is an audit
--   trail: if a concern is ever raised, you can establish what happened.
--
-- WHAT THEY ARE FOR, AND WHAT THEY ARE NOT FOR
--   Being shown in a list costs a mentor nothing. Being emailed by six people
--   in a fortnight is what burns a volunteer out. So impressions are for
--   spreading exposure; contact requests are the measure of actual load, and
--   the basis for pausing somebody before they get overwhelmed.
--
--   Not for insight about members. Keeping a record so one volunteer is not
--   buried while a colleague gets nothing is easy to explain to a mentor and
--   benefits the person whose data it is. The same record repurposed into
--   "who is engaging with whom" is a different thing needing a different
--   justification, and the privacy notice would have to say so.
--
-- STILL TO DO BEFORE THIS IS USED IN ANGER: the privacy notice does not yet
-- mention either log. Both sides should be told.
--
-- Run after school-invitations.sql.
-- ===========================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Impressions. No identity, by design.
-- ---------------------------------------------------------------------------
create table if not exists public.mentor_impressions (
  mentor_id uuid not null references public.mentors(id) on delete cascade,
  day       date not null default current_date,
  shown     integer not null default 0,
  primary key (mentor_id, day)
);

alter table public.mentor_impressions enable row level security;
revoke all on public.mentor_impressions from anon, authenticated;


-- ---------------------------------------------------------------------------
-- 2. Contact requests. Identity kept on purpose.
-- ---------------------------------------------------------------------------
create table if not exists public.mentor_contact_log (
  id           bigserial primary key,
  mentor_id    uuid not null references public.mentors(id) on delete cascade,
  member_email text not null,
  requested_at timestamptz not null default now()
);

create index if not exists mentor_contact_log_mentor_idx
  on public.mentor_contact_log (mentor_id, requested_at desc);

alter table public.mentor_contact_log enable row level security;
revoke all on public.mentor_contact_log from anon, authenticated;


-- ---------------------------------------------------------------------------
-- 3. Counting an impression.
--
-- The directory shows a whole sector at once, so this takes the list and
-- counts them in one call rather than one call per card.
--
-- A signed-in member could call this repeatedly and inflate a counter. The
-- worst that achieves is pushing a mentor DOWN the running order, since
-- exposure is equalised - there is nothing to gain and nothing exposed, so it
-- is not worth defending against with anything heavier than this comment.
-- ---------------------------------------------------------------------------
create or replace function public.record_impressions(p_mentors uuid[])
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  if not (public.is_approved_school() or public.is_approved_member()) then
    return;                       -- silently ignore; nothing to leak either way
  end if;

  insert into public.mentor_impressions (mentor_id, day, shown)
  select m, current_date, 1
    from unnest(p_mentors) as m
   where exists (select 1 from public.mentors where id = m)
  on conflict (mentor_id, day) do update
    set shown = public.mentor_impressions.shown + 1;
end;
$$;

revoke all on function public.record_impressions(uuid[]) from public, anon;
grant execute on function public.record_impressions(uuid[]) to authenticated;


-- ---------------------------------------------------------------------------
-- 4. mentor_contact, now logging.
--
--    NOTE THE VOLATILITY. This was declared "stable", and a stable function
--    is not allowed to write - Postgres rejects the insert at runtime, not at
--    creation, so this would have looked fine and failed the first time
--    somebody pressed the button. It has to be volatile to log anything.
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
    select m.public_contact, m.public_contact_kind
      from public.mentors m
     where m.id = p_mentor
       and m.is_published
       and m.member_contact_ok
       and m.public_contact is not null;

  -- RETURN QUERY sets FOUND, so this logs only a request that actually handed
  -- something over. A click on a mentor who has since withdrawn their consent
  -- returns nothing and is not a contact.
  if found then
    insert into public.mentor_contact_log (mentor_id, member_email)
    values (p_mentor, who);
  end if;
end;
$$;

revoke all on function public.mentor_contact(uuid) from public, anon;
grant execute on function public.mentor_contact(uuid) to authenticated;


-- ---------------------------------------------------------------------------
-- 5. What you see on the admin page: who is carrying the load.
-- ---------------------------------------------------------------------------
create or replace function public.admin_mentor_load(p_days integer default 14)
returns table (
  mentor_id     uuid,
  full_name     text,
  industry      industry_slug,
  is_published  boolean,
  impressions   bigint,
  requests      bigint,
  last_request  timestamptz
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
    select m.id, m.full_name, m.industry, m.is_published,
           coalesce(i.shown, 0)::bigint,
           coalesce(c.requests, 0)::bigint,
           c.last_request
      from public.mentors m
      left join (
        select mentor_id, sum(shown) as shown
          from public.mentor_impressions
         where day >= current_date - p_days
         group by mentor_id
      ) i on i.mentor_id = m.id
      left join (
        select mentor_id, count(*) as requests, max(requested_at) as last_request
          from public.mentor_contact_log
         where requested_at >= now() - make_interval(days => p_days)
         group by mentor_id
      ) c on c.mentor_id = m.id
     order by coalesce(c.requests, 0) desc, coalesce(i.shown, 0) desc,
              m.full_name;
end;
$$;

revoke all on function public.admin_mentor_load from public, anon;
grant execute on function public.admin_mentor_load to authenticated;


-- ---------------------------------------------------------------------------
-- 6. Throwing it away again.
--
--    Nothing here needs keeping forever. Two years on the contact log is long
--    enough to answer a question about something that happened; impressions
--    are useless after a few months. Run this occasionally, or put it on a
--    schedule when there is enough traffic to warrant one.
-- ---------------------------------------------------------------------------
create or replace function public.prune_logs()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  gone_contacts integer;
  gone_shown    integer;
begin
  if not public.is_admin() then
    raise exception 'Not permitted' using errcode = '42501';
  end if;

  delete from public.mentor_contact_log where requested_at < now() - interval '2 years';
  get diagnostics gone_contacts = row_count;

  delete from public.mentor_impressions where day < current_date - 400;
  get diagnostics gone_shown = row_count;

  return gone_contacts || ' contact records and ' || gone_shown ||
         ' impression rows removed';
end;
$$;

revoke all on function public.prune_logs from public, anon;
grant execute on function public.prune_logs to authenticated;

commit;


-- ===========================================================================
-- CHECKING IT
-- ===========================================================================
-- Who is carrying the load over the last fortnight:
--   select * from public.admin_mentor_load(14);
--
-- The audit trail for one mentor:
--   select member_email, requested_at
--     from public.mentor_contact_log
--    where mentor_id = 'paste-an-id'
--    order by requested_at desc;
-- ===========================================================================
