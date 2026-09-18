#!/usr/bin/env node
import http from "node:http";

const listenHost = process.env.MCP_ALIAS_HOST || "127.0.0.1";
const listenPort = Number(process.env.MCP_ALIAS_PORT || 3000);
const targetHost = process.env.MCP_HOST || "127.0.0.1";
const targetPort = Number(process.env.MCP_PORT || 3001);

const aliases = new Map([
  ["/.well-known/oauth-authorization-server/mcp", "/.well-known/oauth-authorization-server"],
  ["/.well-known/openid-configuration", "/.well-known/oauth-authorization-server"],
  ["/.well-known/openid-configuration/mcp", "/.well-known/oauth-authorization-server"],
  ["/mcp/.well-known/oauth-protected-resource", "/.well-known/oauth-protected-resource"],
  ["/mcp/.well-known/oauth-authorization-server", "/.well-known/oauth-authorization-server"],
  ["/mcp/.well-known/openid-configuration", "/.well-known/oauth-authorization-server"],
]);

const server = http.createServer((request, response) => {
  const incoming = new URL(request.url || "/", `http://${listenHost}`);
  const mapped = aliases.get(incoming.pathname);
  const targetPath = mapped ? `${mapped}${incoming.search}` : `${incoming.pathname}${incoming.search}`;
  const headers = { ...request.headers, host: `${targetHost}:${targetPort}` };

  const proxy = http.request(
    {
      hostname: targetHost,
      port: targetPort,
      path: targetPath,
      method: request.method,
      headers,
    },
    (upstream) => {
      const outHeaders = { ...upstream.headers };
      if (!outHeaders["access-control-allow-origin"]) {
        outHeaders["access-control-allow-origin"] = "*";
      }
      response.writeHead(upstream.statusCode ?? 502, outHeaders);
      upstream.pipe(response);
    },
  );

  proxy.on("error", (error) => {
    console.error("oauth-alias-proxy upstream error:", error.message);
    if (!response.headersSent) {
      response.writeHead(502, { "content-type": "application/json" });
    }
    response.end(JSON.stringify({ error: "bad_gateway" }));
  });

  request.pipe(proxy);
});

server.listen(listenPort, listenHost, () => {
  console.log(
    `oauth-alias-proxy listening on http://${listenHost}:${listenPort} -> http://${targetHost}:${targetPort}`,
  );
});
