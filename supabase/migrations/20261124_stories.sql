-- Cottontail Stories: execute uma vez no Supabase SQL Editor.
create table if not exists public.stories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  media_path text,
  media_type text not null default 'text' check (media_type in ('image','video','text')),
  text_overlay text,
  filter_name text not null default 'none' check (filter_name in ('none','warm','cool','bw','dream')),
  music_path text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  constraint story_has_content check (media_path is not null or nullif(trim(text_overlay),'') is not null)
);
create index if not exists stories_user_expiry_idx on public.stories(user_id, expires_at desc);
create table if not exists public.story_views (
  story_id uuid not null references public.stories(id) on delete cascade,
  viewer_id uuid not null references auth.users(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key(story_id, viewer_id)
);
alter table public.stories enable row level security;
alter table public.story_views enable row level security;
drop policy if exists "Stories readable by owner and followed users" on public.stories;
create policy "Stories readable by owner and followed users" on public.stories for select to authenticated using (
  user_id = auth.uid() or exists (select 1 from public.follows f where f.follower_id = auth.uid() and f.following_id = stories.user_id)
);
drop policy if exists "Users create own stories" on public.stories;
create policy "Users create own stories" on public.stories for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "Users delete own stories" on public.stories;
create policy "Users delete own stories" on public.stories for delete to authenticated using (user_id = auth.uid());
drop policy if exists "Users read story views for visible stories" on public.story_views;
create policy "Users read story views for visible stories" on public.story_views for select to authenticated using (
  viewer_id = auth.uid() or exists (select 1 from public.stories s where s.id = story_views.story_id and s.user_id = auth.uid())
);
drop policy if exists "Users mark own story views" on public.story_views;
create policy "Users mark own story views" on public.story_views for insert to authenticated with check (viewer_id = auth.uid());
drop policy if exists "Users update own story views" on public.story_views;
create policy "Users update own story views" on public.story_views for update to authenticated using (viewer_id = auth.uid()) with check (viewer_id = auth.uid());
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('stories','stories',false,36700160,array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm','video/quicktime','audio/mpeg','audio/mp4','audio/aac','audio/wav','audio/ogg'])
on conflict (id) do update set public=false,file_size_limit=36700160,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists "Story owners upload media" on storage.objects;
create policy "Story owners upload media" on storage.objects for insert to authenticated with check (bucket_id='stories' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Story owners and followers read media" on storage.objects;
create policy "Story owners and followers read media" on storage.objects for select to authenticated using (
 bucket_id='stories' and (
  (storage.foldername(name))[1]=auth.uid()::text or
  exists (select 1 from public.follows f where f.follower_id=auth.uid() and f.following_id=((storage.foldername(name))[1])::uuid)
 )
);
drop policy if exists "Story owners delete media" on storage.objects;
create policy "Story owners delete media" on storage.objects for delete to authenticated using (bucket_id='stories' and (storage.foldername(name))[1]=auth.uid()::text);
