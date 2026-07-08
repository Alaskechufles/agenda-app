-- ============================================================
-- CENTRO ESTETICO - Esquema completo para Supabase (Postgres)
-- Ejecutar en el SQL Editor de Supabase, en este orden.
-- ============================================================

-- Extension necesaria para la restriccion de exclusion (anti-solapamiento)
create extension if not exists btree_gist;

-- ============================================================
-- 1. TABLA PERFILES (extiende auth.users)
-- ============================================================
create table public.perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nombre text not null,
  telefono text,
  rol text not null default 'cliente' check (rol in ('admin', 'staff', 'cliente')),
  creado_en timestamptz not null default now()
);

-- Trigger: crear perfil automaticamente al registrarse un usuario
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.perfiles (id, nombre, telefono)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nombre', split_part(new.email, '@', 1)),
    new.raw_user_meta_data->>'telefono'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================
-- 2. FUNCIONES AUXILIARES DE ROL
-- security definer: evitan recursion infinita en las politicas RLS
-- ============================================================
create or replace function public.es_admin()
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from perfiles
    where id = auth.uid() and rol = 'admin'
  );
$$;

-- Trigger: solo un admin puede cambiar el rol de un perfil
create or replace function public.prevenir_cambio_rol()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  -- auth.uid() es null cuando se ejecuta desde el SQL Editor o con la
  -- service role key: esos contextos si pueden cambiar roles (bootstrap
  -- del primer admin). Un usuario logueado normal no puede.
  if new.rol is distinct from old.rol
     and auth.uid() is not null
     and not public.es_admin() then
    raise exception 'Solo un administrador puede cambiar roles';
  end if;
  return new;
end;
$$;

create trigger perfiles_proteger_rol
  before update on public.perfiles
  for each row execute function public.prevenir_cambio_rol();

-- ============================================================
-- 3. TABLAS DEL NEGOCIO
-- ============================================================
create table public.staff (
  id serial primary key,
  usuario_id uuid not null unique references public.perfiles(id) on delete cascade,
  foto_url text,
  descripcion text,
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);

create table public.servicios (
  id serial primary key,
  nombre text not null,
  descripcion text,
  duracion_minutos int not null check (duracion_minutos > 0),
  precio numeric(10,2) not null check (precio >= 0),
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);

create table public.staff_servicios (
  staff_id int not null references public.staff(id) on delete cascade,
  servicio_id int not null references public.servicios(id) on delete cascade,
  primary key (staff_id, servicio_id)
);

create table public.horarios_staff (
  id serial primary key,
  staff_id int not null references public.staff(id) on delete cascade,
  dia_semana int not null check (dia_semana between 0 and 6), -- 0=domingo ... 6=sabado
  hora_inicio time not null,
  hora_fin time not null,
  check (hora_fin > hora_inicio)
);

create table public.ausencias (
  id serial primary key,
  staff_id int not null references public.staff(id) on delete cascade,
  inicio timestamptz not null,
  fin timestamptz not null,
  motivo text,
  creado_en timestamptz not null default now(),
  check (fin > inicio)
);

create table public.citas (
  id serial primary key,
  cliente_id uuid not null references public.perfiles(id),
  staff_id int not null references public.staff(id),
  servicio_id int not null references public.servicios(id),
  fecha_hora_inicio timestamptz not null,
  fecha_hora_fin timestamptz not null,
  precio_cobrado numeric(10,2) not null,
  estado text not null default 'pendiente'
    check (estado in ('pendiente', 'confirmada', 'completada', 'cancelada', 'no_asistio')),
  creado_en timestamptz not null default now(),
  check (fecha_hora_fin > fecha_hora_inicio),
  -- Red de seguridad: imposible insertar dos citas activas solapadas del mismo staff
  constraint citas_sin_solapamiento exclude using gist (
    staff_id with =,
    tstzrange(fecha_hora_inicio, fecha_hora_fin) with &&
  ) where (estado not in ('cancelada'))
);

-- Indices para las consultas mas frecuentes
create index idx_citas_staff_fecha on public.citas (staff_id, fecha_hora_inicio);
create index idx_citas_cliente on public.citas (cliente_id, fecha_hora_inicio desc);
create index idx_ausencias_staff on public.ausencias (staff_id, inicio);
create index idx_horarios_staff on public.horarios_staff (staff_id, dia_semana);

-- Funcion auxiliar: id de staff del usuario logueado (null si no es staff).
-- Se define aqui porque referencia la tabla staff.
create or replace function public.mi_staff_id()
returns int
language sql
security definer set search_path = public
stable
as $$
  select s.id from staff s
  where s.usuario_id = auth.uid();
$$;

-- ============================================================
-- 4. ROW LEVEL SECURITY
-- ============================================================
alter table public.perfiles enable row level security;
alter table public.staff enable row level security;
alter table public.servicios enable row level security;
alter table public.staff_servicios enable row level security;
alter table public.horarios_staff enable row level security;
alter table public.ausencias enable row level security;
alter table public.citas enable row level security;

-- ---- PERFILES ----
-- Ver: mi propio perfil, perfiles del staff (para mostrar nombres al agendar), o admin ve todo
create policy perfiles_select on public.perfiles
  for select to authenticated
  using (
    id = auth.uid()
    or public.es_admin()
    or exists (select 1 from public.staff s where s.usuario_id = perfiles.id)
  );

-- Editar: solo mi propio perfil (el trigger protege el campo rol) o admin
create policy perfiles_update on public.perfiles
  for update to authenticated
  using (id = auth.uid() or public.es_admin());

-- ---- STAFF ----
create policy staff_select on public.staff
  for select to authenticated
  using (activo = true or public.es_admin());

create policy staff_admin_write on public.staff
  for all to authenticated
  using (public.es_admin())
  with check (public.es_admin());

-- ---- SERVICIOS ----
create policy servicios_select on public.servicios
  for select to authenticated
  using (activo = true or public.es_admin());

create policy servicios_admin_write on public.servicios
  for all to authenticated
  using (public.es_admin())
  with check (public.es_admin());

-- ---- STAFF_SERVICIOS ----
create policy staff_servicios_select on public.staff_servicios
  for select to authenticated
  using (true);

create policy staff_servicios_admin_write on public.staff_servicios
  for all to authenticated
  using (public.es_admin())
  with check (public.es_admin());

-- ---- HORARIOS_STAFF ----
create policy horarios_select on public.horarios_staff
  for select to authenticated
  using (true);

create policy horarios_admin_write on public.horarios_staff
  for all to authenticated
  using (public.es_admin())
  with check (public.es_admin());

-- ---- AUSENCIAS ----
-- Ver: admin, o el staff ve las suyas
create policy ausencias_select on public.ausencias
  for select to authenticated
  using (public.es_admin() or staff_id = public.mi_staff_id());

create policy ausencias_admin_write on public.ausencias
  for all to authenticated
  using (public.es_admin())
  with check (public.es_admin());

-- ---- CITAS ----
-- Ver: el cliente ve las suyas, el staff ve las que atiende, admin ve todo
create policy citas_select on public.citas
  for select to authenticated
  using (
    cliente_id = auth.uid()
    or staff_id = public.mi_staff_id()
    or public.es_admin()
  );

-- Insertar/actualizar directo: solo admin.
-- Los clientes crean y cancelan citas a traves de las funciones RPC de abajo.
create policy citas_admin_write on public.citas
  for all to authenticated
  using (public.es_admin())
  with check (public.es_admin());

-- ============================================================
-- 5. FUNCION: OBTENER SLOTS DISPONIBLES
-- Llamar desde el frontend con:
-- supabase.rpc('obtener_slots_disponibles', { p_staff_id, p_servicio_id, p_fecha })
-- ============================================================
create or replace function public.obtener_slots_disponibles(
  p_staff_id int,
  p_servicio_id int,
  p_fecha date,
  p_intervalo_minutos int default 30  -- cada cuanto se ofrece un slot
)
returns table (slot_inicio timestamptz, slot_fin timestamptz)
language plpgsql
security definer set search_path = public
stable
as $$
declare
  v_duracion int;
begin
  select duracion_minutos into v_duracion
  from servicios where id = p_servicio_id and activo = true;

  if v_duracion is null then
    raise exception 'Servicio no encontrado o inactivo';
  end if;

  return query
  with franjas as (
    -- Plantilla semanal del staff para ese dia.
    -- 'at time zone' interpreta la hora como hora local de Peru,
    -- ya que Supabase corre en UTC.
    select
      ((p_fecha + h.hora_inicio) at time zone 'America/Lima') as f_ini,
      ((p_fecha + h.hora_fin) at time zone 'America/Lima') as f_fin
    from horarios_staff h
    where h.staff_id = p_staff_id
      and h.dia_semana = extract(dow from p_fecha)::int
  ),
  candidatos as (
    -- Generar slots candidatos dentro de cada franja
    select
      gs as s_ini,
      gs + make_interval(mins => v_duracion) as s_fin
    from franjas f,
    lateral generate_series(
      f.f_ini,
      f.f_fin - make_interval(mins => v_duracion),
      make_interval(mins => p_intervalo_minutos)
    ) as gs
  )
  select c.s_ini, c.s_fin
  from candidatos c
  where
    -- Solo slots futuros
    c.s_ini > now()
    -- Sin cruce con ausencias
    and not exists (
      select 1 from ausencias a
      where a.staff_id = p_staff_id
        and a.inicio < c.s_fin
        and a.fin > c.s_ini
    )
    -- Sin cruce con citas activas
    and not exists (
      select 1 from citas ci
      where ci.staff_id = p_staff_id
        and ci.estado not in ('cancelada')
        and ci.fecha_hora_inicio < c.s_fin
        and ci.fecha_hora_fin > c.s_ini
    )
  order by c.s_ini;
end;
$$;

-- ============================================================
-- 6. FUNCION: CREAR CITA (transaccional y a prueba de carreras)
-- supabase.rpc('crear_cita', { p_staff_id, p_servicio_id, p_inicio })
-- ============================================================
create or replace function public.crear_cita(
  p_staff_id int,
  p_servicio_id int,
  p_inicio timestamptz
)
returns citas
language plpgsql
security definer set search_path = public
as $$
declare
  v_duracion int;
  v_precio numeric(10,2);
  v_fin timestamptz;
  v_cita citas;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesion para agendar';
  end if;

  -- Datos del servicio (snapshot de precio y duracion)
  select duracion_minutos, precio into v_duracion, v_precio
  from servicios where id = p_servicio_id and activo = true;

  if v_duracion is null then
    raise exception 'Servicio no encontrado o inactivo';
  end if;

  v_fin := p_inicio + make_interval(mins => v_duracion);

  if p_inicio <= now() then
    raise exception 'La cita debe ser en el futuro';
  end if;

  -- El staff debe ofrecer este servicio y estar activo
  if not exists (
    select 1 from staff_servicios ss
    join staff s on s.id = ss.staff_id
    where ss.staff_id = p_staff_id
      and ss.servicio_id = p_servicio_id
      and s.activo = true
  ) then
    raise exception 'Este miembro del staff no ofrece ese servicio';
  end if;

  -- Debe caer dentro de la plantilla semanal
  -- (convertimos a hora local de Peru porque el servidor corre en UTC)
  if not exists (
    select 1 from horarios_staff h
    where h.staff_id = p_staff_id
      and h.dia_semana = extract(dow from (p_inicio at time zone 'America/Lima'))::int
      and (p_inicio at time zone 'America/Lima')::time >= h.hora_inicio
      and (v_fin at time zone 'America/Lima')::time <= h.hora_fin
  ) then
    raise exception 'Fuera del horario de trabajo del staff';
  end if;

  -- No debe cruzarse con una ausencia
  if exists (
    select 1 from ausencias a
    where a.staff_id = p_staff_id
      and a.inicio < v_fin
      and a.fin > p_inicio
  ) then
    raise exception 'El staff no esta disponible en ese horario';
  end if;

  -- Insertar. Si dos clientes intentan el mismo slot a la vez,
  -- la restriccion citas_sin_solapamiento rechaza al segundo.
  insert into citas (cliente_id, staff_id, servicio_id,
                     fecha_hora_inicio, fecha_hora_fin,
                     precio_cobrado, estado)
  values (auth.uid(), p_staff_id, p_servicio_id,
          p_inicio, v_fin, v_precio, 'pendiente')
  returning * into v_cita;

  return v_cita;
exception
  when exclusion_violation then
    raise exception 'Ese horario acaba de ser reservado, elige otro';
end;
$$;

-- ============================================================
-- 7. FUNCION: CANCELAR CITA (cliente cancela la suya)
-- supabase.rpc('cancelar_cita', { p_cita_id })
-- ============================================================
create or replace function public.cancelar_cita(p_cita_id int)
returns citas
language plpgsql
security definer set search_path = public
as $$
declare
  v_cita citas;
begin
  update citas
  set estado = 'cancelada'
  where id = p_cita_id
    and estado in ('pendiente', 'confirmada')
    and (cliente_id = auth.uid() or public.es_admin())
    -- Politica de cancelacion: minimo 2 horas de anticipacion (ajustable)
    and fecha_hora_inicio > now() + interval '2 hours'
  returning * into v_cita;

  if v_cita.id is null then
    raise exception 'No se pudo cancelar: la cita no existe, no es tuya, ya paso o falta menos de 2 horas';
  end if;

  return v_cita;
end;
$$;

-- ============================================================
-- 8. DATOS DE EJEMPLO (opcional, para probar)
-- Nota: primero registra usuarios reales via Supabase Auth,
-- luego asigna roles y crea el staff con sus UUID reales.
-- ============================================================
insert into public.servicios (nombre, descripcion, duracion_minutos, precio) values
  ('Corte de cabello', 'Corte clasico o moderno', 45, 30.00),
  ('Corte de barba', 'Perfilado y arreglo de barba', 30, 20.00),
  ('Manicure', 'Limpieza y esmaltado de unas', 60, 35.00),
  ('Pedicure', 'Cuidado completo de pies', 60, 40.00);

-- Ejemplo de como promover a alguien (ejecutar con el UUID real):
-- update public.perfiles set rol = 'admin' where id = 'UUID-DEL-USUARIO';
-- update public.perfiles set rol = 'staff' where id = 'UUID-DEL-STAFF';
-- insert into public.staff (usuario_id, descripcion) values ('UUID-DEL-STAFF', 'Especialista en cortes');
-- insert into public.staff_servicios (staff_id, servicio_id) values (1, 1), (1, 3);
-- insert into public.horarios_staff (staff_id, dia_semana, hora_inicio, hora_fin) values
--   (1, 1, '09:00', '13:00'),
--   (1, 1, '15:00', '19:00'),
--   (1, 2, '09:00', '18:00');