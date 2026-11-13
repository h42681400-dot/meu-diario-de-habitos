-- Cottontail — recursos sociais das comunidades
-- Execute este arquivo no SQL Editor do Supabase depois do setup inicial de comunidades.

alter table public.wellness_community_posts
  add column if not exists media_url text,
  add column if not exists media_type text;

create table if not exists public.wellness_community_post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.wellness_community_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  content text not null check (char_length(content) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists wellness_community_post_comments_post_idx
  on public.wellness_community_post_comments(post_id, created_at asc);

alter table public.wellness_community_post_comments enable row level security;

drop policy if exists "cottontail_community_comments_read_members" on public.wellness_community_post_comments;
create policy "cottontail_community_comments_read_members"
on public.wellness_community_post_comments for select to authenticated
using (
  exists (
    select 1
    from public.wellness_community_posts p
    join public.wellness_community_members m on m.community_id = p.community_id
    where p.id = wellness_community_post_comments.post_id
      and m.user_id = auth.uid()
  )
);

drop policy if exists "cottontail_community_comments_create_members" on public.wellness_community_post_comments;
create policy "cottontail_community_comments_create_members"
on public.wellness_community_post_comments for insert to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.wellness_community_posts p
    join public.wellness_community_members m on m.community_id = p.community_id
    where p.id = wellness_community_post_comments.post_id
      and m.user_id = auth.uid()
  )
);

drop policy if exists "cottontail_community_comments_delete_own" on public.wellness_community_post_comments;
create policy "cottontail_community_comments_delete_own"
on public.wellness_community_post_comments for delete to authenticated
using (user_id = auth.uid());

grant select, insert, delete on public.wellness_community_post_comments to authenticated;

-- Bucket público para exibir imagens e vídeos publicados nos grupos.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'community-media',
  'community-media',
  true,
  52428800,
  array['image/jpeg','image/png','image/webp','image/gif','image/avif','video/mp4','video/webm','video/quicktime']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "cottontail_community_media_read" on storage.objects;
create policy "cottontail_community_media_read"
on storage.objects for select to public
using (bucket_id = 'community-media');

drop policy if exists "cottontail_community_media_upload_own" on storage.objects;
create policy "cottontail_community_media_upload_own"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'community-media'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "cottontail_community_media_delete_own" on storage.objects;
create policy "cottontail_community_media_delete_own"
on storage.objects for delete to authenticated
using (
  bucket_id = 'community-media'
  and (storage.foldername(name))[1] = auth.uid()::text
);
