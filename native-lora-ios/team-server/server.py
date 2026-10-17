"""Werkbeleg pilot: one business per database, up to 20 named bearer tokens.
Run only behind an HTTPS reverse proxy. Standard library, no external packages.
"""
import argparse
import hashlib
import json
import os
import secrets
import sqlite3
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

LIMIT = 30 * 1024 * 1024
EMPTY = dict(schema=1, company='', customers=[], jobs=[], reports=[])


def connect(path):
    c = sqlite3.connect(path, timeout=15)
    c.execute('PRAGMA journal_mode=WAL')
    c.execute('CREATE TABLE IF NOT EXISTS members(name TEXT PRIMARY KEY, digest TEXT UNIQUE, role TEXT NOT NULL)')
    c.execute('CREATE TABLE IF NOT EXISTS snapshot(id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER, body TEXT)')
    c.execute('INSERT OR IGNORE INTO snapshot VALUES(1,0,?)', (json.dumps(EMPTY),))
    c.execute('CREATE TABLE IF NOT EXISTS history(version INTEGER PRIMARY KEY, author TEXT, body TEXT, created TEXT DEFAULT CURRENT_TIMESTAMP)')
    c.commit()
    return c


def add_member(path, name, role):
    if role not in ('editor', 'reader') or not name.strip():
        raise ValueError('name and editor/reader role required')
    token = secrets.token_urlsafe(32)
    with connect(path) as c:
        if not c.execute('SELECT 1 FROM members WHERE name=?', (name,)).fetchone() and c.execute('SELECT count(*) FROM members').fetchone()[0] >= 20:
            raise ValueError('20 member limit reached')
        c.execute('INSERT OR REPLACE INTO members VALUES(?,?,?)', (name, hashlib.sha256(token.encode()).hexdigest(), role))
    return token


def validate(w):
    if not isinstance(w, dict) or w.get('schema') != 1 or not isinstance(w.get('company'), str):
        raise ValueError('unsupported schema')
    for field in ('customers', 'jobs', 'reports'):
        rows = w.get(field)
        if not isinstance(rows, list) or len(rows) > 10000 or any(not isinstance(r, dict) or not isinstance(r.get('id'), str) for r in rows):
            raise ValueError('invalid collection')
        if len({r['id'].lower() for r in rows}) != len(rows):
            raise ValueError('duplicate IDs')
    customers = {r['id'].lower() for r in w['customers']}
    jobs = {r['id'].lower() for r in w['jobs']}
    if any(str(r.get('customerID', '')).lower() not in customers for r in w['jobs']):
        raise ValueError('orphan job')
    if any(str(r.get('jobID', '')).lower() not in jobs for r in w['reports']):
        raise ValueError('orphan report')


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # never log tokens, customers or report bodies

    def reply(self, code, payload, role=None):
        data = json.dumps(payload, allow_nan=False).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Connection', 'close')
        if role:
            self.send_header('X-Role', role)
        self.end_headers()
        self.wfile.write(data)

    def handle_workspace(self, write=False):
        self.connection.settimeout(30)
        if self.path != '/workspace':
            return self.reply(404, {'error': 'not found'})
        auth = self.headers.get('Authorization', '')
        if not auth.startswith('Bearer ') or len(auth) > 512:
            return self.reply(401, {'error': 'unauthorized'})
        digest = hashlib.sha256(auth[7:].encode()).hexdigest()
        with connect(self.server.database) as c:
            member = c.execute('SELECT name,role FROM members WHERE digest=?', (digest,)).fetchone()
            if not member:
                return self.reply(401, {'error': 'unauthorized'})
            if not write:
                version, body = c.execute('SELECT version,body FROM snapshot WHERE id=1').fetchone()
                return self.reply(200, {'version': version, 'workspace': json.loads(body)}, member[1])
            if member[1] != 'editor':
                return self.reply(403, {'error': 'read only'})
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length <= LIMIT:
                    return self.reply(413, {'error': 'snapshot exceeds 30 MiB'})
                raw = self.rfile.read(length)
                if len(raw) != length:
                    raise ValueError('truncated body')
                payload = json.loads(raw, parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite number')))
                w = payload['workspace']; validate(w)
                if type(payload.get('version')) is not int or payload['version'] < 0:
                    raise ValueError('invalid version')
                body = json.dumps(w, allow_nan=False)
            except (ValueError, KeyError, TypeError):
                return self.reply(400, {'error': 'invalid snapshot'})
            c.execute('BEGIN IMMEDIATE')
            version = c.execute('SELECT version FROM snapshot WHERE id=1').fetchone()[0]
            if payload['version'] != version:
                return self.reply(409, {'error': 'version conflict', 'version': version})
            c.execute('INSERT INTO history(version,author,body) SELECT version,?,body FROM snapshot WHERE id=1', (member[0],))
            c.execute('UPDATE snapshot SET version=?,body=? WHERE id=1', (version + 1, body))
            # Keep the last 10 revisions; operator must also maintain external backups.
            c.execute('DELETE FROM history WHERE version < ?', (version - 9,))
            c.commit()
            return self.reply(200, {'version': version + 1, 'workspace': w}, member[1])

    def do_GET(self):
        self.handle_workspace()

    def do_PUT(self):
        self.handle_workspace(True)


def serve(database, host='127.0.0.1', port=8787):
    connect(database).close()
    server = ThreadingHTTPServer((host, port), Handler)
    server.database = database
    return server


if __name__ == '__main__':
    os.umask(0o077)
    p = argparse.ArgumentParser()
    p.add_argument('--database', default='werkbeleg.sqlite3')
    p.add_argument('--add-member'); p.add_argument('--revoke-member')
    p.add_argument('--role', choices=['editor', 'reader'], default='editor')
    p.add_argument('--port', type=int, default=8787)
    args = p.parse_args()
    if args.add_member:
        print(add_member(args.database, args.add_member, args.role))
    elif args.revoke_member:
        with connect(args.database) as c:
            c.execute('DELETE FROM members WHERE name=?', (args.revoke_member,))
    else:
        serve(args.database, port=args.port).serve_forever()
