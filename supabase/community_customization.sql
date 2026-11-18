-- Cottontail — Personalização e acesso das comunidades
-- Execute uma única vez no SQL Editor do Supabase.
-- Mantém as comunidades e publicações existentes; apenas acrescenta campos e regras.

alter table public.wellness_communities
  add column if not exists cover_url text;

-- A bio da comunidade usa o campo description já existente.

create table if not exists public.wellness_community_join_requests (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.wellness_communities(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (community_id,user_id)
);
create index if not exists wellness_community_join_requests_admin_idx
  on public.wellness_community_join_requests(community_id,status,created_at);

alter table public.wellness_community_join_requests enable row level security;

-- Metadados (nome, bio, capa e privacidade) são descobríveis para que usuários
-- possam encontrar comunidades privadas e solicitar entrada. O conteúdo continua protegido.
drop policy if exists "cottontail_communities_read_public" on public.wellness_communities;
create policy "cottontail_communities_read_public" on public.wellness_communities
  for select to authenticated using (true);

drop policy if exists "cottontail_community_members_read" on public.wellness_community_members;
create policy "cottontail_community_members_read" on public.wellness_community_members
  for select to authenticated using (
    user_id = auth.uid()
    or exists (
      select 1 from public.wellness_communities c
      where c.id = wellness_community_members.community_id
        and (not c.is_private or c.created_by = auth.uid())
    )
  );

drop policy if exists "cottontail_community_members_join_public" on public.wellness_community_members;
create policy "cottontail_community_members_join_public" on public.wellness_community_members
  for insert to authenticated with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.wellness_communities c
      where c.id = community_id
        and (not c.is_private or c.created_by = auth.uid())
    )
  );

drop policy if exists "cottontail_community_members_leave_self" on public.wellness_community_members;
create policy "cottontail_community_members_leave_self" on public.wellness_community_members
  for delete to authenticated using (
    user_id = auth.uid()
    or exists (
      select 1 from public.wellness_communities c
      where c.id = wellness_community_members.community_id
        and c.created_by = auth.uid()
    )
  );

-- Cada pessoa vê seus próprios pedidos; o criador da comunidade vê os pedidos recebidos.
drop policy if exists "cottontail_community_requests_read" on public.wellness_community_join_requests;
create policy "cottontail_community_requests_read" on public.wellness_community_join_requests
  for select to authenticated using (
    user_id = auth.uid()
    or exists (
      select 1 from public.wellness_communities c
      where c.id = wellness_community_join_requests.community_id
        and c.created_by = auth.uid()
    )
  );

drop policy if exists "cottontail_community_requests_create_own" on public.wellness_community_join_requests;
create policy "cottontail_community_requests_create_own" on public.wellness_community_join_requests
  for insert to authenticated with check (
    user_id = auth.uid()
    and status = 'pending'
    and exists (
      select 1 from public.wellness_communities c
      where c.id = community_id and c.is_private and c.created_by <> auth.uid()
    )
    and not exists (
      select 1 from public.wellness_community_members m
      where m.community_id = community_id and m.user_id = auth.uid()
    )
  );

grant select,insert on public.wellness_community_join_requests to authenticated;

-- A decisão é feita no servidor: somente o criador pode aprovar/recusar.
create or replace function public.cottontail_decide_community_join_request(
  p_request_id uuid,
  p_approved boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  request_row public.wellness_community_join_requests%rowtype;
  community_owner uuid;
begin
  select r.* into request_row
  from public.wellness_community_join_requests r
  where r.id = p_request_id
  for update;

  if not found then
    raise exception 'Solicitação não encontrada.';
  end if;

  select c.created_by into community_owner
  from public.wellness_communities c
  where c.id = request_row.community_id;

  if community_owner is distinct from auth.uid() then
    raise exception 'Somente o administrador pode decidir esta solicitação.';
  end if;

  if request_row.status <> 'pending' then
    raise exception 'Esta solicitação já foi respondida.';
  end if;

  update public.wellness_community_join_requests
  set status = case when p_approved then 'approved' else 'rejected' end,
      updated_at = now()
  where id = p_request_id;

  if p_approved then
    insert into public.wellness_community_members(community_id,user_id,role)
    values (request_row.community_id,request_row.user_id,'member')
    on conflict (community_id,user_id) do nothing;
  end if;

  return jsonb_build_object('success',true,'approved',p_approved);
end;
$$;

revoke all on function public.cottontail_decide_community_join_request(uuid,boolean) from public;
grant execute on function public.cottontail_decide_community_join_request(uuid,boolean) to authenticated;

-- A capa usa o bucket community-media já utilizado pelas mídias das publicações.
-- O upload permanece no escopo da pasta do usuário autenticado.
