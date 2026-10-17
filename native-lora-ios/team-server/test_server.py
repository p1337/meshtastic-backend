import copy
from concurrent.futures import ThreadPoolExecutor
import json
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from server import EMPTY, add_member, connect, serve

class TeamTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = str(Path(self.tmp.name) / 'test.sqlite3')
        with connect(self.db) as c:c.execute('UPDATE settings SET seats=20 WHERE id=1')
        self.editor = add_member(self.db, 'Editor', 'editor')
        self.reader = add_member(self.db, 'Reader', 'reader')
        self.server = serve(self.db, port=0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True); self.thread.start()
        self.url = 'http://127.0.0.1:%s/workspace' % self.server.server_port
    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join(); self.tmp.cleanup()
    def request(self, token, payload=None):
        req = urllib.request.Request(self.url, data=None if payload is None else json.dumps(payload).encode(), method='GET' if payload is None else 'PUT', headers={'Authorization': 'Bearer '+token})
        try:
            with urllib.request.urlopen(req, timeout=5) as r: return r.status, json.load(r), r.headers
        except urllib.error.HTTPError as e:
            return e.code, json.load(e), e.headers
    def test_auth_and_roles(self):
        self.assertEqual(self.request('bad')[0], 401)
        code, data, headers = self.request(self.reader)
        self.assertEqual((code,data['version'],headers['X-Role']), (200,0,'reader'))
        self.assertEqual(self.request(self.reader,dict(version=0,workspace=EMPTY))[0],403)
    def test_conflict_and_history(self):
        w=copy.deepcopy(EMPTY);w['company']='Żółć & Söhne'
        self.assertEqual(self.request(self.editor,dict(version=0,workspace=w))[0],200)
        self.assertEqual(self.request(self.editor,dict(version=0,workspace=EMPTY))[0],409)
        self.assertEqual(self.request(self.reader)[1]['workspace']['company'],w['company'])
        with connect(self.db) as c:
            self.assertEqual(c.execute('SELECT count(*) FROM history').fetchone()[0],1)
    def test_invalid_snapshot(self):
        for w in [dict(EMPTY,schema=2), dict(EMPTY,customers=None), dict(EMPTY,jobs=[dict(id='a',customerID='missing')])]:
            self.assertEqual(self.request(self.editor,dict(version=0,workspace=w))[0],400)
    def test_rotate_revoke_and_limit(self):
        add_member(self.db,'Editor','editor')
        self.assertEqual(self.request(self.editor)[0],401)
        for i in range(18):add_member(self.db,'Member%d'%i,'reader')
        with self.assertRaises(ValueError):add_member(self.db,'Twenty one','editor')
        with connect(self.db) as c:c.execute('DELETE FROM members WHERE name=?',('Reader',))
        self.assertEqual(self.request(self.reader)[0],401)
    def test_simultaneous_writers_do_not_overwrite(self):
        def upload(name):
            w = dict(EMPTY,company=name)
            return self.request(self.editor,dict(version=0,workspace=w))[0]
        with ThreadPoolExecutor(max_workers=2) as pool:
            codes = list(pool.map(upload,['A','B']))
        self.assertEqual(sorted(codes),[200,409])
        self.assertEqual(self.request(self.reader)[1]['version'],1)
    def test_separate_business_databases_reject_foreign_tokens(self):
        other = str(Path(self.tmp.name) / 'other.sqlite3')
        foreign = add_member(other,'Someone','editor')
        self.assertEqual(self.request(foreign)[0],401)
    def test_nonfinite_json_and_bad_version_rejected(self):
        self.assertEqual(self.request(self.editor,dict(version=True,workspace=EMPTY))[0],400)
        w = dict(EMPTY,unexpected=float('nan'))
        self.assertEqual(self.request(self.editor,dict(version=0,workspace=w))[0],400)
    def api(self,path,token=None,payload=None,method='GET'):
        headers = {} if token is None else {'Authorization':'Bearer '+token}
        req=urllib.request.Request(self.url.removesuffix('/workspace')+path,data=None if payload is None else json.dumps(payload).encode(),method=method,headers=headers)
        try:
            with urllib.request.urlopen(req,timeout=5) as r:return r.status,json.load(r)
        except urllib.error.HTTPError as e:return e.code,json.load(e)
    def test_invites_reserve_plan_seats_and_redeem_once(self):
        owner=add_member(self.db,'Owner','admin')
        with connect(self.db) as c:c.execute('UPDATE settings SET seats=5 WHERE id=1')
        self.assertEqual(self.api('/invites',self.editor,dict(name='Not allowed',role='editor'),'POST')[0],403)
        codes=[]
        for name in ['Person A','Person B']:
            status,invite=self.api('/invites',owner,dict(name=name,role='editor'),'POST');self.assertEqual(status,200);codes.append(invite['code'])
        self.assertEqual(self.api('/invites',owner,dict(name='Too many',role='editor'),'POST')[0],409)
        self.assertEqual(self.api('/team',owner)[1]['pendingInvites'],2)
        status,result=self.api('/join',payload=dict(code=codes[0]),method='POST');self.assertEqual(status,200)
        self.assertEqual(self.api('/team',result['token'])[1]['memberCount'],4)
        self.assertEqual(self.api('/join',payload=dict(code=codes[0]),method='POST')[0],410)
        with connect(self.db) as c:c.execute('UPDATE invites SET expires=0')
        self.assertEqual(self.api('/join',payload=dict(code=codes[1]),method='POST')[0],410)
    def test_chat_concurrent_messages_idempotency_and_server_author(self):
        import uuid
        customer=str(uuid.uuid4());project=str(uuid.uuid4())
        w=dict(EMPTY,customers=[dict(id=customer)],jobs=[dict(id=project,customerID=customer)])
        self.assertEqual(self.request(self.editor,dict(version=0,workspace=w))[0],200)
        def post(i):return self.api('/messages',self.editor,dict(id=str(uuid.uuid4()),jobID=project,text='Message '+str(i),author='Spoof'),'POST')[0]
        with ThreadPoolExecutor(max_workers=2) as pool:self.assertEqual(list(pool.map(post,[1,2])),[200,200])
        payload=dict(id=str(uuid.uuid4()),jobID=project,text='Once')
        self.assertEqual(self.api('/messages',self.editor,payload,'POST')[0],200)
        self.assertEqual(self.api('/messages',self.editor,payload,'POST')[0],200)
        code,messages=self.api('/messages?project='+project,self.reader)
        self.assertEqual(code,200);self.assertEqual(len(messages),3)
        self.assertTrue(all(m['author']=='Editor' for m in messages))
        self.assertEqual(self.api('/messages',self.reader,payload,'POST')[0],403)
        self.assertEqual(self.request(self.editor)[1]['version'],1) # chat does not invalidate report CAS versions
        self.assertEqual(len(self.request(self.reader)[1]['workspace']['messages']),3)
        self.assertEqual(self.request(self.editor,dict(version=1,workspace=w))[0],200)
        self.assertEqual(len(self.api('/messages?project='+project,self.reader)[1]),3) # snapshot uploads cannot erase chat
    def test_all_three_seat_limits(self):
        for size in [5,10,20]:
            with connect(self.db) as c:c.execute('UPDATE settings SET seats=? WHERE id=1',(size,))
            self.assertEqual(self.api('/team',self.editor)[1]['seatLimit'],size)
    def test_wrong_route_and_body_limit(self):
        old=self.url;self.url += '/unknown'
        self.assertEqual(self.request(self.editor)[0],404);self.url=old
        req=urllib.request.Request(self.url,data=b'',method='PUT',headers={'Authorization':'Bearer '+self.editor,'Content-Length':str(31*1024*1024)})
        with self.assertRaises(urllib.error.HTTPError) as e:urllib.request.urlopen(req, timeout=5)
        self.assertEqual(e.exception.code,413)

if __name__ == '__main__':unittest.main()
