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
create policy "cottontail_challenge_members_join_self" on public.wellness_challenge_members for insert to authenticated with check (user_id = auth.uid());
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
