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
    def test_wrong_route_and_body_limit(self):
        old=self.url;self.url += '/unknown'
        self.assertEqual(self.request(self.editor)[0],404);self.url=old
        req=urllib.request.Request(self.url,data=b'',method='PUT',headers={'Authorization':'Bearer '+self.editor,'Content-Length':str(31*1024*1024)})
        with self.assertRaises(urllib.error.HTTPError) as e:urllib.request.urlopen(req, timeout=5)
        self.assertEqual(e.exception.code,413)

if __name__ == '__main__':unittest.main()
