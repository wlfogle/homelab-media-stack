#!/usr/bin/env bash
# =============================================================================
# setup-vnc.sh — Tiamat (Proxmox host) VNC + noVNC Desktop Setup
# Installs XFCE4 + TigerVNC + noVNC web interface
# View from: native VNC client, any browser, Android, Fire TV (Silk browser)
# =============================================================================
set -euo pipefail

VNC_PORT="5900"
NOVNC_PORT="6080"
VNC_RESOLUTION="1920x1080"
VNC_DEPTH="24"

# ── Prompt for VNC password ──────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   Tiamat VNC Desktop Setup               ║"
echo "╚══════════════════════════════════════════╝"
echo ""
read -rsp "Enter VNC password (min 6 chars): " VNC_PASS
echo ""
read -rsp "Confirm VNC password: " VNC_PASS2
echo ""
if [[ "$VNC_PASS" != "$VNC_PASS2" ]]; then
    echo "ERROR: Passwords do not match." >&2
    exit 1
fi
if [[ ${#VNC_PASS} -lt 6 ]]; then
    echo "ERROR: Password must be at least 6 characters." >&2
    exit 1
fi

# ── Install dependencies ─────────────────────────────────────────────────────
echo "[1/6] Installing XFCE4 + TigerVNC + noVNC..."
apt-get update -y
apt-get install -y \
    xfce4 \
    xfce4-goodies \
    tigervnc-standalone-server \
    tigervnc-common \
    dbus-x11 \
    xfonts-base \
    x11-xserver-utils \
    novnc \
    websockify \
    python3 \
    --no-install-recommends

# ── Set VNC password ─────────────────────────────────────────────────────────
echo "[2/6] Setting VNC password..."
mkdir -p /root/.vnc
# vncpasswd removed in TigerVNC 1.15 — generate passwd file via Python3 DES
python3 - "$VNC_PASS" <<'PYEOF'
import sys, subprocess, os
p = (sys.argv[1].encode() + b'\x00'*8)[:8]
key = bytes(int('{:08b}'.format(b)[::-1],2) for b in p)
# OpenSSL 3.x requires -provider legacy for DES
out = subprocess.run(
    ['openssl','enc','-des-ecb','-provider','legacy','-provider','default',
     '-nosalt','-nopad','-K',key.hex()],
    input=b'\x00'*8, capture_output=True, check=True).stdout[:8]
open('/root/.vnc/passwd','wb').write(out)
os.chmod('/root/.vnc/passwd', 0o600)
PYEOF
unset VNC_PASS VNC_PASS2

# ── Write xstartup ───────────────────────────────────────────────────────────
echo "[3/6] Writing VNC xstartup for XFCE4..."
cat > /root/.vnc/xstartup << 'EOF'
#!/usr/bin/env bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XKL_XMODMAP_DISABLE=1
export DISPLAY=:0

# Start dbus if not running
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval "$(dbus-launch --sh-syntax)"
fi

# Start XFCE4
exec startxfce4
EOF
chmod +x /root/.vnc/xstartup

# ── Write VNC config ─────────────────────────────────────────────────────────
echo "[4/6] Writing VNC server config..."
cat > /root/.vnc/config << EOF
geometry=${VNC_RESOLUTION}
depth=${VNC_DEPTH}
localhost=no
alwaysshared
EOF

# ── Create systemd service ───────────────────────────────────────────────────
echo "[5/6] Creating systemd service (vncserver@.service)..."
cat > /etc/systemd/system/vncserver@.service << 'EOF'
[Unit]
Description=TigerVNC Server (display %i)
After=syslog.target network.target

[Service]
Type=forking
User=root
WorkingDirectory=/root
PIDFile=/root/.vnc/%H%i.pid
ExecStartPre=-/usr/bin/tigervncserver -kill %i
ExecStart=/usr/bin/tigervncserver %i -depth 24 -geometry 1920x1080 -localhost no -alwaysshared
ExecStop=/usr/bin/tigervncserver -kill %i
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vncserver@:0.service
systemctl start  vncserver@:0.service

# ── noVNC websockify service ─────────────────────────────────────────────────
echo "[6/6] Setting up noVNC web interface on port ${NOVNC_PORT}..."

NOVNC_DIR=$(find /usr/share -maxdepth 1 -name 'novnc' -o -name 'noVNC' 2>/dev/null | head -1)
if [[ -z "$NOVNC_DIR" ]]; then
    NOVNC_DIR="/usr/share/novnc"
fi

cat > /etc/systemd/system/novnc.service << EOF
[Unit]
Description=noVNC Web Interface for Tiamat Desktop
After=network.target vncserver@:0.service
Requires=vncserver@:0.service

[Service]
Type=simple
ExecStart=/usr/bin/websockify --web=${NOVNC_DIR} ${NOVNC_PORT} localhost:${VNC_PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable novnc.service
systemctl start  novnc.service

# ── Open firewall ports ───────────────────────────────────────────────────────
apt-get install -y iptables-persistent
for PORT in "${VNC_PORT}" "${NOVNC_PORT}"; do
    if ! iptables -C INPUT -p tcp --dport "${PORT}" -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p tcp --dport "${PORT}" -j ACCEPT
    fi
done
netfilter-persistent save

# ── Done ─────────────────────────────────────────────────────────────────────
TIAMAT_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║   VNC + noVNC is LIVE on Tiamat                                  ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
printf "║   VNC (native):  %-46s ║\n" "${TIAMAT_IP}:${VNC_PORT}"
printf "║   noVNC (web):   %-46s ║\n" "http://${TIAMAT_IP}:${NOVNC_PORT}/vnc.html"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║   Connect from anywhere:                                         ║"
echo "║   • Laptop:    vncviewer ${TIAMAT_IP}:5900              ║"
echo "║   • Android:   VNC Viewer app → ${TIAMAT_IP}:5900       ║"
printf "║   • Fire TV:   Silk browser → http://%-28s ║\n" "${TIAMAT_IP}:6080/vnc.html"
echo "║   • Any browser: same noVNC URL above                            ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
