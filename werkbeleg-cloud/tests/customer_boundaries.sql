\set ON_ERROR_STOP on
set role authenticated;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000001';
select public.wb_test_assert(public.wb_import_customers('11111111-1111-1111-1111-111111111111','[{"name":"Import A","external_id":"00042","source":"CSV","profile":{"postalCode":"00123"}}]')=1,'owner imports structured customer atomically');
select public.wb_test_assert((select count(*)=1 from public.wb_customers where profile->>'postalCode'='00123'),'leading zero preserved in imported profile');
do $$declare rejected boolean:=false; begin
 begin perform public.wb_import_customers('22222222-2222-2222-2222-222222222222','[{"name":"Foreign"}]'); exception when raise_exception then rejected:=SQLERRM='admin required'; end;
 perform public.wb_test_assert(rejected,'import into foreign business denied');
end $$;
do $$declare rejected boolean:=false; begin
 begin perform public.wb_import_customers('11111111-1111-1111-1111-111111111111','[{"name":"Spoof","org_id":"22222222-2222-2222-2222-222222222222"}]'); exception when raise_exception then rejected:=SQLERRM='invalid customer identity'; end;
 perform public.wb_test_assert(rejected,'import cannot supply tenant identity');
end $$;
do $$declare rejected boolean:=false; begin
 begin perform public.wb_import_customers('11111111-1111-1111-1111-111111111111','[{"name":"Duplicate","external_id":"00042","source":"CSV"}]'); exception when unique_violation then rejected:=true; end;
 perform public.wb_test_assert(rejected,'source identifier duplicate cannot overwrite customer');
end $$;
do $$declare rejected boolean:=false; begin
 begin perform public.wb_import_customers('11111111-1111-1111-1111-111111111111','[{"name":"ROLLBACK-ME"},{"name":""}]'); exception when check_violation then rejected:=true; end;
 perform public.wb_test_assert(rejected and not exists(select 1 from public.wb_customers where name='ROLLBACK-ME'),'invalid batch rolls back all inserted rows');
end $$;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000003';
do $$declare rejected boolean:=false; begin
 begin perform public.wb_import_customers('11111111-1111-1111-1111-111111111111','[{"name":"Editor mass import"}]'); exception when raise_exception then rejected:=SQLERRM='admin required'; end;
 perform public.wb_test_assert(rejected,'editor cannot use admin bulk import');
end $$;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000004';
select public.wb_test_assert(public.wb_import_customers('22222222-2222-2222-2222-222222222222','[{"name":"Import B","external_id":"00042","source":"CSV"}]')=1,'same external customer number allowed independently in another business');
select public.wb_create_invite('22222222-2222-2222-2222-222222222222','Bound recipient','viewer','00000000-0000-0000-0000-000000000008')->>'code' as bound_code \gset
set wb.test.bound=:'bound_code';
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000009';
do $$declare rejected boolean:=false; begin
 begin perform public.wb_accept_invite(current_setting('wb.test.bound')); exception when raise_exception then rejected:=SQLERRM='invalid invitation'; end;
 perform public.wb_test_assert(rejected,'forwarded invitation cannot be claimed by a different identity');
end $$;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000008';
select public.wb_test_assert(public.wb_accept_invite(current_setting('wb.test.bound'))='22222222-2222-2222-2222-222222222222','intended recipient can still claim invitation');
reset role;
insert into public.wb_memberships values
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-000000000007','Dual member','editor'),
 ('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-000000000007','Dual member','editor');
set role authenticated;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000007';
do $$declare rejected boolean:=false; begin
 begin update public.wb_customers set org_id='22222222-2222-2222-2222-222222222222' where name='Import A'; exception when insufficient_privilege then rejected:=true; end;
 perform public.wb_test_assert(rejected,'dual membership cannot move customers between tenants');
end $$;
do $$declare rejected boolean:=false; begin
 begin update public.wb_projects set org_id='22222222-2222-2222-2222-222222222222' where title='Project A'; exception when insufficient_privilege then rejected:=true; end;
 perform public.wb_test_assert(rejected,'dual membership cannot move projects between tenants');
end $$;
do $$declare rejected boolean:=false; begin
 begin insert into public.wb_subscriptions values('11111111-1111-1111-1111-111111111111','forged','plan20','active',now(),now()+interval '1 year'); exception when insufficient_privilege then rejected:=true; end;
 perform public.wb_test_assert(rejected,'client cannot grant itself a paid subscription');
end $$;
reset role;
insert into public.wb_subscriptions values('11111111-1111-1111-1111-111111111111','synthetic-transaction','plan5','active',now(),now()+interval '1 month');
do $$declare rejected boolean:=false; begin
 begin insert into public.wb_subscriptions values('22222222-2222-2222-2222-222222222222','synthetic-transaction','plan5','active',now(),now()+interval '1 month'); exception when unique_violation then rejected:=true; end;
 perform public.wb_test_assert(rejected,'same purchase cannot belong to two businesses');
end $$;
set role authenticated;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000004';
select public.wb_test_assert((select count(*)=0 from public.wb_subscriptions),'owner cannot read another business subscription');
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000001';
do $$declare rejected boolean:=false; begin
 begin perform public.wb_remove_member('11111111-1111-1111-1111-111111111111',auth.uid()); exception when raise_exception then rejected:=SQLERRM='protected member'; end;
 perform public.wb_test_assert(rejected,'owner cannot accidentally remove ownership');
end $$;
select public.wb_test_assert(public.wb_remove_member('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-000000000003'),'owner can revoke editor membership');
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000003';
select public.wb_test_assert((select count(*)=0 from public.wb_customers),'revoked member loses access with the same authenticated identity');
do $$declare rejected boolean:=false; begin
 begin perform public.wb_reserve_asset('11111111-1111-1111-1111-111111111111','11111111-0000-0000-0000-000000000010',1,'image/jpeg'); exception when raise_exception then rejected:=SQLERRM='write access required'; end;
 perform public.wb_test_assert(rejected,'revoked member cannot start file upload');
end $$;
reset role;
select 'PASSED ASSERTIONS: '||count(*) from public.wb_test_results;
