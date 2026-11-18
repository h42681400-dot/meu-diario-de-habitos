-- Cottontail: responder mensagens no chat
-- Execute no SQL Editor do Supabase antes de testar o recurso.

alter table public.direct_messages
  add column if not exists reply_to_message_id uuid
  references public.direct_messages(id) on delete set null;

create index if not exists direct_messages_reply_to_message_id_idx
  on public.direct_messages(reply_to_message_id);
