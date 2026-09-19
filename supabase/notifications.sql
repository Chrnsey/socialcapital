-- ===========================================================================
-- EMAIL ME WHEN SOMEONE SUBMITS A FORM
-- ===========================================================================
-- Sends you an email the moment a school registers or a mentor signs up, so
-- you don't have to remember to check the tables.
--
-- BEFORE YOU RUN THIS: replace YOUR_RESEND_API_KEY on the marked line with
-- the Resend key you created. It is stored encrypted in Supabase's Vault,
-- not in plain text, and never appears on the website.
--
-- Run the whole file in the SQL Editor. Safe to run more than once.
-- ===========================================================================

-- 1. Turn on the extension that lets the database send web requests.
create extension if not exists pg_net with schema extensions;

-- 2. Store the Resend key securely.
--    <<< EDIT ONE LINE: the key on the line marked below >>>
do $$
declare
  k text := 'PASTE_YOUR_KEY_HERE';   -- <<< THIS LINE. Your key starts with re_
begin
  -- Safety check - leave this alone. It stops the file half-installing if
  -- you forgot to paste the key in above.
  if left(k, 3) <> 're_' then
    raise exception 'Paste your Resend API key on the line marked above (it starts with re_).';
  end if;

  -- Replace any previous value so you can re-run this after rotating the key.
  delete from vault.secrets where name = 'resend_api_key';
  perform vault.create_secret(k, 'resend_api_key');
end $$;

-- Where the alerts go. Change this if you'd rather they went elsewhere.
do $$ begin
  delete from vault.secrets where name = 'alert_email';
  perform vault.create_secret('registration@socialcapital.ie', 'alert_email');
end $$;


-- 3. The function that actually sends the alert.
create or replace function public.notify_new_submission()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  api_key   text;
  to_addr   text;
  subject   text;
  body_html text;
begin
  select decrypted_secret into api_key
    from vault.decrypted_secrets where name = 'resend_api_key';
  select decrypted_secret into to_addr
    from vault.decrypted_secrets where name = 'alert_email';

  -- If the key is missing, do nothing rather than blocking the submission.
  -- Never let an alert failure stop someone registering.
  if api_key is null or to_addr is null then
    return new;
  end if;

  if tg_table_name = 'pending_schools' then
    subject := 'New school registration: ' || new.school_name;
    body_html :=
      '<h2>New school registration</h2>' ||
      '<p><strong>School:</strong> '  || coalesce(new.school_name, '-')  || '<br>' ||
      '<strong>Contact:</strong> '    || coalesce(new.contact_name, '-') || '<br>' ||
      '<strong>Email:</strong> '      || coalesce(new.email, '-')        || '<br>' ||
      '<strong>County:</strong> '     || coalesce(new.county, '-')       || '</p>' ||
      '<p>Approve with:<br><code>select public.approve_school(''' || new.id || ''');</code></p>';
  else
    subject := 'New mentor signup: ' || new.full_name;
    body_html :=
      '<h2>New mentor signup</h2>' ||
      '<p><strong>Name:</strong> '     || coalesce(new.full_name, '-')        || '<br>' ||
      '<strong>Email:</strong> '       || coalesce(new.email, '-')            || '<br>' ||
      '<strong>Company:</strong> '     || coalesce(new.company, '-')          || '<br>' ||
      '<strong>Industry:</strong> '    || coalesce(new.industry::text, '-')   || '<br>' ||
      '<strong>Experience:</strong> '  || coalesce(new.experience_level, '-') || '<br>' ||
      '<strong>School talks:</strong> '|| coalesce(new.open_to_talks, '-')    || '<br>' ||
      '<strong>Came from:</strong> '   || coalesce(new.source, '-')           || '</p>' ||
      '<p>Their id, for approving: <code>' || new.id || '</code></p>';
  end if;

  perform net.http_post(
    url     := 'https://api.resend.com/emails',
    headers := jsonb_build_object(
                 'Authorization', 'Bearer ' || api_key,
                 'Content-Type',  'application/json'
               ),
    body    := jsonb_build_object(
                 'from',    'Social Capital <registration@socialcapital.ie>',
                 'to',      to_addr,
                 'subject', subject,
                 'html',    body_html
               )
  );

  return new;
end $$;

revoke all on function public.notify_new_submission() from public, anon, authenticated;


-- 4. Fire it on every new submission.
drop trigger if exists trg_notify_new_school on public.pending_schools;
create trigger trg_notify_new_school
  after insert on public.pending_schools
  for each row execute function public.notify_new_submission();

drop trigger if exists trg_notify_new_mentor on public.pending_mentors;
create trigger trg_notify_new_mentor
  after insert on public.pending_mentors
  for each row execute function public.notify_new_submission();


-- ===========================================================================
-- TESTING AND TROUBLESHOOTING
-- ===========================================================================
-- Send yourself a test alert:
--
--   insert into public.pending_schools (school_name, contact_name, email, county)
--   values ('ZZ NOTIFY TEST', 'Test', 'zz@example.invalid', 'Dublin');
--
--   delete from public.pending_schools where school_name = 'ZZ NOTIFY TEST';
--
-- If no email arrives, look at what Resend said back. 200 means sent:
--
--   select id, status_code, content, created
--     from net._http_response
--    order by created desc
--    limit 5;
-- ===========================================================================
