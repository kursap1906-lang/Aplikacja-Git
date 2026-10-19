// Serwuje build Flutter Web i przekazuje /api do backendu, dzięki czemu UI i API mają jeden origin.
import http from 'node:http';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { extname, join, normalize } from 'node:path';

const port = Number(process.env.GATEWAY_PORT ?? 4173);
const apiPort = Number(process.env.PORT ?? 3000);
const root = process.env.WEB_ROOT;

if (!root || !existsSync(join(root, 'index.html'))) {
  console.error('WEB_ROOT must point to a Flutter web build.');
  process.exit(1);
}

const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.wasm': 'application/wasm',
  '.ico': 'image/x-icon',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
};

http
  .createServer((req, res) => {
    const url = new URL(req.url ?? '/', 'http://gateway');

    if (url.pathname === '/__control-center/health') {
      res.writeHead(200, {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'no-store',
      });
      res.end(JSON.stringify({ service: 'copilot-control-center-gateway', status: 'ok' }));
      return;
    }

    if (url.pathname.startsWith('/api/') || url.pathname.startsWith('/health/')) {
      const upstream = http.request(
        { host: '127.0.0.1', port: apiPort, path: req.url, method: req.method, headers: req.headers },
        (upstreamRes) => {
          res.writeHead(upstreamRes.statusCode ?? 502, upstreamRes.headers);
          upstreamRes.pipe(res);
        },
      );
      upstream.on('error', () => {
        res.writeHead(502, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'API_UNAVAILABLE' }));
      });
      req.pipe(upstream);
      return;
    }

    const relative = normalize(decodeURIComponent(url.pathname)).replace(/^(\.\.[/\\])+/, '');
    let file = join(root, relative);
    if (!file.startsWith(root) || !existsSync(file) || statSync(file).isDirectory()) {
      file = join(root, 'index.html');
    }
    const assetName = file.slice(root.length + 1).split(/[\\/]/).pop();
    const isEntrypoint = new Set([
      'index.html',
      'flutter_bootstrap.js',
      'flutter.js',
      'flutter_service_worker.js',
      'main.dart.js',
      'version.json',
    ]).has(assetName);
    res.writeHead(200, {
      'Content-Type': types[extname(file)] ?? 'application/octet-stream',
      'Cache-Control': isEntrypoint ? 'no-cache' : 'public, max-age=3600',
    });
    createReadStream(file).pipe(res);
  })
  .listen(port, '127.0.0.1', () => console.log(`Gateway listening on 127.0.0.1:${port}`));
