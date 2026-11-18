-- Cottontail: solicitações para seguir perfis privados
create table if not exists public.follow_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete cascade,
  target_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(requester_id,target_id),
  check (requester_id <> target_id)
);

create index if not exists follow_requests_target_status_idx
  on public.follow_requests(target_id,status,created_at desc);

alter table public.follow_requests enable row level security;

drop policy if exists "follow_requests_read_participants" on public.follow_requests;
create policy "follow_requests_read_participants" on public.follow_requests
for select to authenticated
using (auth.uid() = requester_id or auth.uid() = target_id);

drop policy if exists "follow_requests_create_self" on public.follow_requests;
create policy "follow_requests_create_self" on public.follow_requests
for insert to authenticated
with check (auth.uid() = requester_id and status = 'pending');

drop policy if exists "follow_requests_retry_self" on public.follow_requests;
create policy "follow_requests_retry_self" on public.follow_requests
for update to authenticated
using (auth.uid() = requester_id and status = 'rejected')
with check (auth.uid() = requester_id and status = 'pending');

create or replace function public.cottontail_notify_follow_request()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if new.status = 'pending' and (tg_op = 'INSERT' or old.status is distinct from 'pending') then
    insert into public.notifications(user_id,actor_id,type,read)
    values(new.target_id,new.requester_id,'follow_request',false);
  end if;
  return new;
end;
$$;

drop trigger if exists cottontail_follow_request_notification on public.follow_requests;
create trigger cottontail_follow_request_notification
after insert or update of status on public.follow_requests
for each row execute function public.cottontail_notify_follow_request();

-- Impede que um cliente contorne a aprovação inserindo diretamente em follows.
create or replace function public.cottontail_guard_private_follow()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if exists(select 1 from public.user_profiles p where p.user_id = new.following_id and coalesce(p.is_private,false))
     and not exists(
       select 1 from public.follow_requests r
       where r.requester_id = new.follower_id
         and r.target_id = new.following_id
         and r.status = 'accepted'
     ) then
    raise exception 'Este perfil é privado. Envie uma solicitação para seguir.';
  end if;
  return new;
end;
$$;

drop trigger if exists cottontail_guard_private_follow on public.follows;
create trigger cottontail_guard_private_follow
before insert on public.follows
for each row execute function public.cottontail_guard_private_follow();

create or replace function public.cottontail_decide_follow_request(
  p_requester_id uuid,
  p_approve boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  req public.follow_requests%rowtype;
begin
  select * into req
  from public.follow_requests
  where requester_id = p_requester_id
    and target_id = auth.uid()
    and status = 'pending'
  for update;

  if not found then
    raise exception 'Solicitação não encontrada ou já respondida.';
  end if;

  update public.follow_requests
  set status = case when p_approve then 'accepted' else 'rejected' end,
      updated_at = now()
  where id = req.id;

  if p_approve then
    insert into public.follows(follower_id,following_id)
    values(req.requester_id,req.target_id)
    on conflict(follower_id,following_id) do nothing;
    insert into public.notifications(user_id,actor_id,type,read)
    values(req.requester_id,req.target_id,'follow',false);
  end if;

  return jsonb_build_object('success',true,'status',case when p_approve then 'accepted' else 'rejected' end);
end;
$$;

revoke all on function public.cottontail_decide_follow_request(uuid,boolean) from public;
grant execute on function public.cottontail_decide_follow_request(uuid,boolean) to authenticated;
