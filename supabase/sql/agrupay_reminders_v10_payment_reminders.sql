-- ============================================================
-- AgruPay · Recordatorios de cobro v10 — «me estás debiendo»
-- ============================================================
-- Corre esto DESPUÉS de amigos v9. Idempotente.
--
-- Qué añade
-- 1. `device_tokens`: el token de APNs de cada teléfono, para poder mandarle
--    una notificación a un amigo. Nadie lee los tokens de nadie: sólo el
--    servicio (la Edge Function `send-reminder-push`) los toca.
-- 2. `payment_reminders`: «Joseph te recuerda un pago». Lleva el comercio, la
--    fecha del gasto, un monto opcional y el mensaje. No crea ninguna deuda
--    del otro lado: es un recado, y quien lo recibe sólo lo ve y lo cierra.
-- 3. Tope de uno por día: mientras el amigo no lo haya cerrado, el del día
--    siguiente **reemplaza** al anterior en vez de apilarse. Si lo cierra, se
--    le puede mandar otro en el acto.
-- 4. Sólo entre amigos (`is_friend`) y sólo con cuenta de Google, igual que
--    todo lo demás de Amigos.

-- ── Tokens de notificación ──────────────────────────────────────────────

create table if not exists public.device_tokens (
  token text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  -- 'sandbox' con la app instalada desde Xcode, 'production' desde TestFlight
  -- o la App Store. APNs rechaza el token si se manda al servidor equivocado.
  environment text not null default 'production',
  updated_at timestamptz not null default now()
);

create index if not exists device_tokens_user_idx on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

-- Ninguna política de lectura a propósito: el token no lo necesita ni su
-- dueño. Se escribe por RPC y se lee sólo con la llave de servicio.
drop policy if exists device_tokens_owner_rw on public.device_tokens;

create or replace function public.register_device_token(p_token text, p_environment text default 'production')
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := public.require_google_user();
begin
  if coalesce(trim(p_token), '') = '' then
    raise exception 'Token vacío';
  end if;

  insert into public.device_tokens (token, user_id, environment, updated_at)
  values (trim(p_token), v_user,
          case when p_environment = 'sandbox' then 'sandbox' else 'production' end,
          now())
  on conflict (token) do update
    set user_id = excluded.user_id,
        environment = excluded.environment,
        updated_at = now();
end;
$$;

revoke all on function public.register_device_token(text, text) from public, anon;
grant execute on function public.register_device_token(text, text) to authenticated;

-- Cerrar sesión o quitar el permiso de notificaciones: el token deja de ser
-- de este usuario.
create or replace function public.forget_device_token(p_token text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.device_tokens
  where token = trim(p_token) and user_id = auth.uid();
$$;

revoke all on function public.forget_device_token(text) from public, anon;
grant execute on function public.forget_device_token(text) to authenticated;

-- ── Recordatorios ───────────────────────────────────────────────────────

create table if not exists public.payment_reminders (
  id uuid primary key default gen_random_uuid(),
  from_user uuid not null references auth.users(id) on delete cascade,
  to_user uuid not null references auth.users(id) on delete cascade,
  -- Identifica la deuda **en el teléfono de quien cobra**. Al que la recibe
  -- no le sirve de nada; está para el tope de uno por día y para que la ficha
  -- de la deuda sepa a quién ya le escribió.
  debt_key text not null,
  merchant text not null,
  occurred_on date,
  -- Opcional: un recordatorio puede no llevar cifra («ya sabes de cuánto es»).
  amount numeric(14,2),
  currency text not null default 'PEN',
  message text not null default '',
  -- Día de calendario de quien cobra (hora de Perú), que es como se cuenta el
  -- «uno por día».
  sent_on date not null default (now() at time zone 'America/Lima')::date,
  created_at timestamptz not null default now(),
  dismissed_at timestamptz
);

create index if not exists payment_reminders_to_idx on public.payment_reminders (to_user, dismissed_at);
create index if not exists payment_reminders_from_idx on public.payment_reminders (from_user, debt_key);

-- Uno abierto por amigo y por deuda: el del día siguiente reemplaza al de
-- ayer en vez de apilarse.
create unique index if not exists payment_reminders_open_idx
  on public.payment_reminders (from_user, to_user, debt_key)
  where dismissed_at is null;

alter table public.payment_reminders enable row level security;

drop policy if exists payment_reminders_read on public.payment_reminders;
create policy payment_reminders_read on public.payment_reminders
  for select to authenticated
  using (to_user = auth.uid() or from_user = auth.uid());

-- Sin insert ni update directos: todo pasa por las funciones de abajo, que
-- comprueban la amistad y el tope diario.

-- Manda (o renueva) el recordatorio a cada amigo de la lista.
--
-- `p_amounts` es un objeto {"<uuid del amigo>": 40.00}. Lo que no aparezca ahí
-- va sin monto.
--
-- Devuelve una fila por amigo con lo que pasó:
--   sent          se mandó uno nuevo
--   renewed       ya había uno sin abrir de otro día: se reemplazó
--   already_today ya se le mandó hoy y sigue sin abrirlo: no se manda nada
--   not_friend    no es tu amigo (o dejó de serlo)
create or replace function public.send_payment_reminders(
  p_friends uuid[],
  p_debt_key text,
  p_merchant text,
  p_occurred_on date default null,
  p_amounts jsonb default '{}'::jsonb,
  p_currency text default 'PEN',
  p_message text default ''
)
returns table (friend uuid, status text, reminder_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := public.require_google_user();
  v_today date := (now() at time zone 'America/Lima')::date;
  v_friend uuid;
  v_amount numeric(14,2);
  v_existing public.payment_reminders%rowtype;
  v_message text := left(coalesce(p_message, ''), 240);
  v_merchant text := left(coalesce(nullif(trim(p_merchant), ''), 'Un gasto'), 120);
begin
  if coalesce(trim(p_debt_key), '') = '' then
    raise exception 'Falta la deuda';
  end if;
  -- Tope de cordura: un recordatorio no es una lista de difusión.
  if coalesce(array_length(p_friends, 1), 0) > 20 then
    raise exception 'Demasiados amigos en un mismo recordatorio';
  end if;

  foreach v_friend in array coalesce(p_friends, array[]::uuid[]) loop
    if not public.is_friend(v_friend) then
      friend := v_friend; status := 'not_friend'; reminder_id := null;
      return next;
      continue;
    end if;

    v_amount := nullif(p_amounts ->> v_friend::text, '')::numeric;

    select * into v_existing
    from public.payment_reminders
    where from_user = v_user and to_user = v_friend
      and debt_key = trim(p_debt_key) and dismissed_at is null;

    if found then
      if v_existing.sent_on >= v_today then
        friend := v_friend; status := 'already_today'; reminder_id := v_existing.id;
        return next;
        continue;
      end if;

      update public.payment_reminders
         set merchant = v_merchant,
             occurred_on = p_occurred_on,
             amount = v_amount,
             currency = coalesce(nullif(p_currency, ''), 'PEN'),
             message = v_message,
             sent_on = v_today,
             created_at = now()
       where id = v_existing.id;

      friend := v_friend; status := 'renewed'; reminder_id := v_existing.id;
      return next;
      continue;
    end if;

    insert into public.payment_reminders
      (from_user, to_user, debt_key, merchant, occurred_on, amount, currency, message, sent_on)
    values
      (v_user, v_friend, trim(p_debt_key), v_merchant, p_occurred_on, v_amount,
       coalesce(nullif(p_currency, ''), 'PEN'), v_message, v_today)
    returning id into reminder_id;

    friend := v_friend; status := 'sent';
    return next;
  end loop;
end;
$$;

revoke all on function public.send_payment_reminders(uuid[], text, text, date, jsonb, text, text) from public, anon;
grant execute on function public.send_payment_reminders(uuid[], text, text, date, jsonb, text, text) to authenticated;

-- Lo que me están recordando y todavía no cierro.
create or replace function public.list_my_reminders()
returns setof public.payment_reminders
language sql
stable
security definer
set search_path = public
as $$
  select * from public.payment_reminders
  where to_user = auth.uid() and dismissed_at is null
  order by created_at desc;
$$;

revoke all on function public.list_my_reminders() from public, anon;
grant execute on function public.list_my_reminders() to authenticated;

-- «Listo»: lo cierra y deja que su amigo pueda mandarle otro enseguida.
create or replace function public.dismiss_payment_reminder(p_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.payment_reminders
     set dismissed_at = now()
   where id = p_id and to_user = auth.uid() and dismissed_at is null;
$$;

revoke all on function public.dismiss_payment_reminder(uuid) from public, anon;
grant execute on function public.dismiss_payment_reminder(uuid) to authenticated;

-- A quién le escribí ya por esta deuda: la ficha marca «enviado» y apaga a
-- quien ya recibió uno hoy.
create or replace function public.list_sent_reminders(p_debt_key text)
returns table (friend uuid, sent_on date, dismissed_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select to_user, sent_on, dismissed_at
  from public.payment_reminders
  where from_user = auth.uid() and debt_key = trim(p_debt_key)
  order by created_at desc;
$$;

revoke all on function public.list_sent_reminders(text) from public, anon;
grant execute on function public.list_sent_reminders(text) to authenticated;

-- ── Realtime ────────────────────────────────────────────────────────────
-- Para que el recordatorio aparezca en Amigos aunque la notificación no
-- llegue (permiso denegado, teléfono sin red en ese momento).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'payment_reminders'
  ) then
    alter publication supabase_realtime add table public.payment_reminders;
  end if;
exception when others then
  -- Sin permiso sobre la publicación no se cae todo el archivo: lo demás
  -- funciona igual, y sin Realtime el recordatorio aparece igual al abrir
  -- Amigos (que es cuando se vuelve a pedir la lista).
  raise notice 'Realtime no se pudo activar para payment_reminders: %', sqlerrm;
end
$$;
