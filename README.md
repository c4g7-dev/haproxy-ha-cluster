# HAProxy High Availability Cluster with Keepalived

A production-ready two-node HAProxy load balancer cluster with automatic failover using Keepalived VRRP and bidirectional config sync.

## Architecture

```
                    ┌─────────────────────────────────────┐
                    │         Virtual IP (VIP)            │
                    │         10.50.50.100                │
                    │    Ports: 80, 443, 8404 (stats)     │
                    └───────────────┬─────────────────────┘
                                    │
              ┌─────────────────────┼─────────────────────┐
              │                     │                     │
    ┌─────────▼─────────┐ ┌────────▼────────┐
    │   Node 1 (MASTER) │ │  Node 2 (BACKUP) │
    │   HAP-e1          │ │  HAP-f3          │
    │   10.50.50.10     │ │  10.50.50.30     │
    │   Priority: 101   │ │  Priority: 100   │
    │                   │ │                  │
    │   - HAProxy       │ │  - HAProxy       │
    │   - Keepalived    │ │  - Keepalived    │
    │   - Auto-sync     │ │  - Auto-sync     │
    └───────────────────┘ └──────────────────┘
              │                     │
              └──────────┬──────────┘
                         │
              ┌──────────▼──────────┐
              │   Backend Servers   │
              │   10.27.27.0/24     │
              └─────────────────────┘
```

## Features

- **High Availability**: Automatic failover via VRRP (< 3 second failover)
- **SSL Termination**: Multiple certificate support (Cloudflare Origin, Let's Encrypt)
- **HTTP/HTTPS Load Balancing**: Round-robin with health checks
- **Auto Config Sync**: Bidirectional sync between nodes using inotify
- **Stats Dashboard**: Real-time monitoring at `http://VIP:8404/stats`

## Quick Start

### Prerequisites
- Ubuntu 22.04 LTS
- Two servers on the same VLAN
- Root access

### Installation

```bash
# On both nodes
apt update && apt install -y haproxy keepalived inotify-tools

# Copy configs from this repo
# Node 1:
cp configs/haproxy.cfg /etc/haproxy/
cp configs/keepalived-node1.conf /etc/keepalived/keepalived.conf
cp scripts/haproxy-sync-node1.sh /usr/local/bin/haproxy-sync.sh
cp services/haproxy-autosync.service /etc/systemd/system/

# Node 2:
cp configs/haproxy.cfg /etc/haproxy/
cp configs/keepalived-node2.conf /etc/keepalived/keepalived.conf
cp scripts/haproxy-sync-node2.sh /usr/local/bin/haproxy-sync.sh
cp services/haproxy-autosync.service /etc/systemd/system/

# Enable services on both nodes
systemctl enable --now haproxy keepalived haproxy-autosync
```

## Configuration Files

| File | Description |
|------|-------------|
| `configs/haproxy.cfg` | Main HAProxy configuration |
| `configs/keepalived-node1.conf` | Keepalived config for MASTER node |
| `configs/keepalived-node2.conf` | Keepalived config for BACKUP node |
| `scripts/haproxy-sync-node1.sh` | Sync script for Node 1 → Node 2 |
| `scripts/haproxy-sync-node2.sh` | Sync script for Node 2 → Node 1 |
| `services/haproxy-autosync.service` | Systemd service for auto-sync |

## Network Configuration

| Component | IP Address | Port(s) |
|-----------|------------|---------|
| Virtual IP (VIP) | 10.50.50.100 | 80, 443, 8404 |
| Node 1 (HAP-e1) | 10.50.50.10 | - |
| Node 2 (HAP-f3) | 10.50.50.30 | - |
| Backend Network | 10.27.27.0/24 | Various |

## SSL Certificates

The setup supports multiple certificate chains:

1. **Cloudflare Origin** (`*.c4g7.com`): `/etc/haproxy/certs/cloudflare/c4g7.pem`
2. **Let's Encrypt** (`*.tth-gaming.de`, `*.tth-projects.de`): `/etc/haproxy/certs/letsencrypt/`

## Health Checks

HAProxy performs HTTP health checks on backends:

```
option httpchk GET /
http-check expect status 200-399
```

For SSL backends with SNI requirements:
```
server backend1 10.27.27.16:443 ssl verify none sni str(domain.com) check check-sni domain.com
```

## Auto-Sync System

The auto-sync uses inotify to watch for config changes:

1. Config file modified on any node
2. inotify detects `close_write` event
3. Waits 2 seconds (debounce)
4. Validates config locally
5. SCP to peer node
6. Validates and reloads on peer

### Manual Sync

```bash
/usr/local/bin/haproxy-sync.sh
```

## Monitoring

### Stats Dashboard
- URL: `http://10.50.50.100:8404/stats`
- Auth: `admin` / `YourSecurePassword123`

### Check Cluster Status

```bash
# On either node
systemctl status keepalived haproxy haproxy-autosync

# Check who has VIP
ip addr show eth1 | grep 10.50.50.100

# View backend status
curl -s -u admin:YourSecurePassword123 "http://10.50.50.100:8404/stats;csv" | \
  awk -F',' 'NR>1 && $2!="BACKEND" && $2!="FRONTEND"{print $1,$2,$18}'
```

## Failover Testing

```bash
# On MASTER node - simulate failure
systemctl stop keepalived

# Watch VIP move to BACKUP (on backup node)
watch -n1 'ip addr show eth1 | grep 10.50.50.100'

# Restore
systemctl start keepalived
```

## Troubleshooting

### Keepalived in FAULT state
- Check interface name matches config (`interface eth1`)
- Verify VLAN connectivity between nodes
- Check unicast peer IPs are correct

### Backends showing DOWN
- `L6RSP`: SSL handshake failed - check SNI config
- `L7RSP`: HTTP response error - check health check path
- `L4TOUT`: TCP timeout - backend server unreachable

### Config sync not working
- Verify SSH key authentication: `ssh -o BatchMode=yes root@PEER_IP hostname`
- Check autosync service: `journalctl -u haproxy-autosync -f`

## License

MIT License
