const fs = require('fs');
let t = fs.readFileSync('tools/matrix/tests/container.test.mjs', 'utf8');
const rep = (a, b) => { if (!t.includes(a)) throw new Error('missing: ' + a.slice(0, 80)); t = t.replace(a, b); };
rep("['.anthropic.com', '.claude.ai', '.claude.com', 'api.anthropic.com', 'api.github.com',", "['.anthropic.com', '.claude.ai', '.claude.com', 'api.github.com',");
rep("assert.match(squid, /http_access allow agent_net CONNECT ssl_ports allowed_hosts\nhttp_access deny all/);", "assert.match(squid, /http_access allow agent_net authed CONNECT ssl_ports allowed_hosts\nhttp_access deny all/);\n  assert.match(squid, /auth_param basic program \/usr\/lib\/squid\/basic_ncsa_auth \/etc\/squid\/passwd/);\n  assert.match(squid, /acl authed proxy_auth REQUIRED/);\n  // Squid refuses a host listed beside a parent domain, so no entry may be a subdomain of another.\n  for (const a of hosts) for (const b of hosts) if (a !== b && b.startsWith('.') && a.endsWith(b)) assert.fail(a + ' is redundant next to ' + b);");
fs.writeFileSync('tools/matrix/tests/container.test.mjs', t);
