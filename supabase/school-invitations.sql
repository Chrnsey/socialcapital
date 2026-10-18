-- ===========================================================================
-- SCHOOLS ISSUE THE INVITATIONS THEMSELVES
-- ===========================================================================
-- Replaces the shared school code. One code per school meant anyone who was
-- forwarded it, or saw it in a group chat, could join if they were over 18 -
-- and could then pull the contact details of every mentor who agreed to be
-- contactable. A leaked code was a leaked directory.
--
-- Instead: a guidance counsellor signs into their existing school account and
-- issues an invitation for one named address. Only that address can use it,
-- it expires, and it can be revoked.
--
-- WHY THE SCHOOL SENDS THE EMAIL, NOT US
--   school_issue_invite returns a link. The counsellor pastes it into their
--   own email. We never hold a list of student addresses, which would be a
--   data transfer needing its own lawful basis and an inbox full of lists
--   going stale. It is also better for the student: a link from the school's
--   own address, from a person they know, rather than an unexpected mail from
--   a platform they have never heard of.
--
-- WHY THE COUNSELLOR CONFIRMS THE AGE
--   The date of birth on the form is whatever somebody typed. The school
--   knows who is actually 18. Two independent checks, with the one that
--   matters sitting where the knowledge really is.
--
-- Run after rename-to-members.sql.
-- ===========================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. The invitations.
-- ---------------------------------------------------------------------------
create table if not exists public.member_invites (
  token        text primary key
                 default encode(gen_random_bytes(18), 'hex'),
  school_id    uuid not null references public.schools(id) on delete cascade,
  email        text not null,
  issued_by    text not null,              -- the school account that made it
  issued_at    timestamptz not null default now(),
  expires_at   timestamptz not null default (now() + interval '30 days'),
  age_attested boolean not null default false,
  accepted_at  timestamptz,
  revoked_at   timestamptz,
  constraint member_invites_email_lower check (email = lower(email))
);

create index if not exists member_invites_school_idx
  on public.member_invites (school_id, issued_at desc);

alter table public.member_invites enable row level security;
-- No policies on purpose. Everything goes through the functions below, which
-- check who is asking. A table with RLS on and no policy is unreadable.
revoke all on public.member_invites from anon, authenticated;

-- Where a member came from, so the audit trail survives the invitation.
alter table public.members
  add column if not exists invite_token text references public.member_invites(token);


-- ---------------------------------------------------------------------------
-- 2. Which school is asking.
-- ---------------------------------------------------------------------------
create or replace function public.my_school_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.schools
   where lower(email) = lower(auth.jwt() ->> 'email')
     and is_active
   limit 1;
$$;

revoke all on function public.my_school_id() from public, anon;
grant execute on function public.my_school_id() to authenticated;


-- ---------------------------------------------------------------------------
-- 3. Issue one.
-- ---------------------------------------------------------------------------
create or replace function public.school_issue_invite(
  p_email        text,
  p_age_attested boolean default false
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  sid   uuid;
  tok   text;
  clean text := lower(trim(p_email));
begin
  sid := public.my_school_id();
  if sid is null then
    raise exception 'Not permitted' using errcode = '42501';
  end if;

  if clean !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'That does not look like an email address'
      using errcode = '22023';
  end if;

  if not p_age_attested then
    raise exception 'The school has to confirm this person is 18 or over'
      using errcode = '22023';
  end if;

  -- Already a member? Say so rather than issuing a second invitation.
  if exists (select 1 from public.members where lower(email) = clean and is_active) then
    raise exception 'That address has already joined' using errcode = '23505';
  end if;

  -- Replace any live invitation for the same address at this school, so a
  -- counsellor re-sending does not leave two valid tokens in circulation.
  update public.member_invites
     set revoked_at = now()
   where school_id = sid
     and email = clean
     and accepted_at is null
     and revoked_at is null;

  insert into public.member_invites (school_id, email, issued_by, age_attested)
  values (sid, clean, lower(auth.jwt() ->> 'email'), true)
  returning token into tok;

  return tok;
end;
$$;

revoke all on function public.school_issue_invite from public, anon;
grant execute on function public.school_issue_invite to authenticated;


-- ---------------------------------------------------------------------------
-- 4. What this school has issued, and who has joined.
-- ---------------------------------------------------------------------------
create or replace function public.school_list_invites()
returns table (
  token       text,
  email       text,
  issued_at   timestamptz,
  expires_at  timestamptz,
  state       text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  sid uuid;
begin
  sid := public.my_school_id();
  if sid is null then
    raise exception 'Not permitted' using errcode = '42501';
  end if;

  return query
    select i.token, i.email, i.issued_at, i.expires_at,
           case
             when i.revoked_at  is not null then 'revoked'
             when i.accepted_at is not null then 'joined'
             when i.expires_at  < now()     then 'expired'
             else 'waiting'
           end
      from public.member_invites i
     where i.school_id = sid
     order by i.issued_at desc;
end;
$$;

revoke all on function public.school_list_invites from public, anon;
grant execute on function public.school_list_invites to authenticated;


-- ---------------------------------------------------------------------------
-- 5. Take one back.
-- ---------------------------------------------------------------------------
create or replace function public.school_revoke_invite(p_token text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  sid uuid;
begin
  sid := public.my_school_id();
  if sid is null then
    raise exception 'Not permitted' using errcode = '42501';
  end if;

  -- Revoking an accepted invitation also removes that person's access, which
  -- is the point: a school must be able to take someone out without emailing
  -- us about it.
  update public.members
     set is_active = false
   where invite_token = p_token
     and school_id = sid;

  update public.member_invites
     set revoked_at = coalesce(revoked_at, now())
   where token = p_token
     and school_id = sid;

  return found;
end;
$$;

revoke all on function public.school_revoke_invite from public, anon;
grant execute on function public.school_revoke_invite to authenticated;


-- ---------------------------------------------------------------------------
-- 6. Accepting one. Called by somebody who is not signed in yet, so the
--    token is the only thing proving they were invited.
--
--    Every failure that would confirm a token exists returns the same
--    'invalid'. Otherwise a wrong email address against a real token tells
--    the person holding it that the token is real.
-- ---------------------------------------------------------------------------
create or replace function public.accept_invite(
  p_token text,
  p_email text,
  p_dob   date
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  inv   public.member_invites%rowtype;
  clean text := lower(trim(p_email));
begin
  if p_dob is null or p_dob > (current_date - interval '18 years') then
    return 'under_18';
  end if;

  select * into inv from public.member_invites
   where token = trim(p_token);

  if not found
     or inv.email <> clean
     or inv.revoked_at is not null then
    return 'invalid';
  end if;

  if inv.accepted_at is not null then return 'already_used'; end if;
  if inv.expires_at < now()      then return 'expired';      end if;

  insert into public.members (email, school_id, date_of_birth, invite_token)
  values (clean, inv.school_id, p_dob, inv.token)
  on conflict (lower(email)) do update
    set is_active    = true,
        school_id    = excluded.school_id,
        invite_token = excluded.invite_token;

  update public.member_invites set accepted_at = now() where token = inv.token;
  return 'ok';
end;
$$;

revoke all on function public.accept_invite from public;
grant execute on function public.accept_invite to anon, authenticated;


-- ---------------------------------------------------------------------------
-- 7. Turn the shared codes off.
--    The table is kept rather than dropped - it is a record of who was issued
--    what - but nothing can register with a code any more.
-- ---------------------------------------------------------------------------
update public.school_codes set is_active = false;
drop function if exists public.register_member(text, text, date);

commit;


-- ===========================================================================
-- CHECKING IT
-- ===========================================================================
-- Nothing can be read directly, by design:
--   select * from public.member_invites;        -- works for you in here only
--
-- Live invitations per school:
--   select s.school_name, i.email, i.issued_at, i.accepted_at, i.revoked_at
--     from public.member_invites i
--     join public.schools s on s.id = i.school_id
--    order by i.issued_at desc;
-- ===========================================================================
