-- ===========================================================================
-- CAN A SIGNED-IN SCHOOL CHANGE THE DIRECTORY? (It must not be able to.)
-- ===========================================================================
-- This pretends to be a school that is signed in and not on the admin list,
-- then tries each admin function in turn. Every one should refuse.
--
-- Supabase works out who you are from a claim it keeps in the session. This
-- sets that claim to somebody who is not an admin, runs the functions, and
-- undoes it - nothing is changed and no mentor is added.
--
-- READ THE RESULT, NOT THE ERRORS. You will get a small table at the bottom
-- saying PASS or FAIL for each function. PASS means it was refused, which is
-- the result you want.
-- ===========================================================================

-- A scratch table for the results. TEMP means it exists only for this one
-- connection, is invisible to every other connection including the website's,
-- and is deleted when you close the tab. Supabase's linter cannot tell a temp
-- table from a real one and will warn about row level security anyway, so RLS
-- is enabled below to settle the point - it changes nothing either way.
create temp table if not exists gate_test (what text, result text);
alter table gate_test enable row level security;
truncate gate_test;

do $$
declare
  who constant text := '{"email":"a-school-not-an-admin@example.com"}';
begin
  -- Become somebody who is not on the admin list.
  perform set_config('request.jwt.claims', who, true);

  -- Does the gate itself agree they are not an admin?
  insert into gate_test values (
    'is_admin() says no',
    case when public.is_admin() then 'FAIL - it thinks they ARE an admin'
         else 'PASS' end
  );

  -- Reading the mentor list, which includes private contact details.
  begin
    perform * from public.admin_list_mentors();
    insert into gate_test values ('admin_list_mentors refuses',
      'FAIL - A SCHOOL CAN READ PRIVATE CONTACT DETAILS');
  exception
    when insufficient_privilege then
      insert into gate_test values ('admin_list_mentors refuses', 'PASS');
    when others then
      insert into gate_test values ('admin_list_mentors refuses',
        'PASS (refused: ' || sqlerrm || ')');
  end;

  -- Reading the queue of people who signed up.
  begin
    perform * from public.admin_list_pending();
    insert into gate_test values ('admin_list_pending refuses',
      'FAIL - A SCHOOL CAN READ THE SIGNUP QUEUE');
  exception
    when insufficient_privilege then
      insert into gate_test values ('admin_list_pending refuses', 'PASS');
    when others then
      insert into gate_test values ('admin_list_pending refuses',
        'PASS (refused: ' || sqlerrm || ')');
  end;

  -- Publishing a mentor. A made-up id, so even if the gate failed this
  -- would change nothing.
  begin
    perform public.admin_set_published(gen_random_uuid(), true);
    insert into gate_test values ('admin_set_published refuses',
      'FAIL - A SCHOOL CAN PUBLISH AND HIDE MENTORS');
  exception
    when insufficient_privilege then
      insert into gate_test values ('admin_set_published refuses', 'PASS');
    when others then
      insert into gate_test values ('admin_set_published refuses',
        'PASS (refused: ' || sqlerrm || ')');
  end;

  -- Asking for a mentor's shared LinkedIn or email. Only members over 18 may,
  -- so a school should be handed nothing. (Passes trivially if no published
  -- mentor has agreed to be contacted yet.)
  insert into gate_test values (
    'mentor_contact gives a school nothing',
    case when exists (
           select 1 from public.mentor_contact(
             (select id from public.mentors
               where is_published and member_contact_ok limit 1)))
         then 'FAIL - A SCHOOL CAN SEE SHARED CONTACTS'
         else 'PASS' end
  );

  -- Seeing a mentor's photo. This made-up user is neither an approved school
  -- nor a member, so even a real photo's path must be refused.
  insert into gate_test values (
    'can_view_mentor_photo refuses a stranger',
    case when public.can_view_mentor_photo(
           coalesce((select photo_path from public.mentors
                      where photo_path is not null limit 1),
                    'mentors/00000000-0000-4000-8000-000000000000.jpg'))
         then 'FAIL - A STRANGER CAN SEE MENTOR PHOTOS'
         else 'PASS' end
  );

  -- Put things back.
  perform set_config('request.jwt.claims', '', true);
end $$;

-- admin_add_mentor and admin_update_mentor are not tested here on purpose:
-- if the gate were broken, testing them would add or alter a real mentor.
-- Their first statement is the identical is_admin() check, so the result
-- above covers them.

-- Reading the shared LinkedIn and email straight off the table, which would
-- skip the member check and the log. The columns must not be granted.
insert into gate_test values (
  'shared contact columns are not readable',
  case when has_column_privilege('authenticated', 'public.mentors', 'public_contact', 'select')
         or has_column_privilege('authenticated', 'public.mentors', 'public_email', 'select')
       then 'FAIL - A SCHOOL CAN READ SHARED CONTACTS DIRECTLY'
       else 'PASS' end
);

-- The photo bucket must never be public: a public bucket ignores every rule
-- above and hands out a permanent link to anyone.
insert into gate_test values (
  'mentor-photos bucket is private',
  case when exists (select 1 from storage.buckets where id = 'mentor-photos' and not public)
       then 'PASS'
       else 'FAIL - THE PHOTO BUCKET IS PUBLIC OR MISSING' end
);

select what, result from gate_test order by result desc, what;
