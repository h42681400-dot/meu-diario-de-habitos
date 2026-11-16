-- Cottontail: recursos extras do chat (reações, imagens e áudios)
-- Execute este arquivo no SQL Editor do Supabase do projeto.

alter table public.direct_messages
  add column if not exists attachment_url text,
  add column if not exists attachment_type text;

create table if not exists public.direct_message_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.direct_messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reaction text not null check (char_length(reaction) between 1 and 8),
  created_at timestamptz not null default now(),
  unique (message_id, user_id, reaction)
);

alter table public.direct_message_reactions enable row level security;

drop policy if exists "Chat participants can read reactions" on public.direct_message_reactions;
create policy "Chat participants can read reactions"
on public.direct_message_reactions for select to authenticated
using (
  exists (
    select 1 from public.direct_messages m
    where m.id = message_id
      and (m.sender_id = auth.uid() or m.receiver_id = auth.uid())
  )
);

drop policy if exists "Users can react in their conversations" on public.direct_message_reactions;
create policy "Users can react in their conversations"
on public.direct_message_reactions for insert to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.direct_messages m
    where m.id = message_id
      and (m.sender_id = auth.uid() or m.receiver_id = auth.uid())
  )
);

drop policy if exists "Users can remove their own reactions" on public.direct_message_reactions;
create policy "Users can remove their own reactions"
on public.direct_message_reactions for delete to authenticated
using (user_id = auth.uid());

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-media', 'chat-media', true, 15728640, array['image/jpeg','image/png','image/webp','image/gif','audio/webm','audio/ogg','audio/mp4','audio/mpeg'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Chat users can upload their own media" on storage.objects;
create policy "Chat users can upload their own media"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'chat-media'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Chat media is publicly readable" on storage.objects;
create policy "Chat media is publicly readable"
on storage.objects for select to public
using (bucket_id = 'chat-media');

drop policy if exists "Chat users can delete their own media" on storage.objects;
create policy "Chat users can delete their own media"
on storage.objects for delete to authenticated
using (
  bucket_id = 'chat-media'
  and (storage.foldername(name))[1] = auth.uid()::text
);
