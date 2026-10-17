"""Werkbeleg pilot: one business per database, up to 20 named bearer tokens.
Run only behind an HTTPS reverse proxy. Standard library, no external packages.
"""
import argparse
import hashlib
import json
import os
import secrets
import time
import uuid
import urllib.parse
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
    c.execute('CREATE TABLE IF NOT EXISTS settings(id INTEGER PRIMARY KEY CHECK(id=1), seats INTEGER)')
    c.execute('INSERT OR IGNORE INTO settings VALUES(1,5)')
    c.execute('CREATE TABLE IF NOT EXISTS invites(id TEXT PRIMARY KEY, digest TEXT UNIQUE, name TEXT, role TEXT, expires REAL)')
    c.execute('CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY, project TEXT, author TEXT, body TEXT, created REAL)')
    c.commit()
    return c


def add_member(path, name, role):
    if role not in ('admin', 'editor', 'reader') or not name.strip():
        raise ValueError('name and admin/editor/reader role required')
    token = secrets.token_urlsafe(32)
    with connect(path) as c:
        if not c.execute('SELECT 1 FROM members WHERE name=?', (name,)).fetchone() and c.execute('SELECT count(*) FROM members').fetchone()[0] >= c.execute('SELECT seats FROM settings WHERE id=1').fetchone()[0]:
            raise ValueError('plan member limit reached')
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
                return self.reply(200, {'version': version, 'workspace': self.with_messages(c, json.loads(body))}, member[1])
            if member[1] not in ('admin', 'editor'):
                return self.reply(403, {'error': 'read only'})
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length <= LIMIT:
                    return self.reply(413, {'error': 'snapshot exceeds 30 MiB'})
                raw = self.rfile.read(length)
                if len(raw) != length:
                    raise ValueError('truncated body')
                payload = json.loads(raw, parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite number')))
                w = payload['workspace']; validate(w); w.pop('messages', None)
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
            return self.reply(200, {'version': version + 1, 'workspace': self.with_messages(c, w)}, member[1])

    def auth(self, c):
        auth = self.headers.get('Authorization', '')
        if not auth.startswith('Bearer ') or len(auth) > 512:
            return None
        return c.execute('SELECT name,role FROM members WHERE digest=?', (hashlib.sha256(auth[7:].encode()).hexdigest(),)).fetchone()

    def read_json(self):
        length = int(self.headers.get('Content-Length', '0'))
        if not 0 < length <= 16384:
            raise ValueError('invalid body size')
        data = json.loads(self.rfile.read(length))
        if not isinstance(data, dict):
            raise ValueError('object required')
        return data

    def chat_rows(self, c, projects):
        rows = c.execute('SELECT id,project,author,body,created FROM messages ORDER BY created,id').fetchall()
        return [dict(id=r[0],jobID=r[1],author=r[2],text=r[3],createdAt=r[4]) for r in rows if r[1].lower() in projects]

    def with_messages(self, c, workspace):
        workspace['messages'] = self.chat_rows(c, {r['id'].lower() for r in workspace['jobs']})
        return workspace

    def collaboration(self):
        self.connection.settimeout(30)
        url = urllib.parse.urlsplit(self.path)
        with connect(self.server.database) as c:
            if self.command == 'POST' and url.path == '/join':
                try:
                    payload = self.read_json(); code = payload['code']
                    if not isinstance(code, str) or not 10 <= len(code) <= 512:
                        raise ValueError('invalid code')
                except (KeyError, TypeError, ValueError):
                    return self.reply(400, {'error':'invalid invitation'})
                c.execute('BEGIN IMMEDIATE')
                invite = c.execute('SELECT id,name,role FROM invites WHERE digest=? AND expires>?', (hashlib.sha256(code.encode()).hexdigest(), time.time())).fetchone()
                if not invite:
                    return self.reply(410, {'error':'invitation expired or used'})
                if c.execute('SELECT 1 FROM members WHERE name=?', (invite[1],)).fetchone():
                    return self.reply(409, {'error':'member already exists'})
                if c.execute('SELECT count(*) FROM members').fetchone()[0] >= c.execute('SELECT seats FROM settings WHERE id=1').fetchone()[0]:
                    return self.reply(409, {'error':'plan seat limit reached'})
                token = secrets.token_urlsafe(32)
                c.execute('INSERT INTO members VALUES(?,?,?)', (invite[1], hashlib.sha256(token.encode()).hexdigest(), invite[2]))
                c.execute('DELETE FROM invites WHERE id=?', (invite[0],)); c.commit()
                return self.reply(200, dict(token=token,name=invite[1],role=invite[2]))
            member = self.auth(c)
            if not member:
                return self.reply(401, {'error':'unauthorized'})
            if self.command == 'GET' and url.path == '/team':
                seats = c.execute('SELECT seats FROM settings WHERE id=1').fetchone()[0]
                members = [dict(name=n,role=r) for n,r in c.execute('SELECT name,role FROM members ORDER BY name')]
                pending = c.execute('SELECT count(*) FROM invites WHERE expires>?', (time.time(),)).fetchone()[0]
                return self.reply(200,dict(seatLimit=seats,memberCount=len(members),pendingInvites=pending,role=member[1],members=members))
            if self.command == 'POST' and url.path == '/invites':
                if member[1] != 'admin':
                    return self.reply(403, {'error':'only owner/admin can invite'})
                try:
                    payload = self.read_json(); name = payload['name'].strip(); role = payload['role']
                    if not 1 <= len(name) <= 80 or role not in ('editor','reader'):
                        raise ValueError('invalid name or role')
                except (KeyError, TypeError, ValueError, AttributeError):
                    return self.reply(400, {'error':'invalid invitation'})
                c.execute('BEGIN IMMEDIATE')
                c.execute('DELETE FROM invites WHERE expires<=?', (time.time(),))
                seats = c.execute('SELECT seats FROM settings WHERE id=1').fetchone()[0]
                occupied = c.execute('SELECT count(*) FROM members').fetchone()[0] + c.execute('SELECT count(*) FROM invites').fetchone()[0]
                if occupied >= seats:
                    return self.reply(409, {'error':'plan seat limit reached; pending invitations reserve seats'})
                if c.execute('SELECT 1 FROM members WHERE name=?', (name,)).fetchone() or c.execute('SELECT 1 FROM invites WHERE name=?', (name,)).fetchone():
                    return self.reply(409, {'error':'name already registered or invited'})
                code = secrets.token_urlsafe(32); expires = time.time() + 48*3600
                c.execute('INSERT INTO invites VALUES(?,?,?,?,?)', (str(uuid.uuid4()),hashlib.sha256(code.encode()).hexdigest(),name,role,expires)); c.commit()
                return self.reply(200, dict(code=code,expiresAt=expires))
            if url.path == '/messages' and self.command == 'GET':
                try:
                    project = str(uuid.UUID(urllib.parse.parse_qs(url.query)['project'][0])).lower()
                except (ValueError, KeyError, IndexError):
                    return self.reply(400, {'error':'project required'})
                workspace = json.loads(c.execute('SELECT body FROM snapshot WHERE id=1').fetchone()[0])
                if project not in {r['id'].lower() for r in workspace['jobs']}:
                    return self.reply(404, {'error':'project not synchronized yet'})
                return self.reply(200, self.chat_rows(c,{project}))
            if url.path == '/messages' and self.command == 'POST':
                if member[1] not in ('editor','admin'):
                    return self.reply(403, {'error':'read only'})
                try:
                    payload = self.read_json(); mid = str(uuid.UUID(payload['id'])); project = str(uuid.UUID(payload['jobID'])); text = payload['text'].strip()
                    if not 1 <= len(text) <= 4000:
                        raise ValueError('message length')
                except (KeyError, ValueError, TypeError, AttributeError):
                    return self.reply(400, {'error':'invalid message'})
                c.execute('BEGIN IMMEDIATE')
                workspace = json.loads(c.execute('SELECT body FROM snapshot WHERE id=1').fetchone()[0])
                if project.lower() not in {r['id'].lower() for r in workspace['jobs']}:
                    return self.reply(404, {'error':'project not synchronized yet'})
                previous = c.execute('SELECT project,author,body FROM messages WHERE id=?', (mid,)).fetchone()
                if previous and previous != (project,member[0],text):
                    return self.reply(409, {'error':'message ID already used'})
                if not previous and c.execute('SELECT count(*) FROM messages').fetchone()[0] >= 10000:
                    return self.reply(409, {'error':'pilot message capacity reached'})
                c.execute('INSERT OR IGNORE INTO messages VALUES(?,?,?,?,?)', (mid,project,member[0],text,time.time()-978307200)); c.commit()
                return self.reply(200, {'saved': True})
            return self.reply(404, {'error':'not found'})

    def do_GET(self):
        if self.path == '/workspace':
            self.handle_workspace()
        else:
            self.collaboration()

    def do_PUT(self):
        self.handle_workspace(True)

    def do_POST(self):
        self.collaboration()


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
    p.add_argument('--role', choices=['admin', 'editor', 'reader'], default='editor')
    p.add_argument('--port', type=int, default=8787)
    p.add_argument('--plan', type=int, choices=[5,10,20])
    args = p.parse_args()
    if args.plan:
        with connect(args.database) as c:
            if c.execute('SELECT count(*) FROM members').fetchone()[0] > args.plan:
                raise SystemExit('Cannot downgrade below current member count')
            c.execute('UPDATE settings SET seats=? WHERE id=1',(args.plan,))
    if args.add_member:
        print(add_member(args.database, args.add_member, args.role))
    elif args.revoke_member:
        with connect(args.database) as c:
            c.execute('DELETE FROM members WHERE name=?', (args.revoke_member,))
    else:
        serve(args.database, port=args.port).serve_forever()
