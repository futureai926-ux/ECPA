-- Carry-over subjects (تەکەبە) and dropped subjects (Cancel/...).
--   kind = 'carry': the student also attends this subject (usually of another stage) with group `section`.
--   kind = 'drop' : the student does not take this subject of their own stage this year.
create table if not exists public.ecpa_enrollments (
  student_id uuid not null references public.ecpa_students(id) on delete cascade,
  subject_id uuid not null references public.ecpa_subjects(id) on delete cascade,
  kind text not null check (kind in ('carry', 'drop')),
  section text not null,
  created_at timestamptz not null default now(),
  primary key (student_id, subject_id)
);
create index if not exists ecpa_enrollments_subject on public.ecpa_enrollments (subject_id, section);
alter table public.ecpa_enrollments enable row level security;

-- teachers see the carry-over students of the classes they teach
create or replace function private.ecpa_teaches_carry(p_student uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.ecpa_enrollments e
                 join public.ecpa_assignments a on a.subject_id = e.subject_id and a.section = e.section
                 where e.student_id = p_student and e.kind = 'carry' and a.teacher_id = (select auth.uid()));
$$;
revoke all on function private.ecpa_teaches_carry(uuid) from public;
grant execute on function private.ecpa_teaches_carry(uuid) to authenticated;

create policy "admin/head or own subject enrollments" on public.ecpa_enrollments for select to authenticated
  using ((select private.ecpa_can_view_all()) or private.ecpa_teaches_subject(subject_id));
create policy "admin writes enrollments" on public.ecpa_enrollments for all to authenticated
  using ((select private.ecpa_is_admin())) with check ((select private.ecpa_is_admin()));

alter policy "admin/head or own class students" on public.ecpa_students
  using ((select private.ecpa_can_view_all()) or private.ecpa_teaches_student(stage, section) or private.ecpa_teaches_carry(id));

alter publication supabase_realtime add table public.ecpa_enrollments;
