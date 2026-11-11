-- Cottontail — Etapa 4: preferências de notificações
-- Execute este arquivo no SQL Editor do Supabase.
create table if not exists public.user_notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  likes boolean not null default true,
  comments boolean not null default true,
  reposts boolean not null default true,
  follows boolean not null default true,
  messages boolean not null default true,
  collaborations boolean not null default true,
  challenges boolean not null default true,
  communities boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.user_notification_preferences enable row level security;
drop policy if exists "cottontail_notification_preferences_read_own" on public.user_notification_preferences;
create policy "cottontail_notification_preferences_read_own" on public.user_notification_preferences for select to authenticated using (user_id = auth.uid());
drop policy if exists "cottontail_notification_preferences_insert_own" on public.user_notification_preferences;
create policy "cottontail_notification_preferences_insert_own" on public.user_notification_preferences for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "cottontail_notification_preferences_update_own" on public.user_notification_preferences;
create policy "cottontail_notification_preferences_update_own" on public.user_notification_preferences for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select,insert,update on public.user_notification_preferences to authenticated;
