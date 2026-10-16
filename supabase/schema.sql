-- Agenda da Barbearia — banco de dados no Supabase
-- Rode este arquivo inteiro no SQL Editor do Supabase (uma vez).
-- Clientes não fazem login: só conseguem agendar, ver os próprios agendamentos pelo código
-- e consultar horários ocupados (sem nome nem telefone de ninguém).
-- O administrador entra com e-mail e senha e vê tudo.

create extension if not exists pgcrypto;

create table if not exists public.agendamentos (
  id uuid primary key default gen_random_uuid(),
  servico text not null,
  servico_nome text not null,
  duracao int not null default 30,
  preco numeric(10,2) not null,
  cashback_usado numeric(10,2) not null default 0,
  barbeiro text not null,
  data date not null,
  hora text not null check (hora ~ '^[0-2][0-9]:[0-5][0-9]$'),
  nome text not null check (char_length(nome) between 2 and 80),
  telefone text not null check (char_length(telefone) between 10 and 20),
  status text not null default 'confirmado' check (status in ('confirmado','concluido','cancelado')),
  pagamento text not null default 'pendente' check (pagamento in ('pendente','informado','pago')),
  avisado_barbeiro timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz
);
create index if not exists agendamentos_data_idx on public.agendamentos (data, barbeiro);

create table if not exists public.config (
  id text primary key,          -- 'pix' ou 'whatsapp'
  dados jsonb not null default '{}'::jsonb
);

create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

-- ---------- Segurança ----------
alter table public.agendamentos enable row level security;
alter table public.config enable row level security;
alter table public.admins enable row level security;

create or replace function public.eh_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.admins where user_id = auth.uid());
$$;

drop policy if exists "admin tudo agendamentos" on public.agendamentos;
create policy "admin tudo agendamentos" on public.agendamentos
  for all to authenticated using (public.eh_admin()) with check (public.eh_admin());

drop policy if exists "todos leem config" on public.config;
create policy "todos leem config" on public.config for select to anon, authenticated using (true);
drop policy if exists "admin altera config" on public.config;
create policy "admin altera config" on public.config
  for all to authenticated using (public.eh_admin()) with check (public.eh_admin());

drop policy if exists "admin se ve" on public.admins;
create policy "admin se ve" on public.admins for select to authenticated using (user_id = auth.uid());

-- ---------- Regras do negócio ----------
-- Tabela de serviços (o preço vem daqui, não do navegador do cliente)
create or replace function public.preco_servico(p_servico text, out nome text, out preco numeric)
language sql immutable as $$
  select s.nome, s.preco from (values
    ('corte','Corte',45.00),
    ('barba','Barba na navalha',35.00),
    ('combo','Corte + barba',70.00),
    ('degrade','Degradê',55.00),
    ('pezinho','Pezinho e acabamento',15.00),
    ('sobrancelha','Sobrancelha',20.00)
  ) as s(id,nome,preco) where s.id = p_servico;
$$;

create or replace function public.so_digitos(t text) returns text
language sql immutable as $$ select regexp_replace(coalesce(t,''), '\D', '', 'g'); $$;

-- Saldo = 5% do valor pago nos atendimentos concluídos, menos o cashback já usado
create or replace function public.saldo_cashback(p_tel text) returns numeric
language sql stable security definer set search_path = public as $$
  select greatest(0, round(coalesce(sum(
    case when status = 'concluido' then (preco - cashback_usado) * 0.05 else 0 end
    - case when status <> 'cancelado' then cashback_usado else 0 end
  ), 0), 2))
  from public.agendamentos
  where so_digitos(telefone) = so_digitos(p_tel) and char_length(so_digitos(p_tel)) >= 10;
$$;

create or replace function public.horarios_ocupados(p_data date)
returns table(barbeiro text, hora text, duracao int)
language sql stable security definer set search_path = public as $$
  select a.barbeiro, a.hora, a.duracao from public.agendamentos a
  where a.data = p_data and a.status <> 'cancelado';
$$;

create or replace function public.criar_agendamento(
  p_servico text, p_barbeiro text, p_data date, p_hora text,
  p_nome text, p_telefone text, p_usar_cashback boolean)
returns public.agendamentos
language plpgsql security definer set search_path = public as $$
declare
  s record; v_min int; v_cb numeric := 0; v_novo public.agendamentos;
begin
  select * into s from public.preco_servico(p_servico);
  if s.nome is null then raise exception 'servico_invalido'; end if;
  if p_barbeiro not in ('rafael','diego','marcos') then raise exception 'barbeiro_invalido'; end if;
  if p_data < (now() at time zone 'America/Sao_Paulo')::date
     or p_data > (now() at time zone 'America/Sao_Paulo')::date + 30 then raise exception 'data_invalida'; end if;
  v_min := split_part(p_hora, ':', 1)::int * 60 + split_part(p_hora, ':', 2)::int;
  -- um pedido por vez para o mesmo barbeiro e dia, para não marcar dois no mesmo horário
  perform pg_advisory_xact_lock(hashtext(p_barbeiro || p_data::text));
  if exists (
    select 1 from public.agendamentos a
    where a.barbeiro = p_barbeiro and a.data = p_data and a.status <> 'cancelado'
      and v_min < (split_part(a.hora, ':', 1)::int * 60 + split_part(a.hora, ':', 2)::int) + a.duracao
      and v_min + 30 > (split_part(a.hora, ':', 1)::int * 60 + split_part(a.hora, ':', 2)::int)
  ) then raise exception 'horario_ocupado'; end if;
  if p_usar_cashback then v_cb := least(public.saldo_cashback(p_telefone), s.preco); end if;
  insert into public.agendamentos (servico, servico_nome, duracao, preco, cashback_usado, barbeiro, data, hora, nome, telefone)
  values (p_servico, s.nome, 30, s.preco, v_cb, p_barbeiro, p_data, p_hora, trim(p_nome), trim(p_telefone))
  returning * into v_novo;
  return v_novo;
end $$;

-- O cliente guarda os códigos dos próprios agendamentos no aparelho e consulta por eles
create or replace function public.meus_agendamentos(p_ids uuid[])
returns setof public.agendamentos
language sql stable security definer set search_path = public as $$
  select * from public.agendamentos where id = any(p_ids) order by data, hora;
$$;

create or replace function public.cliente_atualiza(p_id uuid, p_acao text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_acao = 'cancelar' then
    update public.agendamentos set status = 'cancelado', atualizado_em = now()
      where id = p_id and status = 'confirmado';
  elsif p_acao = 'paguei' then
    update public.agendamentos set pagamento = 'informado', atualizado_em = now()
      where id = p_id and pagamento = 'pendente';
  elsif p_acao = 'avisei' then
    update public.agendamentos set avisado_barbeiro = now() where id = p_id;
  else raise exception 'acao_invalida'; end if;
end $$;

revoke all on function public.criar_agendamento, public.meus_agendamentos, public.cliente_atualiza,
  public.horarios_ocupados, public.saldo_cashback from public;
grant execute on function public.criar_agendamento, public.meus_agendamentos, public.cliente_atualiza,
  public.horarios_ocupados, public.saldo_cashback, public.eh_admin to anon, authenticated;

insert into public.config (id, dados) values ('pix', '{}'), ('whatsapp', '{}') on conflict do nothing;

-- ---------- Depois de rodar ----------
-- 1. Em Authentication > Users, crie o usuário do administrador (e-mail e senha).
-- 2. Rode a linha abaixo trocando pelo e-mail dele:
-- insert into public.admins (user_id) select id from auth.users where email = 'seu@email.com';
