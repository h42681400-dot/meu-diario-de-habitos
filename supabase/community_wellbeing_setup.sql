-- Cottontail — Etapa 2: desafios coletivos e comunidades
-- Execute este arquivo uma única vez no Supabase SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.wellness_challenges (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 3 and 90),
  description text not null default '',
  category text not null default 'Bem-estar',
  goal_value numeric not null default 7 check (goal_value > 0),
  goal_unit text not null default 'dias',
  duration_days integer not null default 7 check (duration_days between 1 and 90),
  starts_on date not null default current_date,
  ends_on date not null,
  created_by uuid not null references auth.users(id) on delete cascade,
  is_public boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists wellness_challenges_created_idx on public.wellness_challenges(created_at desc);

create table if not exists public.wellness_challenge_members (
  challenge_id uuid not null references public.wellness_challenges(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  progress numeric not null default 0 check (progress >= 0),
  joined_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  primary key (challenge_id,user_id)
);
create index if not exists wellness_challenge_members_user_idx on public.wellness_challenge_members(user_id);

create table if not exists public.wellness_communities (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 3 and 60),
  description text not null default '',
  category text not null default 'Bem-estar',
  created_by uuid not null references auth.users(id) on delete cascade,
  is_private boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists wellness_communities_created_idx on public.wellness_communities(created_at desc);

create table if not exists public.wellness_community_members (
  community_id uuid not null references public.wellness_communities(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','member')),
  joined_at timestamptz not null default now(),
  primary key (community_id,user_id)
);
create index if not exists wellness_community_members_user_idx on public.wellness_community_members(user_id);

create table if not exists public.wellness_community_posts (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.wellness_communities(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  content text not null check (char_length(content) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists wellness_community_posts_feed_idx on public.wellness_community_posts(community_id,created_at desc);

alter table public.wellness_challenges enable row level security;
alter table public.wellness_challenge_members enable row level security;
alter table public.wellness_communities enable row level security;
alter table public.wellness_community_members enable row level security;
alter table public.wellness_community_posts enable row level security;

drop policy if exists "cottontail_challenges_read_public" on public.wellness_challenges;
create policy "cottontail_challenges_read_public" on public.wellness_challenges for select to authenticated using (is_public or created_by = auth.uid());
drop policy if exists "cottontail_challenges_create_own" on public.wellness_challenges;
create policy "cottontail_challenges_create_own" on public.wellness_challenges for insert to authenticated with check (created_by = auth.uid());
drop policy if exists "cottontail_challenges_update_own" on public.wellness_challenges;
create policy "cottontail_challenges_update_own" on public.wellness_challenges for update to authenticated using (created_by = auth.uid()) with check (created_by = auth.uid());
drop policy if exists "cottontail_challenge_members_read" on public.wellness_challenge_members;
create policy "cottontail_challenge_members_read" on public.wellness_challenge_members for select to authenticated using (exists (select 1 from public.wellness_challenges c where c.id = challenge_id and (c.is_public or c.created_by = auth.uid())) or user_id = auth.uid());
drop policy if exists "cottontail_challenge_members_join_self" on public.wellness_challenge_members;
create policy "cottontail_challenge_members_join_self" on public.wellness_challenge_members for insert to authenticated with check (user_id = auth.uid() and exists (select 1 from public.wellness_challenges c where c.id = wellness_challenge_members.challenge_id and c.is_public));
drop policy if exists "cottontail_challenge_members_update_self" on public.wellness_challenge_members;
create policy "cottontail_challenge_members_update_self" on public.wellness_challenge_members for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "cottontail_challenge_members_leave_self" on public.wellness_challenge_members;
create policy "cottontail_challenge_members_leave_self" on public.wellness_challenge_members for delete to authenticated using (user_id = auth.uid());

drop policy if exists "cottontail_communities_read_public" on public.wellness_communities;
create policy "cottontail_communities_read_public" on public.wellness_communities for select to authenticated using (not is_private or created_by = auth.uid());
drop policy if exists "cottontail_communities_create_own" on public.wellness_communities;
create policy "cottontail_communities_create_own" on public.wellness_communities for insert to authenticated with check (created_by = auth.uid());
drop policy if exists "cottontail_communities_update_own" on public.wellness_communities;
create policy "cottontail_communities_update_own" on public.wellness_communities for update to authenticated using (created_by = auth.uid()) with check (created_by = auth.uid());

drop policy if exists "cottontail_community_members_read" on public.wellness_community_members;
create policy "cottontail_community_members_read" on public.wellness_community_members for select to authenticated using (user_id = auth.uid() or exists (select 1 from public.wellness_communities c where c.id = wellness_community_members.community_id and not c.is_private));
drop policy if exists "cottontail_community_members_join_public" on public.wellness_community_members;
create policy "cottontail_community_members_join_public" on public.wellness_community_members for insert to authenticated with check (user_id = auth.uid() and exists (select 1 from public.wellness_communities c where c.id = community_id and not c.is_private));
drop policy if exists "cottontail_community_members_leave_self" on public.wellness_community_members;
create policy "cottontail_community_members_leave_self" on public.wellness_community_members for delete to authenticated using (user_id = auth.uid());

drop policy if exists "cottontail_community_posts_read_members" on public.wellness_community_posts;
create policy "cottontail_community_posts_read_members" on public.wellness_community_posts for select to authenticated using (exists (select 1 from public.wellness_community_members m where m.community_id = wellness_community_posts.community_id and m.user_id = auth.uid()));
drop policy if exists "cottontail_community_posts_create_members" on public.wellness_community_posts;
create policy "cottontail_community_posts_create_members" on public.wellness_community_posts for insert to authenticated with check (user_id = auth.uid() and exists (select 1 from public.wellness_community_members m where m.community_id = wellness_community_posts.community_id and m.user_id = auth.uid()));
drop policy if exists "cottontail_community_posts_delete_own" on public.wellness_community_posts;
create policy "cottontail_community_posts_delete_own" on public.wellness_community_posts for delete to authenticated using (user_id = auth.uid());

grant select,insert,update,delete on public.wellness_challenges to authenticated;
grant select,insert,update,delete on public.wellness_challenge_members to authenticated;
grant select,insert,update,delete on public.wellness_communities to authenticated;
grant select,insert,update,delete on public.wellness_community_members to authenticated;
grant select,insert,update,delete on public.wellness_community_posts to authenticated;


-- Cottontail — Etapa 4: preferências de notificações
-- Execute este arquivo no SQL Editor do Supabase.
-- Liga notificações aos recursos coletivos para permitir abrir o destino correto.
alter table public.notifications add column if not exists challenge_id uuid references public.wellness_challenges(id) on delete cascade;
alter table public.notifications add column if not exists community_id uuid references public.wellness_communities(id) on delete cascade;
create index if not exists notifications_challenge_id_idx on public.notifications(challenge_id) where challenge_id is not null;
create index if not exists notifications_community_id_idx on public.notifications(community_id) where community_id is not null;

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


-- A preferência é aplicada no próprio banco antes do INSERT.
-- Assim, o webhook de push só recebe notificações permitidas, sem expor
-- as preferências privadas de outros usuários ao cliente.
create or replace function public.cottontail_filter_notification_preferences()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  preference_column text;
  preference_enabled boolean;
begin
  preference_column := case new.type
    when 'like' then 'likes'
    when 'comment' then 'comments'
    when 'repost' then 'reposts'
    when 'follow' then 'follows'
    when 'message' then 'messages'
    when 'post_collaboration' then 'collaborations'
    when 'challenge_join' then 'challenges'
    when 'challenge_complete' then 'challenges'
    when 'challenge_update' then 'challenges'
    when 'community_join' then 'communities'
    when 'community_post' then 'communities'
    else null
  end;

  if preference_column is null then
    return new;
  end if;

  execute format(
    'select %I from public.user_notification_preferences where user_id = $1',
    preference_column
  ) into preference_enabled using new.user_id;

  if preference_enabled is false then
    return null;
  end if;
  return new;
end;
$$;

drop trigger if exists cottontail_notification_preferences_before_insert on public.notifications;
create trigger cottontail_notification_preferences_before_insert
before insert on public.notifications
for each row execute function public.cottontail_filter_notification_preferences();
