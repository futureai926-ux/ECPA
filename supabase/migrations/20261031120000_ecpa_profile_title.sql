-- A title shown instead of the role name. 'rapporteur' (بڕیاردەری بەش) has exactly the head-of-department
-- permissions (role = 'head'); only the label differs.
alter table public.ecpa_profiles add column if not exists title text;
alter table public.ecpa_profiles add constraint ecpa_profiles_title_check check (title is null or title in ('rapporteur'));
grant update (title) on public.ecpa_profiles to authenticated;

update public.ecpa_profiles set role = 'head', title = 'rapporteur' where email = 'avan@ecpa.local';
