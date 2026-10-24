-- DRAFT: run in a new Supabase test project, never over an existing app schema.
-- Cloud foundation only. Native 1.1 still uses the single-business pilot API.
begin;
create schema if not exists private;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create table public.wb_organizations (
 id uuid primary key default gen_random_uuid(),
 name text not null check (length(btrim(name)) between 1 and 160),
 owner_id uuid not null unique references auth.users(id),
 seats integer not null default 5 check (seats in (5,10,20)),
 storage_limit_bytes bigint not null default 100000000 check (storage_limit_bytes > 0),
 reserved_bytes bigint not null default 0 check (reserved_bytes >= 0 and reserved_bytes <= storage_limit_bytes),
 created_at timestamptz not null default now()
);
create table public.wb_memberships (
 org_id uuid not null references public.wb_organizations(id),
 user_id uuid not null references auth.users(id),
 display_name text not null check (length(btrim(display_name)) between 1 and 80),
 role text not null check (role in ('owner','admin','editor','viewer')),
 primary key (org_id,user_id)
);
create table public.wb_customers (
 id uuid not null default gen_random_uuid(),
 org_id uuid not null references public.wb_organizations(id),
 name text not null check (length(btrim(name)) between 1 and 160),
 address text not null default '', contact text not null default '',
 primary key (org_id,id)
);
create table public.wb_projects (
 id uuid not null default gen_random_uuid(), org_id uuid not null references public.wb_organizations(id),
 customer_id uuid not null, title text not null check (length(btrim(title)) between 1 and 200),
 address text not null default '', assigned_to text not null default '', completed boolean not null default false,
 primary key (org_id,id), foreign key (org_id,customer_id) references public.wb_customers(org_id,id)
);
create table public.wb_reports (
 id uuid not null default gen_random_uuid(), org_id uuid not null, project_id uuid not null,
 author_id uuid not null default auth.uid() references auth.users(id),
 body text not null default '' check (length(body) <= 100000),
 weather_note text not null default '', latitude double precision, longitude double precision,
 created_at timestamptz not null default now(),
 primary key (org_id,id), foreign key (org_id,project_id) references public.wb_projects(org_id,id),
 check (latitude between -90 and 90), check (longitude between -180 and 180)
);
create table public.wb_messages (
 id uuid not null default gen_random_uuid(), org_id uuid not null, project_id uuid not null,
 author_id uuid not null default auth.uid() references auth.users(id),
 body text not null check (length(btrim(body)) between 1 and 4000),
 created_at timestamptz not null default now(),
 primary key (org_id,id), foreign key (org_id,project_id) references public.wb_projects(org_id,id)
);
create index wb_messages_cursor on public.wb_messages(org_id,project_id,created_at,id);
create table public.wb_invites (
 id uuid primary key default gen_random_uuid(), org_id uuid not null references public.wb_organizations(id),
 code_hash bytea not null unique,
 display_name text not null check (length(btrim(display_name)) between 1 and 80),
 role text not null check (role in ('editor','viewer')),
 expires_at timestamptz not null, created_at timestamptz not null default now()
);
create table public.wb_assets (
 id uuid not null default gen_random_uuid(), org_id uuid not null, project_id uuid not null,
 created_by uuid not null default auth.uid() references auth.users(id),
 object_path text not null unique, mime_type text not null check (mime_type in ('image/jpeg','audio/mp4','application/pdf')),
 expected_bytes bigint not null check (expected_bytes between 1 and 20000000),
 state text not null default 'reserved' check (state in ('reserved','uploaded')),
 created_at timestamptz not null default now(),
 primary key (org_id,id), foreign key (org_id,project_id) references public.wb_projects(org_id,id)
);

-- Security-definer helpers avoid recursive membership policies. Identity remains auth.uid().
create function private.wb_role(target uuid) returns text
language sql stable security definer set search_path = '' as $$
 select m.role from public.wb_memberships m where m.org_id=target and m.user_id=auth.uid()
$$;
revoke all on function private.wb_role(uuid) from public, anon;
grant execute on function private.wb_role(uuid) to authenticated;

alter table public.wb_organizations enable row level security;
alter table public.wb_memberships enable row level security;
alter table public.wb_customers enable row level security;
alter table public.wb_projects enable row level security;
alter table public.wb_reports enable row level security;
alter table public.wb_messages enable row level security;
alter table public.wb_invites enable row level security;
alter table public.wb_assets enable row level security;
revoke all on public.wb_organizations,public.wb_memberships,public.wb_customers,public.wb_projects,public.wb_reports,public.wb_messages,public.wb_invites,public.wb_assets from anon,authenticated;
grant select on public.wb_organizations,public.wb_memberships,public.wb_customers,public.wb_projects,public.wb_reports,public.wb_messages,public.wb_invites,public.wb_assets to authenticated;
grant insert,update on public.wb_customers,public.wb_projects to authenticated;
grant insert(id,org_id,project_id,author_id,body,weather_note,latitude,longitude) on public.wb_reports to authenticated;
grant insert(id,org_id,project_id,author_id,body) on public.wb_messages to authenticated;
grant update(body,weather_note,latitude,longitude) on public.wb_reports to authenticated;
-- Organizations, seats, memberships, invites and asset counters are not client-writable.
create policy wb_org_read on public.wb_organizations for select to authenticated using (private.wb_role(id) is not null);
create policy wb_member_read on public.wb_memberships for select to authenticated using (private.wb_role(org_id) is not null);
create policy wb_customer_read on public.wb_customers for select to authenticated using (private.wb_role(org_id) is not null);
create policy wb_customer_insert on public.wb_customers for insert to authenticated with check (private.wb_role(org_id) in ('owner','admin','editor'));
create policy wb_customer_update on public.wb_customers for update to authenticated using (private.wb_role(org_id) in ('owner','admin','editor')) with check (private.wb_role(org_id) in ('owner','admin','editor'));
create policy wb_project_read on public.wb_projects for select to authenticated using (private.wb_role(org_id) is not null);
create policy wb_project_insert on public.wb_projects for insert to authenticated with check (private.wb_role(org_id) in ('owner','admin','editor'));
create policy wb_project_update on public.wb_projects for update to authenticated using (private.wb_role(org_id) in ('owner','admin','editor')) with check (private.wb_role(org_id) in ('owner','admin','editor'));
create policy wb_report_read on public.wb_reports for select to authenticated using (private.wb_role(org_id) is not null);
create policy wb_report_insert on public.wb_reports for insert to authenticated with check (private.wb_role(org_id) in ('owner','admin','editor') and author_id=auth.uid());
create policy wb_report_update on public.wb_reports for update to authenticated using (private.wb_role(org_id) in ('owner','admin','editor')) with check (private.wb_role(org_id) in ('owner','admin','editor'));
create policy wb_message_read on public.wb_messages for select to authenticated using (private.wb_role(org_id) is not null);
create policy wb_message_insert on public.wb_messages for insert to authenticated with check (private.wb_role(org_id) in ('owner','admin','editor') and author_id=auth.uid());
create policy wb_invite_read on public.wb_invites for select to authenticated using (private.wb_role(org_id) in ('owner','admin'));
create policy wb_asset_read on public.wb_assets for select to authenticated using (private.wb_role(org_id) is not null);

create function public.wb_create_business(business_name text, owner_name text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare result uuid;
begin
 if auth.uid() is null then raise exception 'authentication required'; end if;
 insert into public.wb_organizations(name,owner_id) values(business_name,auth.uid()) returning id into result;
 insert into public.wb_memberships(org_id,user_id,display_name,role) values(result,auth.uid(),owner_name,'owner');
 return result;
end $$;

create function public.wb_create_invite(target uuid, person_name text, person_role text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare raw_code text; expiry timestamptz := now()+interval '48 hours'; seat_count integer; occupied integer;
begin
 if private.wb_role(target) not in ('owner','admin') or private.wb_role(target) is null then raise exception 'admin required'; end if;
 if person_role not in ('editor','viewer') then raise exception 'invalid role'; end if;
 select seats into seat_count from public.wb_organizations where id=target for update;
 delete from public.wb_invites where org_id=target and expires_at<=now();
 select (select count(*) from public.wb_memberships where org_id=target)+(select count(*) from public.wb_invites where org_id=target) into occupied;
 if occupied>=seat_count then raise exception 'seat limit reached'; end if;
 raw_code:=pg_catalog.encode(extensions.gen_random_bytes(32),'hex');
 insert into public.wb_invites(org_id,code_hash,display_name,role,expires_at) values(target,extensions.digest(raw_code,'sha256'),person_name,person_role,expiry);
 return jsonb_build_object('code',raw_code,'expiresAt',expiry);
end $$;

create function public.wb_accept_invite(raw_code text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare target uuid; invitation public.wb_invites%rowtype; seat_count integer;
begin
 if auth.uid() is null then raise exception 'authentication required'; end if;
 if length(raw_code)<>64 then raise exception 'invalid invitation'; end if;
 select org_id into target from public.wb_invites where code_hash=extensions.digest(raw_code,'sha256');
 if target is null then raise exception 'invalid invitation'; end if;
 select seats into seat_count from public.wb_organizations where id=target for update;
 select * into invitation from public.wb_invites where code_hash=extensions.digest(raw_code,'sha256') and expires_at>now() for update;
 if not found then raise exception 'expired or used invitation'; end if;
 if (select count(*) from public.wb_memberships where org_id=target)>=seat_count then raise exception 'seat limit reached'; end if;
 insert into public.wb_memberships(org_id,user_id,display_name,role) values(target,auth.uid(),invitation.display_name,invitation.role);
 delete from public.wb_invites where id=invitation.id;
 return target;
end $$;

create function public.wb_reserve_asset(target uuid, project uuid, size_bytes bigint, content_type text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare asset_id uuid:=gen_random_uuid(); object_name text; limit_bytes bigint; current_bytes bigint;
begin
 if private.wb_role(target) not in ('owner','admin','editor') or private.wb_role(target) is null then raise exception 'write access required'; end if;
 if size_bytes not between 1 and 20000000 then raise exception 'invalid size'; end if;
 select storage_limit_bytes,reserved_bytes into limit_bytes,current_bytes from public.wb_organizations where id=target for update;
 if current_bytes+size_bytes>limit_bytes then raise exception 'storage limit reached'; end if;
 object_name:=target::text||'/'||asset_id::text;
 insert into public.wb_assets(id,org_id,project_id,created_by,object_path,mime_type,expected_bytes) values(asset_id,target,project,auth.uid(),object_name,content_type,size_bytes);
 update public.wb_organizations set reserved_bytes=reserved_bytes+size_bytes where id=target;
 return jsonb_build_object('id',asset_id,'path',object_name,'bytes',size_bytes);
end $$;

-- No authenticated upload policy: direct writes fail closed until a trusted uploader
-- checks actual file size, finalizes reservations and reclaims abandoned uploads.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('werkbeleg-media','werkbeleg-media',false,20000000,array['image/jpeg','audio/mp4','application/pdf']);
create function private.wb_can_read_object(object_name text) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.wb_assets a where a.object_path=object_name and a.state='uploaded' and private.wb_role(a.org_id) is not null)
$$;
revoke all on function private.wb_can_read_object(text) from public,anon;
grant execute on function private.wb_can_read_object(text) to authenticated;
create policy wb_private_media_read on storage.objects for select to authenticated using (bucket_id='werkbeleg-media' and private.wb_can_read_object(name));

revoke all on function public.wb_create_business(text,text),public.wb_create_invite(uuid,text,text),public.wb_accept_invite(text),public.wb_reserve_asset(uuid,uuid,bigint,text) from public,anon;
grant execute on function public.wb_create_business(text,text),public.wb_create_invite(uuid,text,text),public.wb_accept_invite(text),public.wb_reserve_asset(uuid,uuid,bigint,text) to authenticated;
commit;
