-- The Telegram bot token is kept encrypted in Supabase Vault (secret name: ecpa_telegram_bot_token),
-- added once with: select vault.create_secret('<bot token>', 'ecpa_telegram_bot_token');
-- Only the Edge Function (service role) can read it.
create or replace function public.ecpa_backup_token() returns text
language sql stable security definer set search_path = '' as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'ecpa_telegram_bot_token' order by created_at desc limit 1;
$$;
revoke all on function public.ecpa_backup_token() from public, anon, authenticated;
grant execute on function public.ecpa_backup_token() to service_role;
