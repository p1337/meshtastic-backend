\set ON_ERROR_STOP on
create table public.wb_test_results(label text);
create function public.wb_test_assert(value boolean,label text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if value is distinct from true then raise exception 'FAIL: %',label; end if;
 insert into public.wb_test_results values(label);
 raise notice 'PASS: %',label;
end $$;
insert into auth.users(id) select ('00000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid from generate_series(1,9)i;
insert into public.wb_organizations(id,name,owner_id) values
 ('11111111-1111-1111-1111-111111111111','Synthetic Business A','00000000-0000-0000-0000-000000000001'),
 ('22222222-2222-2222-2222-222222222222','Synthetic Business B','00000000-0000-0000-0000-000000000004');
insert into public.wb_memberships values
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-000000000001','Owner A','owner'),
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-000000000002','Reader A','viewer'),
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-000000000003','Editor A','editor'),
 ('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-000000000004','Owner B','owner');
insert into public.wb_customers(id,org_id,name) values
 ('11111111-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','Customer A'),
 ('22222222-0000-0000-0000-000000000001','22222222-2222-2222-2222-222222222222','Customer B');
insert into public.wb_projects(id,org_id,customer_id,title) values
 ('11111111-0000-0000-0000-000000000010','11111111-1111-1111-1111-111111111111','11111111-0000-0000-0000-000000000001','Project A'),
 ('22222222-0000-0000-0000-000000000010','22222222-2222-2222-2222-222222222222','22222222-0000-0000-0000-000000000001','Project B');
set role authenticated;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000001';
select public.wb_test_assert((select count(*)=1 from public.wb_organizations),'owner sees only own business');
select public.wb_test_assert((select count(*)=1 from public.wb_customers),'owner sees only own customers');
select public.wb_test_assert((select count(*)=1 from public.wb_projects),'owner sees only own projects');
select public.wb_test_assert((select count(*)=3 from public.wb_memberships),'owner sees own members only');
do $$declare rejected boolean:=false; begin
 begin update public.wb_organizations set seats=20; exception when insufficient_privilege then rejected:=true; end;
 perform public.wb_test_assert(rejected,'client cannot upgrade its own package');
end$$;
do $$declare rejected boolean:=false; begin
 begin insert into public.wb_memberships values('22222222-2222-2222-2222-222222222222',auth.uid(),'Intruder','owner'); exception when insufficient_privilege then rejected:=true; end;
 perform public.wb_test_assert(rejected,'client cannot add its own membership');
end$$;
do $$declare rejected boolean:=false; begin
 begin insert into public.wb_projects(org_id,customer_id,title) values('22222222-2222-2222-2222-222222222222','22222222-0000-0000-0000-000000000001','Foreign write'); exception when insufficient_privilege then rejected:=true; end;
 perform public.wb_test_assert(rejected,'foreign project insert denied');
end$$;
do $$declare rejected boolean:=false; begin
 begin insert into public.wb_projects(org_id,customer_id,title) values('11111111-1111-1111-1111-111111111111','22222222-0000-0000-0000-000000000001','Cross tenant reference'); exception when foreign_key_violation then rejected:=true; end;
 perform public.wb_test_assert(rejected,'foreign customer cannot be linked into own project');
end$$;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000002';
select public.wb_test_assert((select count(*)=1 from public.wb_customers),'viewer can read own customers');
do $$declare rejected boolean:=false; begin
 begin insert into public.wb_customers(org_id,name) values('11111111-1111-1111-1111-111111111111','Forbidden'); exception when insufficient_privilege then rejected:=true; end;
 perform public.wb_test_assert(rejected,'viewer cannot write customers');
end$$;
do $$declare rejected boolean:=false; begin
 begin perform public.wb_create_invite('11111111-1111-1111-1111-111111111111','Forbidden','editor'); exception when raise_exception then rejected:=SQLERRM='admin required'; end;
 perform public.wb_test_assert(rejected,'viewer cannot invite');
end$$;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000003';
insert into public.wb_messages(org_id,project_id,body) values('11111111-1111-1111-1111-111111111111','11111111-0000-0000-0000-000000000010','Synthetic chat');
select public.wb_test_assert((select count(*)=1 from public.wb_messages where author_id=auth.uid()),'chat uses authenticated author');
do $$declare rejected boolean:=false; begin
 begin insert into public.wb_messages(org_id,project_id,author_id,body) values('11111111-1111-1111-1111-111111111111','11111111-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000001','Forged author'); exception when insufficient_privilege then rejected:=true; end;
 perform public.wb_test_assert(rejected,'chat author forgery denied');
end$$;
do $$declare rejected boolean:=false; begin
 begin insert into public.wb_messages(org_id,project_id,body,created_at) values('11111111-1111-1111-1111-111111111111','11111111-0000-0000-0000-000000000010','Forged time','2000-01-01'); exception when insufficient_privilege then rejected:=true; end;
 perform public.wb_test_assert(rejected,'chat creation time cannot be supplied by client');
end$$;
do $$declare rejected boolean:=false; begin
 begin update public.wb_messages set body='Overwritten'; exception when insufficient_privilege then rejected:=true; end;
 perform public.wb_test_assert(rejected,'chat messages are append only');
end$$;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000004';
select public.wb_test_assert((select count(*)=0 from public.wb_messages),'business B cannot read business A chat');
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000001';
select public.wb_create_invite('11111111-1111-1111-1111-111111111111','Invite 1','editor')->>'code' as code1 \gset
select public.wb_create_invite('11111111-1111-1111-1111-111111111111','Invite 2','viewer')->>'code' as code2 \gset
set wb.test.code1=:'code1';
set wb.test.code2=:'code2';
select public.wb_test_assert((select count(*)=2 from public.wb_invites),'two pending invitations reserve remaining seats');
do $$declare rejected boolean:=false; begin
 begin perform public.wb_create_invite('11111111-1111-1111-1111-111111111111','Overflow','editor'); exception when raise_exception then rejected:=SQLERRM='seat limit reached'; end;
 perform public.wb_test_assert(rejected,'pending invitations enforce five person limit');
end$$;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000005';
select public.wb_accept_invite(current_setting('wb.test.code1')) as joined \gset
select public.wb_test_assert((select count(*)=1 from public.wb_memberships where user_id=auth.uid()),'invitation creates authenticated membership');
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000006';
do $$declare rejected boolean:=false; begin
 begin perform public.wb_accept_invite(current_setting('wb.test.code1')); exception when raise_exception then rejected:=SQLERRM='invalid invitation'; end;
 perform public.wb_test_assert(rejected,'invitation cannot be redeemed twice');
end$$;
reset role;
update public.wb_invites set expires_at=now()-interval '1 minute';
set role authenticated;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000006';
do $$declare rejected boolean:=false; begin
 begin perform public.wb_accept_invite(current_setting('wb.test.code2')); exception when raise_exception then rejected:=SQLERRM='expired or used invitation'; end;
 perform public.wb_test_assert(rejected,'expired invitation cannot be redeemed');
end$$;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000003';
select public.wb_reserve_asset('11111111-1111-1111-1111-111111111111','11111111-0000-0000-0000-000000000010',20000000,'image/jpeg')->>'path' as asset_path \gset
set wb.test.path=:'asset_path';
select public.wb_test_assert((select reserved_bytes=20000000 from public.wb_organizations),'media reservation counts bytes');
do $$declare rejected boolean:=false; begin
 begin insert into storage.objects(bucket_id,name) values('werkbeleg-media',current_setting('wb.test.path')); exception when insufficient_privilege then rejected:=true; end;
 perform public.wb_test_assert(rejected,'direct storage upload disabled until trusted uploader is installed');
end$$;
reset role;
update public.wb_organizations set storage_limit_bytes=20000001 where id='11111111-1111-1111-1111-111111111111';
insert into storage.objects(bucket_id,name) values('werkbeleg-media',current_setting('wb.test.path'));
set role authenticated;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000003';
select public.wb_test_assert((select count(*)=0 from storage.objects),'unfinalized upload is not readable');
do $$declare rejected boolean:=false; begin
 begin perform public.wb_reserve_asset('11111111-1111-1111-1111-111111111111','11111111-0000-0000-0000-000000000010',2,'image/jpeg'); exception when raise_exception then rejected:=SQLERRM='storage limit reached'; end;
 perform public.wb_test_assert(rejected,'storage quota rejects even a two byte overflow');
end$$;
reset role;
update public.wb_assets set state='uploaded';
set role authenticated;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000003';
select public.wb_test_assert((select count(*)=1 from storage.objects),'member reads finalized own media');
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000004';
select public.wb_test_assert((select count(*)=0 from storage.objects),'foreign business cannot read private media');
reset role;
set role anon;
do $$declare rejected boolean:=false; begin
 begin perform count(*) from public.wb_customers; exception when insufficient_privilege then rejected:=true; end;
 perform public.wb_test_assert(rejected,'anonymous users cannot read customers');
end$$;
reset role;
select public.wb_test_assert((select public is false from storage.buckets where id='werkbeleg-media'),'media bucket is private');
select public.wb_test_assert((select count(*)=8 from pg_tables where schemaname='public' and tablename in ('wb_organizations','wb_memberships','wb_customers','wb_projects','wb_reports','wb_messages','wb_invites','wb_assets') and rowsecurity),'all eight business tables enforce RLS');
select public.wb_test_assert((select count(*)=1 from pg_indexes where indexname='wb_messages_cursor'),'chat has an incremental cursor index');
select 'PASSED ASSERTIONS: '||count(*) from public.wb_test_results;
