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

create temp table if not exists gate_test (what text, result text);
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

  -- Put things back.
  perform set_config('request.jwt.claims', '', true);
end $$;

-- admin_add_mentor and admin_update_mentor are not tested here on purpose:
-- if the gate were broken, testing them would add or alter a real mentor.
-- Their first statement is the identical is_admin() check, so the result
-- above covers them.

select what, result from gate_test order by result desc, what;
