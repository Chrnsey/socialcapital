-- ===========================================================================
-- DID IT ALL LAND? Run this and read the "status" column.
-- Everything should say ok. Anything saying MISSING did not get created.
-- ===========================================================================

with expected(name) as (
  values ('is_admin'),
         ('add_mentor'),
         ('admin_add_mentor'),
         ('admin_list_mentors'),
         ('admin_set_published'),
         ('admin_update_mentor'),
         ('admin_list_pending'),
         ('admin_approve_mentor'),
         ('admin_approve_school'),
         ('admin_reject_pending')
)
select e.name as thing,
       case when p.proname is null then 'MISSING' else 'ok' end as status
  from expected e
  left join pg_proc p
    on p.proname = e.name
   and p.pronamespace = 'public'::regnamespace

union all
select 'TABLE admins',
       case when to_regclass('public.admins') is null then 'MISSING' else 'ok' end

union all
select 'admin on the list: ' || a.email,
       case when a.is_active then 'ok' else 'INACTIVE' end
  from public.admins a

order by status, thing;
