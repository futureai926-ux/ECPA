-- Restore from a backup file (the ECPA-backup-YYYY-MM-DD.json sent to Telegram).
-- Everything in the file comes back in one transaction: settings, subjects, students, teacher names and roles,
-- class assignments and attendance. Records added after the backup are kept. Only the admin may call it.

-- keep the original recorder and time when restoring sessions
create or replace function private.ecpa_stamp() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(current_setting('ecpa.restoring', true), '') = 'on' then
    return new;
  end if;
  new.recorded_by := (select auth.uid());
  new.updated_at := now();
  return new;
end $$;

create or replace function public.ecpa_restore(backup jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  t jsonb := backup -> 'tables';
  s jsonb;
  n_sub int := 0; n_stu int := 0; n_ses int := 0; n_asg int := 0; n_prof int := 0; n_skip int := 0;
begin
  if not (select private.ecpa_is_admin()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if coalesce(backup ->> 'app', '') <> 'ECPA' or jsonb_typeof(t) is distinct from 'object' then
    raise exception 'not_a_backup' using errcode = '22023';
  end if;
  perform set_config('ecpa.restoring', 'on', true);

  s := t -> 'ecpa_settings' -> 0;
  if jsonb_typeof(s) = 'object' then
    update public.ecpa_settings set
      unit       = coalesce(s ->> 'unit', unit),
      year       = coalesce(s ->> 'year', year),
      sections   = case when jsonb_typeof(s -> 'sections') = 'array' and jsonb_array_length(s -> 'sections') > 0
                        then array(select jsonb_array_elements_text(s -> 'sections')) else sections end,
      warn1      = coalesce((s ->> 'warn1')::numeric, warn1),
      warn2      = coalesce((s ->> 'warn2')::numeric, warn2),
      fail       = coalesce((s ->> 'fail')::numeric, fail),
      fail_total = coalesce((s ->> 'fail_total')::numeric, fail_total),
      updated_at = now()
    where id = 1;
  end if;

  insert into public.ecpa_subjects (id, name, stage, total, sort, created_at)
  select r.id, r.name, r.stage, coalesce(r.total, 30), coalesce(r.sort, 0), coalesce(r.created_at, now())
  from jsonb_populate_recordset(null::public.ecpa_subjects, coalesce(t -> 'ecpa_subjects', '[]')) r
  where r.id is not null
  on conflict (id) do update set name = excluded.name, stage = excluded.stage, total = excluded.total, sort = excluded.sort;
  get diagnostics n_sub = row_count;

  insert into public.ecpa_students (id, name, code, stage, section, grad_year, created_at)
  select r.id, r.name, coalesce(r.code, ''), r.stage, r.section, r.grad_year, coalesce(r.created_at, now())
  from jsonb_populate_recordset(null::public.ecpa_students, coalesce(t -> 'ecpa_students', '[]')) r
  where r.id is not null
  on conflict (id) do update set name = excluded.name, code = excluded.code, stage = excluded.stage,
    section = excluded.section, grad_year = excluded.grad_year;
  get diagnostics n_stu = row_count;

  -- teacher accounts themselves (usernames and passwords) live in Supabase Auth and are not in the file;
  -- names and roles are restored for the accounts that still exist
  update public.ecpa_profiles p set full_name = r.full_name, role = r.role
  from jsonb_populate_recordset(null::public.ecpa_profiles, coalesce(t -> 'ecpa_profiles', '[]')) r
  where p.id = r.id and p.role <> 'admin' and r.role in ('teacher', 'head') and r.full_name is not null
    and (p.full_name is distinct from r.full_name or p.role is distinct from r.role);
  get diagnostics n_prof = row_count;

  select count(*) into n_skip
  from jsonb_populate_recordset(null::public.ecpa_assignments, coalesce(t -> 'ecpa_assignments', '[]')) r
  where not exists (select 1 from public.ecpa_profiles p where p.id = r.teacher_id);

  insert into public.ecpa_assignments (subject_id, section, teacher_id)
  select r.subject_id, r.section, r.teacher_id
  from jsonb_populate_recordset(null::public.ecpa_assignments, coalesce(t -> 'ecpa_assignments', '[]')) r
  where exists (select 1 from public.ecpa_profiles p where p.id = r.teacher_id)
    and exists (select 1 from public.ecpa_subjects x where x.id = r.subject_id)
  on conflict do nothing;
  get diagnostics n_asg = row_count;

  insert into public.ecpa_sessions (year, subject_id, section, date, marks, recorded_by, updated_at)
  select r.year, r.subject_id, r.section, r.date, coalesce(r.marks, '{}'::jsonb),
         case when exists (select 1 from public.ecpa_profiles p where p.id = r.recorded_by) then r.recorded_by end,
         coalesce(r.updated_at, now())
  from jsonb_populate_recordset(null::public.ecpa_sessions, coalesce(t -> 'ecpa_sessions', '[]')) r
  where exists (select 1 from public.ecpa_subjects x where x.id = r.subject_id)
  on conflict (year, subject_id, section, date) do update set marks = excluded.marks,
    recorded_by = coalesce(excluded.recorded_by, public.ecpa_sessions.recorded_by), updated_at = excluded.updated_at;
  get diagnostics n_ses = row_count;

  perform set_config('ecpa.restoring', 'off', true);
  return jsonb_build_object('subjects', n_sub, 'students', n_stu, 'sessions', n_ses, 'assignments_added', n_asg,
                            'teachers_updated', n_prof, 'assignments_skipped', n_skip, 'backup_date', backup ->> 'created_at');
end $$;
revoke all on function public.ecpa_restore(jsonb) from public, anon;
grant execute on function public.ecpa_restore(jsonb) to authenticated;
