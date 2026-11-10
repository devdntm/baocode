#!/usr/bin/env node
// BaoCode's helper for the claude-context index (docs/fork.md): what is
// indexed of a project, read in Milvus itself; and an indexing run, the
// claude-context MCP server started and asked over stdio, held until it is
// over. Never get_indexing_status: while indexing, it reports a false
// "completed" (files = chunks). A run is followed by what its own server
// logs (its progress, its end), not by the snapshot all the servers share:
// any other one starting (a Claude Code session in the project) writes the
// codebase there as failed ("interrupted"), with an old run's percentage.
//
//   node bao_index.js check <abs-path> [--json] [--server <json>]
//   node bao_index.js index <abs-path> [--force] [--json] [--server <json>]
//   node bao_index.js clear <abs-path> [--json] [--server <json>]
//
// --server: the claude-context entry of mcpServers (command, args, env); by
// default ~/.claude.json's. With --json each line printed is a JSON object:
//   {"event":"check", ...}      the index as it is (see check())
//   {"event":"started"}         the server took index_codebase
//   {"event":"progress", ...}   rows in Milvus, the run's own percentage
//   {"event":"done", ...}       over: the index as it is then
//   {"event":"error","message"}  failed, or no files found (and why)
// Exit codes: 0 complete / done, 1 incomplete or an error, 2 the server
// stopped before it was done.
'use strict';
const os = require('os');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawn, execSync } = require('child_process');

const argv = process.argv.slice(2);
const command = argv[0];
const codebase = path.resolve(argv[1] || process.cwd());
const json = argv.includes('--json');
const force = argv.includes('--force');
const serverArg = argv.indexOf('--server');

const HOME = os.homedir();
const CTX = path.join(HOME, '.context');
const md5 = crypto.createHash('md5').update(codebase).digest('hex');
const collection = `hybrid_code_chunks_${md5.slice(0, 8)}`;
const merklePath = path.join(CTX, 'merkle', `${md5}.json`);
const snapshotPath = path.join(CTX, 'mcp-codebase-snapshot.json');

function out(event, fields, text) {
  if (json) console.log(JSON.stringify({ event, ...fields }));
  else if (text) console.log(text);
}

function fail(message) {
  out('error', { message }, `Error: ${message}`);
  process.exit(1);
}

/// The claude-context server's entry: given, else ~/.claude.json's.
function serverConfig() {
  if (serverArg >= 0) return JSON.parse(argv[serverArg + 1]);
  const config = JSON.parse(fs.readFileSync(path.join(HOME, '.claude.json'), 'utf8'));
  const server =
    config.mcpServers?.['claude-context'] ??
    config.projects?.[codebase]?.mcpServers?.['claude-context'];
  if (!server) throw new Error('claude-context is not among the MCP servers');
  return server;
}

/// Where the server's packages are: beside its script, else ~/.context/mcp.
function nodeModules(server) {
  for (const arg of server.args ?? []) {
    const at = String(arg).lastIndexOf(`${path.sep}node_modules${path.sep}`);
    if (at >= 0) return String(arg).slice(0, at + '/node_modules'.length);
  }
  return path.join(CTX, 'mcp', 'node_modules');
}

function snapshotEntry() {
  try {
    return JSON.parse(fs.readFileSync(snapshotPath, 'utf8')).codebases?.[codebase] ?? null;
  } catch {
    return null;
  }
}

/// Whether a claude-context server runs (Claude Code's, or ours).
function serverRunning() {
  try {
    execSync('pgrep -f claude-context-mcp', { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

/// The snapshot's word on the codebase, as the indexer itself wrote it:
/// "completed" with as many files as chunks is one restored from Milvus,
/// not the indexer's.
function snapshotStatus(entry) {
  if (!entry) return null;
  return {
    status: entry.indexStatus ?? entry.status ?? null,
    indexedFiles: entry.indexedFiles ?? null,
    totalChunks: entry.totalChunks ?? null,
    percentage: entry.indexingPercentage ?? entry.percentage ?? null,
    lastUpdated: entry.lastUpdated ?? null,
    honest: !(entry.indexStatus === 'completed' && entry.indexedFiles === entry.totalChunks),
  };
}

function milvus(server) {
  const { MilvusClient } = require(path.join(nodeModules(server), '@zilliz', 'milvus2-sdk-node'));
  const address = server.env?.MILVUS_ADDRESS || process.env.MILVUS_ADDRESS || 'localhost:19530';
  return new MilvusClient({ address });
}

/// What is indexed of the codebase against what it has (the merkle
/// snapshot the indexer keeps of it).
async function check(client) {
  const result = {
    codebase,
    collection,
    exists: false,
    chunks: 0,
    indexedFiles: 0,
    projectFiles: null,
    missing: null,
    missingByDir: [],
    snapshot: snapshotStatus(snapshotEntry()),
    serverRunning: serverRunning(),
  };
  if (!(await client.hasCollection({ collection_name: collection })).value) return result;
  result.exists = true;
  await client.loadCollection({ collection_name: collection });
  const seen = new Set();
  const it = await client.queryIterator({
    collection_name: collection,
    output_fields: ['relativePath'],
    batchSize: 1000,
    expr: 'id != ""',
  });
  for await (const batch of it) {
    for (const row of batch) {
      result.chunks++;
      seen.add(row.relativePath);
    }
  }
  result.indexedFiles = seen.size;
  try {
    const hashes = JSON.parse(fs.readFileSync(merklePath, 'utf8')).fileHashes;
    const all = Array.isArray(hashes) ? hashes.map((x) => x[0]) : Object.keys(hashes);
    const missing = all.filter((file) => !seen.has(file));
    result.projectFiles = all.length;
    result.missing = missing.length;
    const byDir = {};
    for (const file of missing) {
      const dir = file.split('/').slice(0, 3).join('/');
      byDir[dir] = (byDir[dir] || 0) + 1;
    }
    result.missingByDir = Object.entries(byDir)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 15)
      .map(([dir, count]) => ({ dir, count }));
  } catch {
    // No merkle snapshot: nothing to compare with.
  }
  return result;
}

function describe(result) {
  if (!result.exists) return `No collection ${collection}: not indexed.`;
  return [
    `Collection: ${collection}`,
    `Chunks: ${result.chunks}, files indexed: ${result.indexedFiles}, in the project: ${result.projectFiles ?? '?'}, missing: ${result.missing ?? '?'}`,
    ...result.missingByDir.map(({ dir, count }) => `  ${count}\t${dir}`),
  ].join('\n');
}

const complete = (result) =>
  result.exists && result.projectFiles != null && result.missing === 0;

/// A JSON-RPC client over the server's stdio (newline-delimited).
function rpc(child) {
  let next = 1;
  const waiting = new Map();
  let buffer = '';
  child.stdout.on('data', (data) => {
    buffer += data.toString('utf8');
    let at;
    while ((at = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, at).trim();
      buffer = buffer.slice(at + 1);
      if (!line) continue;
      let message;
      try {
        message = JSON.parse(line);
      } catch {
        continue;
      }
      if (message.id != null && waiting.has(message.id)) {
        const { resolve, reject } = waiting.get(message.id);
        waiting.delete(message.id);
        if (message.error) reject(new Error(message.error.message || 'MCP error'));
        else resolve(message.result);
      }
    }
  });
  const send = (message) => child.stdin.write(`${JSON.stringify(message)}\n`);
  return {
    request(method, params) {
      const id = next++;
      return new Promise((resolve, reject) => {
        waiting.set(id, { resolve, reject });
        send({ jsonrpc: '2.0', id, method, params });
      });
    },
    notify(method, params) {
      send({ jsonrpc: '2.0', method, params });
    },
  };
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/// What the server's own log says of its indexing run: its stderr's
/// `[BACKGROUND-INDEX]` lines (claude-context-mcp's handlers.js).
function followLog(child) {
  const run = { percentage: null, phase: null, done: null, failed: null, files: null, last: [] };
  let buffer = '';
  child.stderr.on('data', (data) => {
    buffer += data.toString('utf8');
    let at;
    while ((at = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, at).replace(/^\[LOG\]\s*/, '').trim();
      buffer = buffer.slice(at + 1);
      if (!line) continue;
      run.last.push(line);
      if (run.last.length > 20) run.last.shift();
      let match;
      if ((match = line.match(/📁 Found (\d+) code files/))) {
        run.files = Number(match[1]);
      } else if ((match = line.match(/\[BACKGROUND-INDEX\] Progress: (.*?) - ([\d.]+)%/))) {
        run.phase = match[1];
        run.percentage = Number(match[2]);
      } else if ((match = line.match(/\[BACKGROUND-INDEX\] ✅ Indexing completed successfully! Files: (\d+), Chunks: (\d+)/))) {
        run.done = { files: Number(match[1]), chunks: Number(match[2]) };
      } else if ((match = line.match(/\[BACKGROUND-INDEX\] Indexing failed for .*?: (.*)$/))) {
        run.failed = match[1];
      } else if (/\[BACKGROUND-INDEX\] Indexing for .* was cancelled/.test(line)) {
        run.failed = 'cancelled';
      }
    }
  });
  return run;
}

/// Why the server found no files: an ignore file in the project's root
/// that excludes all (`*`, `**`) and lists what to keep with `!`, as a
/// .dockerignore may. claude-context reads every `.*ignore` there as a
/// .gitignore, but not its `!` lines: such a file leaves nothing.
function noFilesReason() {
  let names = [];
  try {
    names = fs.readdirSync(codebase).filter((name) => name.startsWith('.') && name.endsWith('ignore'));
  } catch {
    // An unreadable folder: said as it is.
  }
  for (const name of names) {
    let lines = [];
    try {
      lines = fs.readFileSync(path.join(codebase, name), 'utf8').split('\n').map((line) => line.trim());
    } catch {
      continue;
    }
    const all = lines.some((line) => ['*', '**', '/*', '/**', '**/*'].includes(line));
    const kept = lines.some((line) => line.startsWith('!'));
    if (all && kept) {
      return `claude-context found no files to index: ${name} excludes everything ` +
        `and keeps what it needs with "!" lines, which claude-context does not read ` +
        `(it reads every .*ignore in the project's root as a .gitignore).`;
    }
  }
  return 'claude-context found no files to index' +
    (names.length ? ` (its ignore files: ${names.join(', ')})` : '');
}

/// The server started as Claude Code starts it, spoken to over stdio.
async function startServer(server) {
  const child = spawn(server.command, server.args ?? [], {
    env: { ...process.env, ...(server.env ?? {}) },
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  const run = followLog(child);
  let exited = false;
  child.on('exit', () => {
    exited = true;
  });
  const stop = () => {
    if (!exited) child.kill('SIGTERM');
  };
  process.on('SIGTERM', () => {
    stop();
    process.exit(1);
  });
  const mcp = rpc(child);
  await mcp.request('initialize', {
    protocolVersion: '2024-11-05',
    capabilities: {},
    clientInfo: { name: 'baocode', version: '1' },
  });
  mcp.notify('notifications/initialized', {});
  return { mcp, stop, run, exited: () => exited };
}

/// The codebase's index dropped (clear_index).
async function clear(server) {
  const { mcp, stop } = await startServer(server);
  const answer = await mcp.request('tools/call', {
    name: 'clear_index',
    arguments: { path: codebase },
  });
  stop();
  const said = (answer?.content ?? []).map((part) => part.text ?? '').join('\n');
  if (answer?.isError) fail(said || 'clear_index failed');
  out('cleared', { message: said }, said);
  process.exit(0);
}

/// An indexing run: the server asked to index, held until it logs that it
/// is done (or failed, or it stops).
async function index(server, client) {
  const { mcp, stop, run, exited: hasExited } = await startServer(server);
  const answer = await mcp.request('tools/call', {
    name: 'index_codebase',
    arguments: { path: codebase, force },
  });
  const said = (answer?.content ?? []).map((part) => part.text ?? '').join('\n');
  // Already indexed and nothing asked again: the server says so (as an
  // error) and starts no run; what is there is checked.
  if (!force && /already indexed/i.test(said)) {
    stop();
    return;
  }
  if (answer?.isError) {
    stop();
    fail(said || 'index_codebase failed');
  }
  out('started', { message: said }, said);
  let last = null;
  for (;;) {
    await sleep(1000);
    if (run.files === 0) {
      stop();
      out('error', { message: noFilesReason() });
      process.exit(1);
    }
    if (run.done) break;
    if (run.failed) {
      stop();
      out('error', { message: run.failed });
      process.exit(1);
    }
    if (hasExited()) {
      out('error', {
        message: 'the claude-context server stopped before indexing was done',
        log: run.last.slice(-3),
      });
      process.exit(2);
    }
    let rows = null;
    try {
      const stats = await client.getCollectionStatistics({ collection_name: collection });
      rows = Number(stats.data.row_count);
    } catch {
      // The collection is being made.
    }
    // As the snapshot's shape, which the app reads: this run's own.
    const snapshot = { status: 'indexing', percentage: run.percentage, phase: run.phase };
    const key = `${rows}|${run.percentage}`;
    if (key !== last) {
      last = key;
      out('progress', { rows, snapshot }, `rows in Milvus: ${rows}, ${run.phase ?? 'starting'} ${run.percentage ?? ''}`);
    }
  }
  stop();
}

(async () => {
  if (!['check', 'index', 'clear'].includes(command)) {
    fail('usage: bao_index.js check|index|clear <abs-path> [--force] [--json] [--server <json>]');
  }
  let server;
  try {
    server = serverConfig();
  } catch (error) {
    fail(error.message);
  }
  if (command === 'clear') return clear(server);
  const client = milvus(server);
  if (command === 'index') await index(server, client);
  const result = await check(client);
  out(command === 'index' ? 'done' : 'check', result, describe(result));
  process.exit(complete(result) ? 0 : 1);
})().catch((error) => fail(error.message));
