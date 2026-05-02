#!/bin/bash
# ---------------------------------------------------------------------------
# EMQX VM startup script — Debian 12
#
# Installs EMQX OSS 5.x and a Python Pub/Sub bridge sidecar.
# The bridge subscribes to EMQX on localhost (plain MQTT, not exposed
# externally) and forwards every message to the flowterra-iot-ingress
# Pub/Sub topic using the VM's service account (ADC — no key file needed).
#
# External access: MQTT/TLS (8883) only. Self-signed cert for dev;
# replace with Let's Encrypt (certbot) before pilot customer onboarding.
# ---------------------------------------------------------------------------

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

PROJECT_ID="${project_id}"
PUBSUB_TOPIC="${pubsub_topic}"
EMQX_VERSION="5.6.0"
BRIDGE_USER="mqtt-bridge"

log() { echo "[startup] $*" | tee -a /var/log/flowterra-startup.log; }

log "=== Flowterra EMQX startup: $(date) ==="

# ---------------------------------------------------------------------------
# 1. Install EMQX via official deb package
# ---------------------------------------------------------------------------
log "Installing EMQX $EMQX_VERSION..."
apt-get update -qq
apt-get install -y -qq curl wget gnupg lsb-release

DEB_URL="https://www.emqx.com/en/downloads/broker/$EMQX_VERSION/emqx-$EMQX_VERSION-debian12-amd64.deb"
wget -q -O /tmp/emqx.deb "$DEB_URL"
apt-get install -y -qq /tmp/emqx.deb
rm /tmp/emqx.deb

# ---------------------------------------------------------------------------
# 2. Generate self-signed TLS cert (dev only)
#    Replace with Let's Encrypt before pilot onboarding.
# ---------------------------------------------------------------------------
log "Generating self-signed TLS cert..."
mkdir -p /etc/emqx/tls
openssl req -x509 -newkey rsa:2048 \
  -keyout /etc/emqx/tls/server.key \
  -out    /etc/emqx/tls/server.crt \
  -days   365 -nodes \
  -subj   "/CN=flowterra-emqx" 2>/dev/null
chmod 640 /etc/emqx/tls/server.key
chown root:emqx /etc/emqx/tls/server.key

# ---------------------------------------------------------------------------
# 3. Configure EMQX
#    - Enable MQTT/TLS on 8883 (external)
#    - Keep plain MQTT on 1883 bound to localhost only (bridge sidecar)
#    - Disable EMQX dashboard external access
# ---------------------------------------------------------------------------
log "Writing EMQX config..."
cat > /etc/emqx/emqx.conf << 'EMQXCONF'
node {
  name = "emqx@127.0.0.1"
  cookie = "flowterra-emqx-cookie"
  data_dir = "/var/lib/emqx"
}

log {
  file_handlers.default {
    level = warning
    file  = "/var/log/emqx/emqx.log"
  }
}

# External listener — MQTT over TLS (gateways connect here)
listeners.ssl.default {
  bind = "0.0.0.0:8883"
  ssl_options {
    certfile = "/etc/emqx/tls/server.crt"
    keyfile  = "/etc/emqx/tls/server.key"
    verify   = verify_none
  }
}

# Internal listener — plain MQTT, localhost only (bridge sidecar)
listeners.tcp.internal {
  bind = "127.0.0.1:1883"
}

# Disable default external plain MQTT listener
listeners.tcp.default.enabled = false

dashboard {
  listeners.http.bind = "127.0.0.1:18083"
}

# Anonymous access for MVP dev — replace with gateway username/password auth
# before pilot onboarding (load creds from Secret Manager).
allow_anonymous = true
EMQXCONF

# ---------------------------------------------------------------------------
# 4. Start EMQX
# ---------------------------------------------------------------------------
log "Starting EMQX..."
systemctl enable emqx
systemctl start emqx

# Wait for EMQX to accept connections
for i in $(seq 1 20); do
  if nc -z 127.0.0.1 1883 2>/dev/null; then
    log "EMQX ready after $i attempts."
    break
  fi
  sleep 3
done

# ---------------------------------------------------------------------------
# 5. Install Python Pub/Sub bridge dependencies
# ---------------------------------------------------------------------------
log "Installing Python bridge dependencies..."
apt-get install -y -qq python3 python3-pip python3-venv

python3 -m venv /opt/flowterra-bridge
/opt/flowterra-bridge/bin/pip install --quiet \
  paho-mqtt==2.1.0 \
  google-cloud-pubsub==2.21.0

# ---------------------------------------------------------------------------
# 6. Write the bridge script
# ---------------------------------------------------------------------------
log "Writing MQTT → Pub/Sub bridge..."
cat > /opt/flowterra-bridge/bridge.py << PYEOF
#!/usr/bin/env python3
"""
MQTT → GCP Pub/Sub bridge.

Subscribes to EMQX on localhost (plain MQTT, never exposed externally)
and publishes each message as a Pub/Sub message to flowterra-iot-ingress.
Authentication uses the VM's service account via Application Default
Credentials — no key file required.
"""
import json
import logging
import os
import signal
import sys
import time

import paho.mqtt.client as mqtt
from google.cloud import pubsub_v1

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [bridge] %(levelname)s %(message)s",
)
log = logging.getLogger(__name__)

PROJECT_ID   = "$PROJECT_ID"
PUBSUB_TOPIC = "$PUBSUB_TOPIC"
MQTT_HOST    = "127.0.0.1"
MQTT_PORT    = 1883
SUBSCRIBE    = "iot/ingress/#"

publisher  = pubsub_v1.PublisherClient()
topic_path = publisher.topic_path(PROJECT_ID, PUBSUB_TOPIC)

def on_connect(client, userdata, flags, reason_code, properties=None):
    if reason_code == 0:
        log.info("Connected to EMQX; subscribing to %s", SUBSCRIBE)
        client.subscribe(SUBSCRIBE, qos=1)
    else:
        log.error("MQTT connect failed: reason_code=%s", reason_code)

def on_message(client, userdata, msg):
    try:
        payload = msg.payload
        # Attach MQTT topic as a Pub/Sub message attribute for ingest-fn routing.
        future = publisher.publish(
            topic_path,
            data=payload,
            mqtt_topic=msg.topic,
        )
        future.result(timeout=10)
    except Exception as exc:
        log.error("Pub/Sub publish error: %s", exc)

def on_disconnect(client, userdata, disconnect_flags, reason_code, properties=None):
    log.warning("Disconnected from EMQX (reason_code=%s); will reconnect.", reason_code)

def shutdown(sig, frame):
    log.info("Shutting down bridge.")
    sys.exit(0)

signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGINT, shutdown)

client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="flowterra-pubsub-bridge")
client.on_connect    = on_connect
client.on_message    = on_message
client.on_disconnect = on_disconnect

while True:
    try:
        client.connect(MQTT_HOST, MQTT_PORT, keepalive=60)
        client.loop_forever()
    except Exception as exc:
        log.error("Connection error: %s — retrying in 10 s", exc)
        time.sleep(10)
PYEOF

chmod +x /opt/flowterra-bridge/bridge.py

# ---------------------------------------------------------------------------
# 7. Install bridge as a systemd service
# ---------------------------------------------------------------------------
log "Installing bridge systemd service..."
cat > /etc/systemd/system/flowterra-bridge.service << SVCEOF
[Unit]
Description=Flowterra MQTT → Pub/Sub Bridge
After=network-online.target emqx.service
Wants=network-online.target
Requires=emqx.service

[Service]
Type=simple
User=nobody
ExecStart=/opt/flowterra-bridge/bin/python /opt/flowterra-bridge/bridge.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=flowterra-bridge

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable flowterra-bridge
systemctl start flowterra-bridge

log "=== Startup complete ==="
