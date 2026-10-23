-- head of department: reads every stage, subject, student and report; records attendance only for own classes; changes nothing else
alter table public.ecpa_profiles drop constraint if exists ecpa_profiles_role_check;
alter table public.ecpa_profiles add constraint ecpa_profiles_role_check check (role in ('admin','head','teacher'));

create or replace function private.ecpa_can_view_all() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.ecpa_profiles where id = (select auth.uid()) and role in ('admin','head'));
$$;
revoke all on function private.ecpa_can_view_all() from public;
grant execute on function private.ecpa_can_view_all() to authenticated;

drop policy "own profile or admin" on public.ecpa_profiles;
create policy "own profile or admin/head" on public.ecpa_profiles for select to authenticated
  using (id = (select auth.uid()) or (select private.ecpa_can_view_all()));

drop policy "admin or assigned subject" on public.ecpa_subjects;
create policy "admin/head or assigned subject" on public.ecpa_subjects for select to authenticated
  using ((select private.ecpa_can_view_all()) or private.ecpa_teaches_subject(id));

drop policy "admin or own class students" on public.ecpa_students;
create policy "admin/head or own class students" on public.ecpa_students for select to authenticated
  using ((select private.ecpa_can_view_all()) or private.ecpa_teaches_student(stage, section));

drop policy "admin or own assignments" on public.ecpa_assignments;
create policy "admin/head or own assignments" on public.ecpa_assignments for select to authenticated
  using ((select private.ecpa_can_view_all()) or teacher_id = (select auth.uid()));

drop policy "read own class sessions" on public.ecpa_sessions;
create policy "admin/head or own class sessions" on public.ecpa_sessions for select to authenticated
  using ((select private.ecpa_can_view_all()) or private.ecpa_teaches(subject_id, section));
-- insert/update/delete on sessions stay: admin, or a teacher/head of that class

-- the admin may switch someone between teacher and head (the "admin renames" update policy keeps this admin-only)
grant update (full_name, role) on public.ecpa_profiles to authenticated;

update public.ecpa_profiles set role = 'head' where email = 'karzan@ecpa.local';
