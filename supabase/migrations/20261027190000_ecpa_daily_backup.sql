-- Daily backup to Telegram: the ecpa-backup Edge Function is called every night at 23:00 Baghdad time (20:00 UTC).
create extension if not exists pg_net;
create extension if not exists pg_cron;

-- one row: which Telegram chat receives the backup, and the key the nightly job uses to call the function
create table if not exists public.ecpa_backup_config (
  id smallint primary key default 1 check (id = 1),
  chat_id bigint,
  chat_name text,
  cron_key text not null default encode(extensions.gen_random_bytes(24), 'hex'),
  updated_at timestamptz not null default now()
);
alter table public.ecpa_backup_config enable row level security;
-- no policies on purpose: only the Edge Function (service role) and the database itself can read it
revoke all on public.ecpa_backup_config from anon, authenticated;
insert into public.ecpa_backup_config (id) values (1) on conflict (id) do nothing;

-- a log of every backup, readable by the admin
create table if not exists public.ecpa_backups (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  trigger text not null check (trigger in ('cron', 'manual')),
  ok boolean not null,
  detail text,
  counts jsonb
);
alter table public.ecpa_backups enable row level security;
create policy "admin reads backups" on public.ecpa_backups for select to authenticated
  using ((select private.ecpa_is_admin()));
revoke insert, update, delete, truncate on public.ecpa_backups from anon, authenticated;

select cron.schedule('ecpa-daily-backup', '0 20 * * *', $job$
  select net.http_post(
    url := 'https://tuzurgxqhcjdnnqydamu.supabase.co/functions/v1/ecpa-backup',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-ecpa-key', (select cron_key from public.ecpa_backup_config where id = 1)),
    body := '{"action":"run"}'::jsonb,
    timeout_milliseconds := 60000
  );
$job$);
