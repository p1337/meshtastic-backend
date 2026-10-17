-- Additional barriers for the hosted foundation; not a live deployment.
begin;
alter table public.wb_customers
 add column external_id text not null default '' check (length(external_id)<=160),
 add column source text not null default '' check (length(source)<=200),
 add column profile jsonb not null default '{}'::jsonb check (jsonb_typeof(profile)='object' and octet_length(profile::text)<=20000);
create unique index wb_customer_source_id on public.wb_customers(org_id,source,external_id) where source<>'' and external_id<>'';
-- Table-wide UPDATE would also allow changing identity/tenant in multi-membership accounts.
revoke update on public.wb_customers,public.wb_projects from authenticated;
grant update(name,address,contact,external_id,source,profile) on public.wb_customers to authenticated;
grant update(customer_id,title,address,assigned_to,completed) on public.wb_projects to authenticated;
create function private.wb_immutable_tenant() returns trigger
language plpgsql set search_path='' as $$ begin
 if new.org_id is distinct from old.org_id then raise exception 'tenant is immutable'; end if;
 return new;
end $$;
revoke all on function private.wb_immutable_tenant() from public,anon,authenticated;
create trigger wb_customer_tenant before update on public.wb_customers for each row execute function private.wb_immutable_tenant();
create trigger wb_project_tenant before update on public.wb_projects for each row execute function private.wb_immutable_tenant();
create trigger wb_report_tenant before update on public.wb_reports for each row execute function private.wb_immutable_tenant();
create trigger wb_message_tenant before update on public.wb_messages for each row execute function private.wb_immutable_tenant();
create trigger wb_asset_tenant before update on public.wb_assets for each row execute function private.wb_immutable_tenant();

-- Atomic insert-only bulk import, never an unrestricted service-role upsert.
create function public.wb_import_customers(target uuid, batch jsonb) returns integer
language plpgsql security definer set search_path='' as $$
declare item jsonb; imported integer:=0;
begin
 if private.wb_role(target) is null or private.wb_role(target) not in ('owner','admin') then raise exception 'admin required'; end if;
 if jsonb_typeof(batch) is distinct from 'array' then raise exception 'invalid batch'; end if;
 if jsonb_array_length(batch) not between 1 and 10000 or octet_length(batch::text)>10000000 then raise exception 'batch limit'; end if;
 -- Serialize imports for one business. Ownership/membership is checked again after the lock.
 perform 1 from public.wb_organizations where id=target for update;
 if private.wb_role(target) is null or private.wb_role(target) not in ('owner','admin') then raise exception 'admin required'; end if;
 for item in select value from jsonb_array_elements(batch) loop
  if jsonb_typeof(item) is distinct from 'object' or item ? 'org_id' or item ? 'orgID' or item ? 'id' then raise exception 'invalid customer identity'; end if;
  if exists(select 1 from jsonb_each(item) e where e.key not in ('name','address','contact','external_id','source','profile')) then raise exception 'unknown customer field'; end if;
  if exists(select 1 from jsonb_each(item) e where e.key<>'profile' and jsonb_typeof(e.value)<>'string') then raise exception 'customer values must be text'; end if;
  insert into public.wb_customers(org_id,name,address,contact,external_id,source,profile)
   values(target,item->>'name',coalesce(item->>'address',''),coalesce(item->>'contact',''),coalesce(item->>'external_id',''),coalesce(item->>'source',''),coalesce(item->'profile','{}'::jsonb));
  imported:=imported+1;
 end loop;
 return imported;
end $$;
revoke all on function public.wb_import_customers(uuid,jsonb) from public,anon;
grant execute on function public.wb_import_customers(uuid,jsonb) to authenticated;

-- Billing records can only be written by a trusted, separately verified server flow.
create table public.wb_subscriptions (
 org_id uuid primary key references public.wb_organizations(id),
 original_transaction_id text not null unique check (length(original_transaction_id) between 1 and 200),
 product_id text not null, status text not null check (status in ('active','grace','expired','revoked')),
 verified_at timestamptz not null, expires_at timestamptz not null
);
alter table public.wb_subscriptions enable row level security;
revoke all on public.wb_subscriptions from anon,authenticated;
grant select on public.wb_subscriptions to authenticated;
create policy wb_subscription_owner_read on public.wb_subscriptions for select to authenticated using (private.wb_role(org_id) in ('owner','admin'));

-- Owner/admin can revoke ordinary members; owner identity is protected.
create function public.wb_remove_member(target uuid, member uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare actor_role text; member_role text;
begin
 perform 1 from public.wb_organizations where id=target for update;
 actor_role:=private.wb_role(target);
 if actor_role is null or actor_role not in ('owner','admin') then raise exception 'admin required'; end if;
 select role into member_role from public.wb_memberships where org_id=target and user_id=member;
 if member_role='owner' or (actor_role='admin' and member_role='admin') then raise exception 'protected member'; end if;
 delete from public.wb_memberships where org_id=target and user_id=member;
 return found;
end $$;
revoke all on function public.wb_remove_member(uuid,uuid) from public,anon;
grant execute on function public.wb_remove_member(uuid,uuid) to authenticated;

-- A forwarded code alone no longer grants a different account access.
-- The trusted invitation UI must resolve a verified recipient identity first.
alter table public.wb_invites add column recipient_id uuid references auth.users(id);
-- Old, unbound invitations are invalidated; none exist in a deployed service.
delete from public.wb_invites;
alter table public.wb_invites alter column recipient_id set not null;
drop function public.wb_create_invite(uuid,text,text);
create function public.wb_create_invite(target uuid, person_name text, person_role text, recipient uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare raw_code text; expiry timestamptz:=now()+interval '48 hours'; seats integer; occupied integer;
begin
 if private.wb_role(target) is null or private.wb_role(target) not in ('owner','admin') then raise exception 'admin required'; end if;
 if person_role not in ('editor','viewer') or recipient is null or not exists(select 1 from auth.users where id=recipient) then raise exception 'invalid recipient or role'; end if;
 select o.seats into seats from public.wb_organizations o where o.id=target for update;
 if exists(select 1 from public.wb_memberships where org_id=target and user_id=recipient) then raise exception 'already a member'; end if;
 delete from public.wb_invites where org_id=target and expires_at<=now();
 select (select count(*) from public.wb_memberships where org_id=target)+(select count(*) from public.wb_invites where org_id=target) into occupied;
 if occupied>=seats then raise exception 'seat limit reached'; end if;
 raw_code:=pg_catalog.encode(extensions.gen_random_bytes(32),'hex');
 insert into public.wb_invites(org_id,code_hash,display_name,role,expires_at,recipient_id) values(target,extensions.digest(raw_code,'sha256'),person_name,person_role,expiry,recipient);
 return jsonb_build_object('code',raw_code,'expiresAt',expiry);
end $$;
create or replace function public.wb_accept_invite(raw_code text) returns uuid
language plpgsql security definer set search_path='' as $$
declare target uuid; invitation public.wb_invites%rowtype; seats integer;
begin
 if auth.uid() is null then raise exception 'authentication required'; end if;
 if length(raw_code)<>64 then raise exception 'invalid invitation'; end if;
 select org_id into target from public.wb_invites where code_hash=extensions.digest(raw_code,'sha256');
 if target is null then raise exception 'invalid invitation'; end if;
 select o.seats into seats from public.wb_organizations o where o.id=target for update;
 select * into invitation from public.wb_invites where code_hash=extensions.digest(raw_code,'sha256') and expires_at>now() for update;
 if not found then raise exception 'expired or used invitation'; end if;
 if invitation.recipient_id<>auth.uid() then raise exception 'invalid invitation'; end if;
 if (select count(*) from public.wb_memberships where org_id=target)>=seats then raise exception 'seat limit reached'; end if;
 insert into public.wb_memberships(org_id,user_id,display_name,role) values(target,auth.uid(),invitation.display_name,invitation.role);
 delete from public.wb_invites where id=invitation.id;
 return target;
end $$;
revoke all on function public.wb_create_invite(uuid,text,text,uuid) from public,anon;
grant execute on function public.wb_create_invite(uuid,text,text,uuid) to authenticated;
commit;
