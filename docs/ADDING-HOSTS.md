# Adding New Hosts to HAProxy

This guide explains how to add new backend services to the HAProxy load balancer.

## Table of Contents
- [HTTP Backend (Plain HTTP)](#http-backend-plain-http)
- [HTTPS with Cloudflare Origin Certificate](#https-with-cloudflare-origin-certificate)
- [HTTPS with Let's Encrypt Certificate](#https-with-lets-encrypt-certificate)
- [HTTPS Backend (SSL Passthrough to Backend)](#https-backend-ssl-passthrough-to-backend)
- [Applying Changes](#applying-changes)

---

## HTTP Backend (Plain HTTP)

For services that only need HTTP (no SSL), like internal tools behind Cloudflare proxy.

### Step 1: Add ACL in HTTP Frontend

Edit `/etc/haproxy/haproxy.cfg` and add in the `frontend http_front` section:

```haproxy
frontend http_front
    bind *:80
    # ... existing ACLs ...
    
    # Add your new host ACL
    acl host_myapp hdr(host) -i myapp.example.com
    
    # ... existing use_backend rules ...
    
    # Add use_backend rule (before default_backend)
    use_backend backend_myapp if host_myapp
```

### Step 2: Create Backend

Add at the end of the backends section:

```haproxy
backend backend_myapp
    mode http
    balance roundrobin
    option httpchk GET /
    http-check expect status 200-399
    server myapp1 10.27.27.XX:PORT check
```

### Example: Adding `dashboard.c4g7.com` on port 3000

```haproxy
# In frontend http_front:
acl host_dashboard hdr(host) -i dashboard.c4g7.com
use_backend backend_dashboard if host_dashboard

# New backend:
backend backend_dashboard
    mode http
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200-399
    server dashboard1 10.27.27.50:3000 check
```

---

## HTTPS with Cloudflare Origin Certificate

For `*.c4g7.com` domains that go through Cloudflare (most common setup).

### Step 1: Add ACL in HTTPS Frontend

Edit `/etc/haproxy/haproxy.cfg` and add in the `frontend https_front` section:

```haproxy
frontend https_front
    bind *:443 ssl crt /etc/haproxy/certs/cloudflare/c4g7.pem ...
    
    # Add your new host ACL
    acl host_myapp hdr(host) -i myapp.c4g7.com
    
    # Add use_backend rule
    use_backend backend_myapp if host_myapp
```

### Step 2: Add HTTP Redirect (Optional but Recommended)

In `frontend http_front`, add redirect for the new domain:

```haproxy
frontend http_front
    # ... existing config ...
    
    # Redirect HTTP to HTTPS for your domain
    acl host_myapp hdr(host) -i myapp.c4g7.com
    redirect scheme https code 301 if host_myapp !{ ssl_fc }
```

### Step 3: Create Backend

```haproxy
backend backend_myapp
    mode http
    balance roundrobin
    option httpchk GET /
    http-check expect status 200-399
    server myapp1 10.27.27.XX:PORT check
```

### Complete Example: Adding `monitor.c4g7.com`

```haproxy
#=== In frontend http_front ===
acl host_monitor hdr(host) -i monitor.c4g7.com
redirect scheme https code 301 if host_monitor !{ ssl_fc }

#=== In frontend https_front ===
acl host_monitor hdr(host) -i monitor.c4g7.com
use_backend backend_monitor if host_monitor

#=== New backend ===
backend backend_monitor
    mode http
    balance roundrobin
    option httpchk GET /api/health
    http-check expect status 200-399
    server monitor1 10.27.27.100:8080 check
```

---

## HTTPS with Let's Encrypt Certificate

For domains not on Cloudflare (e.g., `*.tth-gaming.de`, `*.tth-projects.de`).

### Step 1: Obtain Let's Encrypt Certificate

```bash
# Install certbot if not already installed
apt install certbot

# Get certificate (DNS challenge recommended for wildcards)
certbot certonly --manual --preferred-challenges dns -d "*.yourdomain.com" -d "yourdomain.com"

# Combine cert and key for HAProxy
cat /etc/letsencrypt/live/yourdomain.com/fullchain.pem \
    /etc/letsencrypt/live/yourdomain.com/privkey.pem \
    > /etc/haproxy/certs/letsencrypt/yourdomain.pem
```

### Step 2: Add Certificate to Frontend

If this is a new domain (not already in the cert list):

```haproxy
frontend https_front
    bind *:443 ssl crt /etc/haproxy/certs/cloudflare/c4g7.pem \
                   crt /etc/haproxy/certs/letsencrypt/tth-gaming.pem \
                   crt /etc/haproxy/certs/letsencrypt/yourdomain.pem \
                   ...
```

### Step 3: Add ACL and Backend

Same as Cloudflare setup - add ACL, redirect, and backend.

---

## HTTPS Backend (SSL Passthrough to Backend)

For backends that handle their own SSL (e.g., Proxmox, services with their own certs).

### Basic SSL Backend

```haproxy
backend backend_myssl
    mode http
    balance roundrobin
    option httpchk GET /
    http-check expect status 200-399
    server myssl1 10.27.27.XX:443 ssl verify none check
```

### SSL Backend with SNI Requirement

Some servers require SNI (Server Name Indication) to respond:

```haproxy
backend backend_myssl
    mode http
    balance roundrobin
    option httpchk GET /
    http-check expect status 200-399
    # sni str(...) = SNI for traffic
    # check-sni = SNI for health checks
    server myssl1 10.27.27.XX:443 ssl verify none sni str(myapp.example.com) check check-sni myapp.example.com
```

### Example: Proxmox Web UI

```haproxy
# ACL in https_front
acl host_proxmox hdr(host) -i proxmox.c4g7.com
use_backend backend_proxmox if host_proxmox

# Backend with SSL to Proxmox
backend backend_proxmox
    mode http
    balance roundrobin
    option httpchk GET /
    http-check expect status 200-399
    server proxmox1 10.27.27.200:8006 ssl verify none check
```

---

## Applying Changes

### Method 1: Edit on MASTER Node (Recommended)

The auto-sync will propagate changes to the BACKUP node.

```bash
# 1. Edit config on Node 1 (MASTER)
nano /etc/haproxy/haproxy.cfg

# 2. Validate configuration
haproxy -c -f /etc/haproxy/haproxy.cfg

# 3. Reload HAProxy
systemctl reload haproxy

# 4. Auto-sync will push to Node 2 automatically
# Check sync log:
journalctl -u haproxy-autosync -f
```

### Method 2: Manual Sync

```bash
# Force sync to peer
/usr/local/bin/haproxy-sync.sh
```

### Validation Checklist

```bash
# 1. Check config syntax
haproxy -c -f /etc/haproxy/haproxy.cfg

# 2. Reload and check status
systemctl reload haproxy
systemctl status haproxy

# 3. Verify backend is UP
curl -s -u admin:YourSecurePassword123 "http://10.50.50.100:8404/stats;csv" | grep backend_myapp

# 4. Test the endpoint
curl -I -H "Host: myapp.c4g7.com" http://10.50.50.100/
curl -Ik -H "Host: myapp.c4g7.com" https://10.50.50.100/
```

---

## Quick Reference: Config Snippet Templates

### HTTP-only Service
```haproxy
# frontend http_front
acl host_XXX hdr(host) -i XXX.example.com
use_backend backend_XXX if host_XXX

# backend
backend backend_XXX
    mode http
    balance roundrobin
    option httpchk GET /
    http-check expect status 200-399
    server XXX1 10.27.27.XX:PORT check
```

### HTTPS Service (Cloudflare)
```haproxy
# frontend http_front
acl host_XXX hdr(host) -i XXX.c4g7.com
redirect scheme https code 301 if host_XXX !{ ssl_fc }

# frontend https_front
acl host_XXX hdr(host) -i XXX.c4g7.com
use_backend backend_XXX if host_XXX

# backend
backend backend_XXX
    mode http
    balance roundrobin
    option httpchk GET /
    http-check expect status 200-399
    server XXX1 10.27.27.XX:PORT check
```

### SSL Backend with SNI
```haproxy
# backend
backend backend_XXX
    mode http
    balance roundrobin
    option httpchk GET /
    http-check expect status 200-399
    server XXX1 10.27.27.XX:443 ssl verify none sni str(XXX.example.com) check check-sni XXX.example.com
```
