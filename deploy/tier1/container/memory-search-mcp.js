#!/usr/bin/env node
// memory-search-mcp.js — MCP server for semantic memory search
// Runs inside NanoClaw container. Dispatches search to host via SSH.
// Replaces QMD MCP server with cloud-embedding-based hybrid search.

const { execSync } = require('child_process');
const readline = require('readline');

const TOOLS = [
  {
    name: 'memory_search',
    description: 'Search across all memory files using hybrid semantic + keyword search. Returns relevant chunks ranked by relevance. Use this to recall past conversations, decisions, preferences, or any stored knowledge.',
    inputSchema: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'Natural language search query' },
        limit: { type: 'number', description: 'Max results to return (default 8)', default: 8 },
      },
      required: ['query'],
    },
  },
  {
    name: 'memory_status',
    description: 'Check the status of the memory search index — number of chunks, last indexed time, etc.',
    inputSchema: { type: 'object', properties: {} },
  },
];

function handleRequest(request) {
  if (request.method === 'initialize') {
    return {
      protocolVersion: '2024-11-05',
      capabilities: { tools: {} },
      serverInfo: { name: 'memory-search', version: '1.0.0' },
    };
  }

  if (request.method === 'notifications/initialized') {
    return null; // no response needed for notifications
  }

  if (request.method === 'tools/list') {
    return { tools: TOOLS };
  }

  if (request.method === 'tools/call') {
    const { name, arguments: args } = request.params;

    if (name === 'memory_search') {
      const query = args.query;
      const limit = args.limit || 8;
      try {
        const result = execSync(
          `ssh -F /workspace/extra/agent-ssh/config -o ConnectTimeout=5 host.docker.internal "bash /home/ubuntu/dispatch/memory-search.sh '${query.replace(/'/g, "'\\''")}' ${limit}"`,
          { encoding: 'utf8', timeout: 45000 }
        );
        return {
          content: [{ type: 'text', text: result.trim() || 'No results found.' }],
        };
      } catch (e) {
        return {
          content: [{ type: 'text', text: `Memory search error: ${e.message}` }],
          isError: true,
        };
      }
    }

    if (name === 'memory_status') {
      try {
        const result = execSync(
          `ssh -F /workspace/extra/agent-ssh/config -o ConnectTimeout=5 host.docker.internal "sqlite3 /home/ubuntu/NanoClaw/data/memory-index.db \"SELECT key, value FROM meta ORDER BY key\""`,
          { encoding: 'utf8', timeout: 10000 }
        );
        return {
          content: [{ type: 'text', text: result.trim() || 'Memory index not yet created. Run memory-reindex.sh on the host.' }],
        };
      } catch (e) {
        return {
          content: [{ type: 'text', text: 'Memory index not available. Run memory-reindex.sh on the host to create it.' }],
        };
      }
    }

    return {
      content: [{ type: 'text', text: `Unknown tool: ${name}` }],
      isError: true,
    };
  }

  return { error: { code: -32601, message: `Unknown method: ${request.method}` } };
}

// JSON-RPC over stdin/stdout
const rl = readline.createInterface({ input: process.stdin });

rl.on('line', (line) => {
  try {
    const request = JSON.parse(line);
    const result = handleRequest(request);

    if (result === null) return; // notification, no response

    const response = {
      jsonrpc: '2.0',
      id: request.id,
    };

    if (result.error) {
      response.error = result.error;
    } else {
      response.result = result;
    }

    process.stdout.write(JSON.stringify(response) + '\n');
  } catch (e) {
    const errResponse = {
      jsonrpc: '2.0',
      id: null,
      error: { code: -32700, message: `Parse error: ${e.message}` },
    };
    process.stdout.write(JSON.stringify(errResponse) + '\n');
  }
});
