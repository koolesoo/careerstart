-- Run once in Supabase Dashboard → SQL Editor.
-- The browser can call only these narrowly-scoped RPCs; table access stays private.

create table if not exists public.career_game_sessions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[0-9]{6}$'),
  created_at timestamptz not null default now()
);

create table if not exists public.career_game_claims (
  session_id uuid not null references public.career_game_sessions(id) on delete cascade,
  team_no smallint not null check (team_no between 1 and 3),
  card_id smallint not null check (card_id between 1 and 12),
  created_at timestamptz not null default now(),
  primary key (session_id, team_no, card_id)
);

alter table public.career_game_sessions enable row level security;
alter table public.career_game_claims enable row level security;
revoke all on public.career_game_sessions from anon, authenticated;
revoke all on public.career_game_claims from anon, authenticated;

create or replace function public.create_career_game_session()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
begin
  loop
    v_code := lpad((floor(random() * 1000000))::text, 6, '0');
    begin
      insert into public.career_game_sessions(code) values (v_code);
      return jsonb_build_object('code', v_code);
    exception when unique_violation then
      -- Generate another code if this one is already in use.
    end;
  end loop;
end;
$$;

create or replace function public.check_career_game_session(p_code text)
returns jsonb
language sql
security definer
set search_path = ''
stable
as $$
  select case when exists (
    select 1 from public.career_game_sessions
    where code = upper(trim(p_code))
  ) then jsonb_build_object('ok', true)
    else jsonb_build_object('ok', false)
  end;
$$;

create or replace function public.claim_career_game_card(p_code text, p_team_no smallint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session_id uuid;
  v_card_id smallint;
begin
  if p_team_no not between 1 and 3 then
    raise exception 'Выберите команду от 1 до 3';
  end if;

  select id into v_session_id
  from public.career_game_sessions
  where code = upper(trim(p_code))
  for update;

  if v_session_id is null then
    raise exception 'Сессия не найдена. Проверьте код';
  end if;

  select candidate.card_id into v_card_id
  from generate_series(1, 12) as candidate(card_id)
  where not exists (
    select 1 from public.career_game_claims as claim
    where claim.session_id = v_session_id
      and claim.team_no = p_team_no
      and claim.card_id = candidate.card_id
  )
  order by random()
  limit 1;

  if v_card_id is null then
    return jsonb_build_object('complete', true);
  end if;

  insert into public.career_game_claims(session_id, team_no, card_id)
  values (v_session_id, p_team_no, v_card_id);

  return jsonb_build_object('complete', false, 'card_id', v_card_id);
end;
$$;

revoke execute on function public.create_career_game_session() from public;
revoke execute on function public.check_career_game_session(text) from public;
revoke execute on function public.claim_career_game_card(text, smallint) from public;
grant execute on function public.create_career_game_session() to anon, authenticated;
grant execute on function public.check_career_game_session(text) to anon, authenticated;
grant execute on function public.claim_career_game_card(text, smallint) to anon, authenticated;
