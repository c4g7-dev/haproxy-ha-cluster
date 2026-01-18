#!/bin/bash
# HAProxy config sync script
# Syncs config from this node to peer node

PEER="10.50.50.10"
CONFIG="/etc/haproxy/haproxy.cfg"
REMOTE_USER="root"

# Check if config is valid before syncing
if ! haproxy -c -f "$CONFIG" >/dev/null 2>&1; then
    echo "ERROR: Local config invalid, not syncing"
    exit 1
fi

# Sync to peer
scp -o BatchMode=yes -o ConnectTimeout=5 "$CONFIG" "${REMOTE_USER}@${PEER}:${CONFIG}" 2>/dev/null
if [ $? -eq 0 ]; then
    ssh -o BatchMode=yes -o ConnectTimeout=5 "${REMOTE_USER}@${PEER}" \
        "haproxy -c -f $CONFIG >/dev/null 2>&1 && systemctl reload haproxy" 2>/dev/null
    if [ $? -eq 0 ]; then
        logger "haproxy-sync: Config synced to $PEER successfully"
        echo "Config synced to $PEER"
    else
        logger "haproxy-sync: Failed to reload on $PEER"
        echo "ERROR: Failed to reload on peer"
        exit 1
    fi
else
    logger "haproxy-sync: Failed to copy config to $PEER"
    echo "ERROR: Failed to copy config to peer"
    exit 1
fi
