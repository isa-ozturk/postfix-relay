# postfix-relay

A lightweight, production-ready outbound SMTP relay stack built on Docker Compose. Designed for environments where local devices — printers, IoT sensors, monitoring systems, or internal applications — need to send email without managing individual mail accounts.

## Overview

Most organizations have devices and services that need to send email but maintaining per-device mail accounts is impractical. This stack solves that: any device within your trusted network can send mail from any `@yourdomain.com` address — no credentials, no account provisioning required.

The stack is built around three principles:

- **IP-based trust** — Devices are authorized by network location, not credentials
- **Outbound-only by default** — No inbox, no IMAP, no attack surface for inbound spam
- **Single source of truth** — One `.env` file configures everything; deploy the same stack across multiple domains with no code changes

## Architecture

```
┌─────────────────────────────────┐
│  Trusted Network (MYNETWORKS)   │
│                                 │
│  printer     → port 25, no auth │
│  iot-sensor  → port 25, no auth │
│  app-server  → port 25, no auth │
└────────────────┬────────────────┘
                 │
         ┌───────▼────────┐
         │    Postfix     │  Outbound SMTP relay
         │                │  Direct MX or upstream relay
         └───────┬────────┘
                 │
    ┌────────────┴──────────┐
    │                       │
    │  Internet delivery    │  ┌─────────────────┐
    │  (or smarthost relay) │  │   Log Viewer    │  Web UI
    │                       │  │  /maillog path  │  Mail flow monitoring
    └───────────────────────┘  └─────────────────┘
```

## Features

- **Accountless relay** — Send from `printer@domain.com`, `alerts@domain.com`, `noreply@domain.com` without creating mail accounts
- **Per-network IP allowlisting** — Define which subnets can relay; all others are rejected
- **Zero inbound exposure** — `mydestination` is empty by default; the server does not accept mail for local delivery
- **Web-based log viewer** — Real-time mail flow dashboard: delivery status, source device, recipient, rejection reasons
- **Multi-domain support** — Deploy multiple independent instances on the same host using `COMPOSE_PROJECT_NAME`
- **Existing certificate reuse** — Bind-mount your server's existing TLS certificates; no separate certificate management
- **Optional upstream relay** — Route through SendGrid, AWS SES, Mailgun, or any SMTP smarthost
- **Traefik-native** — Label-based routing, wildcard TLS support, Cloudflare Tunnel compatible
- **Watchtower-ready** — Auto-update labels included

## Requirements

- Docker and Docker Compose
- A running Traefik instance (Dokploy's built-in Traefik works out of the box)
- TLS certificate files (`fullchain.pem` and `privkey.pem`) on the host
- A domain with DNS access

## Quick Start

```bash
git clone https://github.com/isa-ozturk/postfix-relay.git
cd postfix-relay
cp .env.example .env
```

Edit `.env` with your values, then:

```bash
docker compose up -d
```

## Configuration

All configuration lives in `.env`. The `.env.example` file documents every available variable with defaults and examples.

### Required variables

| Variable | Example | Description |
|----------|---------|-------------|
| `COMPOSE_PROJECT_NAME` | `myproject` | Unique name; used for container and Traefik router naming |
| `MAIL_HOSTNAME` | `mail.example.com` | FQDN of the mail server |
| `MAIL_DOMAIN` | `example.com` | Your sending domain |
| `ADMIN_HOST` | `mailadmin.example.com` | Hostname where the log viewer is served |
| `MYNETWORKS` | `192.168.1.0/24 172.16.0.0/12 127.0.0.0/8` | Space-separated CIDR blocks allowed to relay |
| `SSL_CERT_DIR` | `/etc/letsencrypt/live/example.com` | Directory containing `fullchain.pem` and `privkey.pem` |
| `TRAEFIK_NETWORK` | `dokploy-network` | External Docker network name of your Traefik instance |

### Locate your certificate directory

```bash
find / -name "fullchain.pem" 2>/dev/null
```

### Optional upstream relay (smarthost)

If your ISP blocks port 25 or you want to route through a transactional email provider:

```env
RELAYHOST=[smtp.sendgrid.net]:587
SMTP_SMARTHOST=smtp.sendgrid.net
SMTP_SMARTHOST_USER=apikey
SMTP_SMARTHOST_PASS=SG.xxxxxxxxxxxxxxx
```

Leaving `RELAYHOST` empty makes Postfix perform direct MX delivery.

## Running Multiple Domains on One Host

Set a different `COMPOSE_PROJECT_NAME` for each deployment. Container names, Traefik router names, and middleware names are all derived from this value — no conflicts occur.

```bash
# Project A
cd /opt/stacks/project-a
# .env: COMPOSE_PROJECT_NAME=projecta, MAIL_DOMAIN=projecta.com, SMTP_PORT=25
docker compose up -d

# Project B — same server, same compose file
cd /opt/stacks/project-b
# .env: COMPOSE_PROJECT_NAME=projectb, MAIL_DOMAIN=projectb.com, SMTP_PORT=2525
docker compose up -d
```

When running multiple instances on the same host, assign different `SMTP_PORT` values to avoid port binding conflicts.

## Device / Application SMTP Settings

Configure your printers, IoT devices, or applications with:

| Setting | Value |
|---------|-------|
| SMTP Server | `mail.yourdomain.com` or the server's IP address |
| Port | `25` |
| Authentication | **None / Disabled** |
| Encryption | None or STARTTLS (optional) |
| From Address | Any `@yourdomain.com` address |

Devices must originate from an IP within `MYNETWORKS`. All other sources are rejected.

## DNS Configuration

| Type | Name | Value | Proxy |
|------|------|-------|-------|
| A | `mail` | Server IP | ❌ DNS only — not proxied |
| MX | `@` | `mail.yourdomain.com` (priority 10) | — |
| TXT | `@` | `v=spf1 a:mail.yourdomain.com ~all` | — |

> The `mail` A record **must not be proxied** through Cloudflare. Postfix requires a direct TCP connection on port 25.  
> Web-facing subdomains (`mailadmin`, etc.) can be proxied normally.

### Recommended: DMARC record

```
TXT  _dmarc.yourdomain.com  →  v=DMARC1; p=quarantine; rua=mailto:postmaster@yourdomain.com
```

## Log Viewer

Available at `https://ADMIN_HOST/maillog`.

Displays a real-time dashboard of mail activity:

- **Sent** — successfully delivered messages
- **Bounced** — permanent delivery failures with reason
- **Deferred** — temporary failures pending retry
- **Rejected** — connections refused before message acceptance
- **Queued** — messages accepted but not yet delivered

Each entry shows the source device IP, sender address, recipient, relay host, message size, and full status detail. Clicking a row expands the detail text.

The log viewer supports filtering by status, sender, and recipient, and exposes a `/api/events` JSON endpoint for integration with external monitoring systems.

### Access control

The log viewer is protected at two layers:

1. **Traefik IP whitelist** — configured via `LOGVIEWER_ALLOWED_NETWORKS`
2. **Application-level IP check** — `ALLOWED_NETWORKS` environment variable inside the container

When using Cloudflare Tunnel, the real client IP is not forwarded by default. In that case, set `LOGVIEWER_ALLOWED_NETWORKS=0.0.0.0/0` and enforce access control at the Cloudflare Access (Zero Trust) layer instead.

## Operational Commands

```bash
# View the mail queue
docker exec ${COMPOSE_PROJECT_NAME}_postfix mailq

# Force queue processing
docker exec ${COMPOSE_PROJECT_NAME}_postfix postfix flush

# Flush all deferred messages
docker exec ${COMPOSE_PROJECT_NAME}_postfix postsuper -d ALL deferred

# Delete a specific queued message
docker exec ${COMPOSE_PROJECT_NAME}_postfix postsuper -d <QUEUE_ID>

# Tail live logs
docker logs -f ${COMPOSE_PROJECT_NAME}_postfix

# Inspect active Postfix configuration
docker exec ${COMPOSE_PROJECT_NAME}_postfix postconf -n

# Send a test message
docker exec ${COMPOSE_PROJECT_NAME}_postfix bash -c \
  "echo 'Test message body' | sendmail -f noreply@yourdomain.com recipient@example.com"

# Check SPF record propagation
dig TXT yourdomain.com | grep spf
```

## Repository Structure

```
postfix-relay/
├── docker-compose.yml        # Service definitions; no hardcoded domains
├── .env.example              # Fully documented configuration template
├── .gitignore                # Excludes .env and certificate files
├── README.md
└── logviewer/
    ├── Dockerfile            # Python 3.12 slim base
    ├── app.py                # Flask log parser and API server
    └── templates/
        └── index.html        # Dark-theme dashboard UI
```

## Enabling Inbound Mail (Optional)

This stack ships as outbound-only. To enable inbound delivery:

1. Set `POSTFIX_MYDESTINATION` in `.env`:
   ```env
   POSTFIX_MYDESTINATION=${MAIL_HOSTNAME}, ${MAIL_DOMAIN}, localhost
   ```
2. Add a Dovecot container for IMAP/POP3 access (not included in this stack)
3. Ensure your `mail` DNS A record is not proxied and port 25 is reachable from the internet

## Security Considerations

- **`MYNETWORKS` scope** — Keep this as narrow as possible. Include only subnets where trusted devices reside.
- **No port 587 exposure** — Authenticated submission is not exposed externally. Internal relay uses port 25 only.
- **TLS on delivery** — Postfix uses opportunistic TLS (`may`) for outbound delivery. Compatible with devices that cannot negotiate TLS.
- **Log viewer isolation** — The log viewer container has no access to the Postfix queue or configuration. It reads log files from a shared read-only volume.

## License

MIT
