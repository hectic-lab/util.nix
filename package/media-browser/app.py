#!/usr/bin/env python3
"""Matrix Media Browser - Browse local and S3 media with cross-reference."""

import os
import sys
import json
import psycopg2
import boto3
from datetime import datetime
from pathlib import Path
from urllib.parse import quote
from flask import Flask, render_template_string, send_file, jsonify, request

app = Flask(__name__)

MEDIA_STORE_PATH = os.environ.get('MEDIA_STORE_PATH', '/var/lib/matrix-synapse/media_store')
S3_BUCKET = os.environ.get('S3_BUCKET', 'matrix-hectic-lab')
S3_ENDPOINT = os.environ.get('S3_ENDPOINT', 'https://hel1.your-objectstorage.com')
S3_REGION = os.environ.get('S3_REGION', 'hel1')
S3_PREFIX = os.environ.get('S3_PREFIX', '')
DB_NAME = os.environ.get('DB_NAME', 'matrix-synapse')
DB_USER = os.environ.get('DB_USER', 'matrix-synapse')
DB_HOST = os.environ.get('DB_HOST', '/run/postgresql')
DB_PORT = int(os.environ.get('DB_PORT', '5432'))

def get_db_conn():
    return psycopg2.connect(
        dbname=DB_NAME,
        user=DB_USER,
        host=DB_HOST,
        port=DB_PORT
    )

def get_s3_client():
    return boto3.client('s3',
        endpoint_url=S3_ENDPOINT,
        aws_access_key_id=os.environ.get('ACCESS_KEY_ID', ''),
        aws_secret_access_key=os.environ.get('SECRET_ACCESS_KEY', ''),
        region_name=S3_REGION
    )

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE)

@app.route('/api/stats')
def api_stats():
    try:
        local_count = 0
        local_size = 0
        for root, dirs, files in os.walk(MEDIA_STORE_PATH):
            for f in files:
                local_count += 1
                local_size += os.path.getsize(os.path.join(root, f))

        s3 = get_s3_client()
        s3_count = 0
        s3_size = 0
        paginator = s3.get_paginator('list_objects_v2')
        list_kwargs = {'Bucket': S3_BUCKET}
        if S3_PREFIX:
            list_kwargs['Prefix'] = S3_PREFIX + '/'
        for page in paginator.paginate(**list_kwargs):
            for obj in page.get('Contents', []):
                s3_count += 1
                s3_size += obj['Size']

        conn = get_db_conn()
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*), COALESCE(SUM(media_length), 0) FROM local_media_repository")
        db_count, db_size = cur.fetchone()
        cur.execute("SELECT COUNT(*) FROM remote_media_cache")
        remote_count = cur.fetchone()[0]
        cur.close()
        conn.close()

        return jsonify({
            'local_files': local_count,
            'local_size': local_size,
            's3_objects': s3_count,
            's3_size': s3_size,
            'db_local_entries': db_count or 0,
            'db_total_size': int(db_size) if db_size else 0,
            'db_remote_entries': remote_count or 0
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/local')
def api_local():
    try:
        files = []
        for root, dirs, filenames in os.walk(MEDIA_STORE_PATH):
            for filename in filenames:
                filepath = os.path.join(root, filename)
                rel_path = os.path.relpath(filepath, MEDIA_STORE_PATH)
                stat = os.stat(filepath)
                files.append({
                    'path': rel_path,
                    'size': stat.st_size,
                    'modified': datetime.fromtimestamp(stat.st_mtime).isoformat(),
                    'full_path': filepath
                })
        return jsonify(files)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/s3')
def api_s3():
    try:
        s3 = get_s3_client()
        objects = []
        paginator = s3.get_paginator('list_objects_v2')
        list_kwargs = {'Bucket': S3_BUCKET}
        if S3_PREFIX:
            list_kwargs['Prefix'] = S3_PREFIX + '/'
        for page in paginator.paginate(**list_kwargs):
            for obj in page.get('Contents', []):
                objects.append({
                    'key': obj['Key'],
                    'size': obj['Size'],
                    'modified': obj['LastModified'].isoformat(),
                    'etag': obj['ETag'].strip('"')
                })
        return jsonify(objects)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/media-db')
def api_media_db():
    try:
        conn = get_db_conn()
        cur = conn.cursor()
        
        limit = request.args.get('limit', 1000, type=int)
        offset = request.args.get('offset', 0, type=int)
        
        cur.execute("""
            SELECT media_id, media_type, media_length, created_ts, 
                   last_access_ts, upload_name, quarantined_by 
            FROM local_media_repository 
            ORDER BY created_ts DESC 
            LIMIT %s OFFSET %s
        """, (limit, offset))
        
        rows = []
        for row in cur.fetchall():
            media_id, media_type, media_length, created_ts, last_access_ts, upload_name, quarantined = row
            media_path = f"local_content/{media_id[0:2]}/{media_id[2:4]}/{media_id[4:]}"
            local_exists = os.path.exists(os.path.join(MEDIA_STORE_PATH, media_path))
            
            rows.append({
                'media_id': media_id,
                'media_type': media_type,
                'size': media_length,
                'created': datetime.fromtimestamp(created_ts / 1000).isoformat() if created_ts else None,
                'last_access': datetime.fromtimestamp(last_access_ts / 1000).isoformat() if last_access_ts else None,
                'upload_name': upload_name,
                'quarantined': quarantined is not None,
                'local_path': media_path,
                'local_exists': local_exists
            })
        
        cur.close()
        conn.close()
        return jsonify(rows)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/sync-status')
def api_sync_status():
    try:
        local_files = set()
        for root, dirs, filenames in os.walk(MEDIA_STORE_PATH):
            for filename in filenames:
                filepath = os.path.join(root, filename)
                rel_path = os.path.relpath(filepath, MEDIA_STORE_PATH)
                local_files.add(rel_path)

        s3 = get_s3_client()
        s3_files = set()
        paginator = s3.get_paginator('list_objects_v2')
        list_kwargs = {'Bucket': S3_BUCKET}
        prefix = ''
        if S3_PREFIX:
            prefix = S3_PREFIX + '/'
            list_kwargs['Prefix'] = prefix
        for page in paginator.paginate(**list_kwargs):
            for obj in page.get('Contents', []):
                key = obj['Key']
                if prefix:
                    key = key[len(prefix):]
                s3_files.add(key)

        synced = local_files & s3_files
        local_only = local_files - s3_files
        s3_only = s3_files - local_files

        return jsonify({
            'synced_count': len(synced),
            'local_only_count': len(local_only),
            's3_only_count': len(s3_only),
            'synced': sorted(list(synced))[:100],
            'local_only': sorted(list(local_only))[:100],
            's3_only': sorted(list(s3_only))[:100]
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

def get_media_type_from_path(filepath):
    try:
        parts = filepath.split('/')
        if len(parts) >= 4 and parts[0] == 'local_content':
            media_id = parts[1] + parts[2] + parts[3]
            conn = get_db_conn()
            cur = conn.cursor()
            cur.execute(
                "SELECT media_type FROM local_media_repository WHERE media_id = %s",
                (media_id,)
            )
            row = cur.fetchone()
            cur.close()
            conn.close()
            if row:
                return row[0]
    except Exception:
        pass
    return None

@app.route('/view/local/<path:filepath>')
def view_local(filepath):
    try:
        safe_path = os.path.join(MEDIA_STORE_PATH, filepath)
        real_path = os.path.realpath(safe_path)
        real_base = os.path.realpath(MEDIA_STORE_PATH)
        if not real_path.startswith(real_base):
            return 'Access denied', 403
        
        if not os.path.exists(real_path):
            return 'Not found', 404
        
        mimetype = get_media_type_from_path(filepath)
        return send_file(real_path, mimetype=mimetype)
    except Exception as e:
        return str(e), 500

@app.route('/view/s3/<path:key>')
def view_s3(key):
    try:
        s3 = get_s3_client()
        full_key = f"{S3_PREFIX}/{key}" if S3_PREFIX else key
        
        mimetype = None
        if key.startswith('local_content/'):
            mimetype = get_media_type_from_path(key)
        
        params = {'Bucket': S3_BUCKET, 'Key': full_key}
        if mimetype:
            params['ResponseContentType'] = mimetype
        
        url = s3.generate_presigned_url('get_object',
            Params=params,
            ExpiresIn=3600)
        
        return jsonify({'url': url, 'mimetype': mimetype, 'source': 's3'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/view/media/<media_id>')
def view_media(media_id):
    try:
        conn = get_db_conn()
        cur = conn.cursor()
        cur.execute(
            "SELECT media_type FROM local_media_repository WHERE media_id = %s",
            (media_id,)
        )
        row = cur.fetchone()
        cur.close()
        conn.close()
        
        mimetype = row[0] if row else None
        local_path = f"local_content/{media_id[0:2]}/{media_id[2:4]}/{media_id[4:]}"
        full_local_path = os.path.join(MEDIA_STORE_PATH, local_path)
        
        if os.path.exists(full_local_path):
            return send_file(full_local_path, mimetype=mimetype)
        
        s3 = get_s3_client()
        full_key = f"{S3_PREFIX}/{local_path}" if S3_PREFIX else local_path
        
        params = {'Bucket': S3_BUCKET, 'Key': full_key}
        if mimetype:
            params['ResponseContentType'] = mimetype
        
        url = s3.generate_presigned_url('get_object',
            Params=params,
            ExpiresIn=3600)
        
        return jsonify({'url': url, 'mimetype': mimetype, 'source': 's3'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

HTML_TEMPLATE = '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Matrix Media Browser</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { 
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: #0d1117; 
            color: #c9d1d9; 
            padding: 20px;
            line-height: 1.6;
        }
        h1 { color: #58a6ff; margin-bottom: 20px; }
        h2 { color: #79c0ff; margin: 30px 0 15px; font-size: 1.2em; }
        .stats { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); 
            gap: 15px; 
            margin-bottom: 30px;
        }
        .stat-card { 
            background: #161b22; 
            border: 1px solid #30363d; 
            border-radius: 8px; 
            padding: 20px;
        }
        .stat-value { 
            font-size: 2em; 
            font-weight: bold; 
            color: #58a6ff; 
        }
        .stat-label { 
            color: #8b949e; 
            font-size: 0.9em; 
            margin-top: 5px;
        }
        table { 
            width: 100%; 
            border-collapse: collapse; 
            background: #161b22;
            border-radius: 8px;
            overflow: hidden;
            font-size: 0.85em;
        }
        th, td { 
            padding: 10px 12px; 
            text-align: left; 
            border-bottom: 1px solid #30363d;
        }
        th { 
            background: #21262d; 
            color: #79c0ff;
            font-weight: 600;
            position: sticky;
            top: 0;
        }
        tr:hover { background: #1c2128; }
        .badge {
            display: inline-block;
            padding: 2px 8px;
            border-radius: 12px;
            font-size: 0.8em;
            font-weight: 600;
        }
        .badge-synced { background: #238636; color: white; }
        .badge-local { background: #1f6feb; color: white; }
        .badge-s3 { background: #8957e5; color: white; }
        .badge-orphan { background: #da3633; color: white; }
        .tab-bar {
            display: flex;
            gap: 10px;
            margin-bottom: 20px;
            border-bottom: 1px solid #30363d;
            padding-bottom: 10px;
        }
        .tab {
            padding: 8px 16px;
            cursor: pointer;
            border-radius: 6px;
            background: #21262d;
            border: none;
            color: #c9d1d9;
            font-size: 0.9em;
        }
        .tab.active {
            background: #1f6feb;
            color: white;
        }
        .tab:hover:not(.active) { background: #30363d; }
        .hidden { display: none; }
        .loading { color: #8b949e; font-style: italic; }
        .error { color: #f85149; padding: 20px; }
        a { color: #58a6ff; text-decoration: none; }
        a:hover { text-decoration: underline; }
        .size { font-family: monospace; color: #8b949e; }
        .path { font-family: monospace; font-size: 0.85em; }
        #content { max-height: 70vh; overflow-y: auto; }
        .preview-modal {
            display: none;
            position: fixed;
            top: 0; left: 0; width: 100%; height: 100%;
            background: rgba(0,0,0,0.9);
            z-index: 1000;
            justify-content: center;
            align-items: center;
            flex-direction: column;
        }
        .preview-modal.active { display: flex; }
        .preview-modal img, .preview-modal video {
            max-width: 90vw;
            max-height: 80vh;
            border-radius: 8px;
        }
        .preview-modal audio { width: 500px; }
        .preview-close {
            position: absolute;
            top: 20px; right: 30px;
            font-size: 2em; color: white;
            cursor: pointer; background: none; border: none;
        }
        .preview-info {
            color: #8b949e;
            margin-top: 15px;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <h1>📁 Matrix Media Browser</h1>
    
    <div class="stats" id="stats">
        <div class="stat-card"><div class="stat-value" id="stat-local">-</div><div class="stat-label">Local Files</div></div>
        <div class="stat-card"><div class="stat-value" id="stat-s3">-</div><div class="stat-label">S3 Objects</div></div>
        <div class="stat-card"><div class="stat-value" id="stat-db">-</div><div class="stat-label">DB Entries</div></div>
        <div class="stat-card"><div class="stat-value" id="stat-synced">-</div><div class="stat-label">Synced</div></div>
    </div>
    
    <div class="tab-bar">
        <button class="tab active" onclick="showTab('media-db')">Media DB</button>
        <button class="tab" onclick="showTab('sync-status')">Sync Status</button>
        <button class="tab" onclick="showTab('local-files')">Local Files</button>
        <button class="tab" onclick="showTab('s3-objects')">S3 Objects</button>
    </div>
    
    <div id="content">
        <div id="tab-media-db" class="tab-content">
            <h2>Local Media Repository (from DB)</h2>
            <div id="media-db-table" class="loading">Loading...</div>
        </div>
        <div id="tab-sync-status" class="tab-content hidden">
            <h2>Sync Comparison</h2>
            <div id="sync-status-content" class="loading">Loading...</div>
        </div>
        <div id="tab-local-files" class="tab-content hidden">
            <h2>Local Filesystem</h2>
            <div id="local-files-table" class="loading">Loading...</div>
        </div>
        <div id="tab-s3-objects" class="tab-content hidden">
            <h2>S3 Objects</h2>
            <div id="s3-objects-table" class="loading">Loading...</div>
        </div>
    </div>
    
    <div id="preview-modal" class="preview-modal">
        <button class="preview-close">&times;</button>
        <div id="preview-container"></div>
        <div id="preview-info" class="preview-info"></div>
    </div>

    <script>
        function formatBytes(bytes) {
            if (bytes === 0) return "0 B";
            const k = 1024;
            const sizes = ["B", "KB", "MB", "GB"];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + " " + sizes[i];
        }
        
        function showTab(name) {
            document.querySelectorAll(".tab-content").forEach(el => el.classList.add("hidden"));
            document.querySelectorAll(".tab").forEach(el => el.classList.remove("active"));
            document.getElementById("tab-" + name).classList.remove("hidden");
            event.target.classList.add("active");
            
            if (name === "media-db" && !window.mediaDbLoaded) loadMediaDb();
            if (name === "sync-status" && !window.syncStatusLoaded) loadSyncStatus();
            if (name === "local-files" && !window.localFilesLoaded) loadLocalFiles();
            if (name === "s3-objects" && !window.s3ObjectsLoaded) loadS3Objects();
        }
        
        async function loadStats() {
            try {
                const r = await fetch("/api/stats");
                const data = await r.json();
                document.getElementById("stat-local").textContent = data.local_files;
                document.getElementById("stat-s3").textContent = data.s3_objects;
                document.getElementById("stat-db").textContent = data.db_local_entries;
                document.getElementById("stat-synced").textContent = data.s3_objects;
                document.querySelectorAll(".stat-label")[0].textContent = `Local (${formatBytes(data.local_size)})`;
                document.querySelectorAll(".stat-label")[1].textContent = `S3 (${formatBytes(data.s3_size)})`;
            } catch (e) {
                console.error("Stats error:", e);
            }
        }
        
        async function loadMediaDb() {
            try {
                const r = await fetch("/api/media-db?limit=2000");
                const rows = await r.json();
                window.mediaDbLoaded = true;
                
                let html = `<table><thead><tr>
                    <th>Media ID</th><th>Type</th><th>Size</th><th>Created</th>
                    <th>Last Access</th><th>Upload Name</th><th>Status</th><th>Action</th>
                </tr></thead><tbody>`;
                
                rows.forEach(row => {
                    const status = row.local_exists 
                        ? '<span class="badge badge-local">Local</span>' 
                        : '<span class="badge badge-s3">S3 Only</span>';
                    const quarantined = row.quarantined ? ' <span class="badge badge-orphan">Q</span>' : '';
                    html += `<tr>
                        <td class="path">${row.media_id}</td>
                        <td>${row.media_type || "-"}</td>
                        <td class="size">${formatBytes(row.size)}</td>
                        <td>${row.created ? row.created.slice(0, 19).replace("T", " ") : "-"}</td>
                        <td>${row.last_access ? row.last_access.slice(0, 19).replace("T", " ") : "-"}</td>
                        <td>${row.upload_name || "-"}</td>
                        <td>${status}${quarantined}</td>
                        <td><a href="#" onclick="viewMedia('${row.media_id}', '${row.media_type || ""}', '${row.upload_name || row.media_id}'); return false;">View</a></td>
                    </tr>`;
                });
                html += "</tbody></table>";
                document.getElementById("media-db-table").innerHTML = html;
            } catch (e) {
                document.getElementById("media-db-table").innerHTML = `<div class="error">Error: ${e.message}</div>`;
            }
        }
        
        async function loadSyncStatus() {
            try {
                const r = await fetch("/api/sync-status");
                const data = await r.json();
                window.syncStatusLoaded = true;
                
                let html = `<div style="display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 15px; margin-bottom: 20px;">
                    <div class="stat-card"><div class="stat-value" style="color: #238636;">${data.synced_count}</div><div class="stat-label">Synced (both)</div></div>
                    <div class="stat-card"><div class="stat-value" style="color: #1f6feb;">${data.local_only_count}</div><div class="stat-label">Local Only</div></div>
                    <div class="stat-card"><div class="stat-value" style="color: #8957e5;">${data.s3_only_count}</div><div class="stat-label">S3 Only</div></div>
                </div>`;
                
                if (data.local_only.length > 0) {
                    html += `<h3>Local Only (${data.local_only_count} total, showing first 100)</h3>
                    <table><thead><tr><th>Path</th><th>Action</th></tr></thead><tbody>`;
                    data.local_only.forEach(path => {
                        html += `<tr><td class="path">${path}</td><td><a href="/view/local/${path}" target="_blank">View</a></td></tr>`;
                    });
                    html += "</tbody></table>";
                }
                
                if (data.s3_only.length > 0) {
                    html += `<h3>S3 Only (${data.s3_only_count} total, showing first 100)</h3>
                    <table><thead><tr><th>Key</th></tr></thead><tbody>`;
                    data.s3_only.forEach(key => {
                        html += `<tr><td class="path">${key}</td></tr>`;
                    });
                    html += "</tbody></table>";
                }
                
                document.getElementById("sync-status-content").innerHTML = html;
            } catch (e) {
                document.getElementById("sync-status-content").innerHTML = `<div class="error">Error: ${e.message}</div>`;
            }
        }
        
        async function loadLocalFiles() {
            try {
                const r = await fetch("/api/local");
                const files = await r.json();
                window.localFilesLoaded = true;
                
                let html = `<table><thead><tr>
                    <th>Path</th><th>Size</th><th>Modified</th><th>Action</th>
                </tr></thead><tbody>`;
                files.forEach(f => {
                    html += `<tr>
                        <td class="path">${f.path}</td>
                        <td class="size">${formatBytes(f.size)}</td>
                        <td>${f.modified.slice(0, 19).replace("T", " ")}</td>
                        <td><a href="#" onclick="showPreview('/view/local/${f.path}', '', '${f.path}'); return false;">View</a></td>
                    </tr>`;
                });
                html += "</tbody></table>";
                document.getElementById("local-files-table").innerHTML = html;
            } catch (e) {
                document.getElementById("local-files-table").innerHTML = `<div class="error">Error: ${e.message}</div>`;
            }
        }
        
        async function loadS3Objects() {
            try {
                const r = await fetch("/api/s3");
                const objects = await r.json();
                window.s3ObjectsLoaded = true;
                
                let html = `<table><thead><tr>
                    <th>Key</th><th>Size</th><th>Modified</th><th>ETag</th><th>Action</th>
                </tr></thead><tbody>`;
                objects.forEach(obj => {
                    html += `<tr>
                        <td class="path">${obj.key}</td>
                        <td class="size">${formatBytes(obj.size)}</td>
                        <td>${obj.modified.slice(0, 19).replace("T", " ")}</td>
                        <td>${obj.etag.slice(0, 8)}...</td>
                        <td><a href="#" onclick="viewS3('${obj.key}'); return false;">View</a></td>
                    </tr>`;
                });
                html += "</tbody></table>";
                document.getElementById("s3-objects-table").innerHTML = html;
            } catch (e) {
                document.getElementById("s3-objects-table").innerHTML = `<div class="error">Error: ${e.message}</div>`;
            }
        }
        
        async function viewS3(key) {
            const r = await fetch("/view/s3/" + encodeURIComponent(key));
            const data = await r.json();
            if (data.url) {
                showPreview(data.url, data.mimetype || '', key);
            }
        }
        
        function showPreview(url, mimetype, name) {
            const modal = document.getElementById("preview-modal");
            const container = document.getElementById("preview-container");
            const info = document.getElementById("preview-info");
            container.innerHTML = "";
            info.textContent = name + (mimetype ? " (" + mimetype + ")" : "");
            if (mimetype && mimetype.startsWith("image/")) {
                container.innerHTML = `<img src="${url}" alt="${name}">`;
            } else if (mimetype && mimetype.startsWith("video/")) {
                container.innerHTML = `<video controls autoplay><source src="${url}" type="${mimetype}"></video>`;
            } else if (mimetype && mimetype.startsWith("audio/")) {
                container.innerHTML = `<audio controls autoplay src="${url}"></audio>`;
            } else {
                window.open(url, "_blank");
                return;
            }
            modal.classList.add("active");
        }
        
        async function viewMedia(mediaId, mimetype, name) {
            const r = await fetch("/view/media/" + encodeURIComponent(mediaId));
            const contentType = r.headers.get("content-type") || "";
            if (contentType.includes("application/json")) {
                const data = await r.json();
                if (data.url) {
                    showPreview(data.url, data.mimetype || mimetype, name);
                }
            } else {
                const blob = await r.blob();
                const url = URL.createObjectURL(blob);
                showPreview(url, mimetype, name);
            }
        }
        
        document.getElementById("preview-modal").addEventListener("click", function(e) {
            if (e.target === this || e.target.classList.contains("preview-close")) {
                this.classList.remove("active");
                document.getElementById("preview-container").innerHTML = "";
            }
        });
        
        loadStats();
        loadMediaDb();
    </script>
</body>
</html>
'''

if __name__ == '__main__':
    port = int(os.environ.get('PORT', '3000'))
    app.run(host='127.0.0.1', port=port, debug=False)
