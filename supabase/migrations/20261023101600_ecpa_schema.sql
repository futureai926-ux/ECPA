-- ECPA attendance register — database schema (already applied to the Supabase project).
-- Tables are prefixed ecpa_ so they can live next to older tables in the same project.

create schema if not exists private;
grant usage on schema private to authenticated;

-- settings (one row)
create table public.ecpa_settings (
  id smallint primary key default 1 check (id = 1),
  unit text not null default '',
  year text not null default '2026-2027' check (year ~ '^[0-9]{4}-[0-9]{4}$'),
  sections text[] not null default array['A','B'],
  warn1 numeric not null default 5 check (warn1 > 0 and warn1 <= 100),
  warn2 numeric not null default 8 check (warn2 > 0 and warn2 <= 100),
  fail numeric not null default 10 check (fail > 0 and fail <= 100),
  fail_total numeric not null default 15 check (fail_total > 0 and fail_total <= 100),
  updated_at timestamptz not null default now()
);
insert into public.ecpa_settings (id) values (1);

-- people who can sign in to the register
create table public.ecpa_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text,
  role text not null check (role in ('admin','teacher')),
  created_at timestamptz not null default now()
);

create table public.ecpa_subjects (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) > 0),
  stage smallint not null check (stage between 1 and 4),
  total integer not null default 30 check (total between 1 and 300),
  sort integer not null default 0,
  created_at timestamptz not null default now()
);

create table public.ecpa_students (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) > 0),
  code text not null default '',
  stage smallint not null check (stage between 1 and 5),   -- 5 = graduated
  section text not null,
  grad_year text,
  created_at timestamptz not null default now()
);
create index ecpa_students_stage_section on public.ecpa_students (stage, section);

-- one teacher per subject + section
create table public.ecpa_assignments (
  subject_id uuid not null references public.ecpa_subjects(id) on delete cascade,
  section text not null,
  teacher_id uuid not null references public.ecpa_profiles(id) on delete cascade,
  primary key (subject_id, section)
);
create index ecpa_assignments_teacher on public.ecpa_assignments (teacher_id);

-- one row per class session; marks = {student_id: p|a|l|e}
create table public.ecpa_sessions (
  year text not null,
  subject_id uuid not null references public.ecpa_subjects(id) on delete cascade,
  section text not null,
  date date not null,
  marks jsonb not null default '{}'::jsonb check (
    jsonb_typeof(marks) = 'object'
    and not jsonb_path_exists(marks, '$.* ? (@ != "p" && @ != "a" && @ != "l" && @ != "e")')
  ),
  recorded_by uuid references public.ecpa_profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (year, subject_id, section, date)
);
create index ecpa_sessions_class on public.ecpa_sessions (subject_id, section);

create or replace function private.ecpa_stamp() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.recorded_by := (select auth.uid());
  new.updated_at := now();
  return new;
end $$;
create trigger ecpa_sessions_stamp before insert or update on public.ecpa_sessions
  for each row execute function private.ecpa_stamp();

-- access helpers (private schema: not callable through the API)
create or replace function private.ecpa_is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.ecpa_profiles where id = (select auth.uid()) and role = 'admin');
$$;
create or replace function private.ecpa_teaches(p_subject uuid, p_section text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.ecpa_assignments
                 where teacher_id = (select auth.uid()) and subject_id = p_subject and section = p_section);
$$;
create or replace function private.ecpa_teaches_subject(p_subject uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.ecpa_assignments
                 where teacher_id = (select auth.uid()) and subject_id = p_subject);
$$;
create or replace function private.ecpa_teaches_student(p_stage smallint, p_section text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.ecpa_assignments a
                 join public.ecpa_subjects s on s.id = a.subject_id
                 where a.teacher_id = (select auth.uid()) and a.section = p_section and s.stage = p_stage);
$$;
revoke all on function private.ecpa_stamp() from public;
revoke all on function private.ecpa_is_admin(), private.ecpa_teaches(uuid,text),
  private.ecpa_teaches_subject(uuid), private.ecpa_teaches_student(smallint,text) from public;
grant execute on function private.ecpa_is_admin(), private.ecpa_teaches(uuid,text),
  private.ecpa_teaches_subject(uuid), private.ecpa_teaches_student(smallint,text) to authenticated;

-- row level security
alter table public.ecpa_settings enable row level security;
alter table public.ecpa_profiles enable row level security;
alter table public.ecpa_subjects enable row level security;
alter table public.ecpa_students enable row level security;
alter table public.ecpa_assignments enable row level security;
alter table public.ecpa_sessions enable row level security;

revoke all on public.ecpa_settings, public.ecpa_profiles, public.ecpa_subjects,
  public.ecpa_students, public.ecpa_assignments, public.ecpa_sessions from anon;
revoke truncate, references, trigger on public.ecpa_settings, public.ecpa_profiles, public.ecpa_subjects,
  public.ecpa_students, public.ecpa_assignments, public.ecpa_sessions from authenticated;
revoke insert, delete on public.ecpa_settings from authenticated;

create policy "read settings" on public.ecpa_settings for select to authenticated
  using ((select private.ecpa_is_admin()) or exists (select 1 from public.ecpa_profiles where id = (select auth.uid())));
create policy "admin edits settings" on public.ecpa_settings for update to authenticated
  using ((select private.ecpa_is_admin())) with check ((select private.ecpa_is_admin()));

create policy "own profile or admin" on public.ecpa_profiles for select to authenticated
  using (id = (select auth.uid()) or (select private.ecpa_is_admin()));
create policy "admin renames" on public.ecpa_profiles for update to authenticated
  using ((select private.ecpa_is_admin())) with check ((select private.ecpa_is_admin()));
revoke insert, update, delete on public.ecpa_profiles from authenticated;
grant update (full_name) on public.ecpa_profiles to authenticated;

create policy "admin or assigned subject" on public.ecpa_subjects for select to authenticated
  using ((select private.ecpa_is_admin()) or private.ecpa_teaches_subject(id));
create policy "admin writes subjects" on public.ecpa_subjects for all to authenticated
  using ((select private.ecpa_is_admin())) with check ((select private.ecpa_is_admin()));

create policy "admin or own class students" on public.ecpa_students for select to authenticated
  using ((select private.ecpa_is_admin()) or private.ecpa_teaches_student(stage, section));
create policy "admin writes students" on public.ecpa_students for all to authenticated
  using ((select private.ecpa_is_admin())) with check ((select private.ecpa_is_admin()));

create policy "admin or own assignments" on public.ecpa_assignments for select to authenticated
  using ((select private.ecpa_is_admin()) or teacher_id = (select auth.uid()));
create policy "admin writes assignments" on public.ecpa_assignments for all to authenticated
  using ((select private.ecpa_is_admin())) with check ((select private.ecpa_is_admin()));

create policy "read own class sessions" on public.ecpa_sessions for select to authenticated
  using ((select private.ecpa_is_admin()) or private.ecpa_teaches(subject_id, section));
create policy "record own class sessions" on public.ecpa_sessions for insert to authenticated
  with check ((select private.ecpa_is_admin()) or private.ecpa_teaches(subject_id, section));
create policy "edit own class sessions" on public.ecpa_sessions for update to authenticated
  using ((select private.ecpa_is_admin()) or private.ecpa_teaches(subject_id, section))
  with check ((select private.ecpa_is_admin()) or private.ecpa_teaches(subject_id, section));
create policy "delete own class sessions" on public.ecpa_sessions for delete to authenticated
  using ((select private.ecpa_is_admin()) or private.ecpa_teaches(subject_id, section));

-- live updates
alter publication supabase_realtime add table public.ecpa_settings, public.ecpa_subjects,
  public.ecpa_students, public.ecpa_assignments, public.ecpa_sessions, public.ecpa_profiles;

-- the admin account (an existing Supabase Auth user) — put the admin's email in place of ADMIN_EMAIL
insert into public.ecpa_profiles (id, full_name, email, role)
select id, '', email, 'admin' from auth.users where lower(email) = lower('ADMIN_EMAIL');
