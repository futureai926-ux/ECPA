-- A class (subject + section) can have more than one teacher.
alter table public.ecpa_assignments drop constraint ecpa_assignments_pkey;
alter table public.ecpa_assignments add primary key (subject_id, section, teacher_id);
create index if not exists ecpa_assignments_class on public.ecpa_assignments (subject_id, section);
