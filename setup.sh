#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

clear
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}     ПОЛНЫЙ УСТАНОВЩИК (5 КЛИЕНТОВ + ХАНИПОТ)       ${NC}"
echo -e "${GREEN}====================================================${NC}"

read -p "Введите домен (напр. llm.atms2006.ru): " RAW_DOMAIN
DOMAIN=$(echo "$RAW_DOMAIN" | tr -cd 'a-zA-Z0-9.-')

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Ошибка: домен пустой!${NC}"
    exit 1
fi

echo -e "\n${YELLOW}Выберите протоколы (1 2 3 4):${NC}"
echo "1) VLESS Reality + XHTTP (TCP 443)"
echo "2) Hysteria 2 (UDP 443)"
echo "3) Masque (UDP 59215)"
echo "4) SOCKS5 (TCP 65102)"
read -p "Ваш выбор: " PROTOCOLS

echo -e "\n${YELLOW}Выберите тип сайта-заглушки (Honeypot):${NC}"
echo "1) Nexus AI Node (Строгий интерфейс входа в ИИ-систему)"
echo "2) SQL Dump (Слитый дамп базы данных)"
echo "3) Admin Panel (Классическая страница входа)"
echo "4) TeleHealth Portal (Портал телемедицины)"
read -p "Ваш выбор (1-4): " DECOY_CHOICE

PANEL_USER="admin"
PANEL_PASS="admin"

WEB_PATH="/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)/"
SUB_PATH="/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)/"
PANEL_PORT=$(( ( RANDOM % 50000 ) + 10000 ))
SUB_PORT=$(( ( RANDOM % 50000 ) + 10000 ))
NGINX_PORT="40000"

echo -e "\n${YELLOW}Очистка...${NC}"
systemctl stop x-ui nginx >/dev/null 2>&1 || true
apt purge -y nginx nginx-common nginx-core >/dev/null 2>&1 || true
rm -rf /etc/x-ui /usr/local/x-ui /usr/bin/x-ui /etc/systemd/system/x-ui.service /etc/nginx /var/www/decoy /var/www/certbot

export DEBIAN_FRONTEND=noninteractive
apt update && apt install -y nginx certbot curl wget sqlite3 ufw openssl python3

# Файрвол
SSH_PORT=$(ss -tlnp | grep sshd | awk '{print $4}' | awk -F':' '{print $NF}' | head -n 1)
SSH_PORT=${SSH_PORT:-22}
ufw allow "$SSH_PORT"/tcp; ufw allow 80/tcp; ufw allow 443/tcp; ufw allow 443/udp; ufw allow 59215/tcp; ufw allow 59215/udp; ufw allow 65102/tcp; ufw --force enable

# BBR
cat > /etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl --system >/dev/null 2>&1

# --- ГЕНЕРАЦИЯ ХАНИПОТА ---
mkdir -p /var/www/decoy /var/www/certbot

if [ "$DECOY_CHOICE" = "1" ]; then
    cat > /var/www/decoy/index.html <<'HTMLEOF'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Nexus AI Node</title><style>body{background-color:#0f172a;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;color:#fff}.login-box{background-color:#1e293b;padding:40px;border-radius:12px;box-shadow:0 10px 25px rgba(0,0,0,0.5);width:340px;text-align:center;box-sizing:border-box}.logo{font-size:24px;font-weight:700;color:#0ea5e9;margin-bottom:8px}.subtitle{color:#94a3b8;font-size:13px;margin-bottom:30px}input{width:100%;padding:12px 16px;margin-bottom:16px;background-color:#0f172a;border:1px solid #334155;border-radius:6px;color:#fff;font-size:14px;box-sizing:border-box;transition:border-color 0.2s}input:focus{outline:none;border-color:#0ea5e9}button{width:100%;padding:14px;background-color:#0ea5e9;color:#fff;border:none;border-radius:6px;font-size:15px;font-weight:600;cursor:pointer;margin-top:8px}button:hover{background-color:#0284c7}.footer{margin-top:24px;font-size:12px;color:#475569}</style></head><body><div class="login-box"><div class="logo">Nexus AI Node</div><div class="subtitle">Restricted Access Area</div><form id="loginForm"><input type="text" placeholder="Email / Node ID" required><input type="password" placeholder="Access Key" required><button type="submit" id="submitBtn">Initialize Connection</button></form><div class="footer">v 2.4.1 | End-to-End Encrypted</div></div><script>document.getElementById('loginForm').addEventListener('submit',function(e){e.preventDefault();const btn=document.getElementById('submitBtn');const inputs=document.querySelectorAll('input');btn.innerText='Connecting...';btn.style.backgroundColor='#475569';btn.disabled=true;inputs.forEach(i=>i.disabled=true);setTimeout(()=>{btn.innerText='Access Denied';btn.style.backgroundColor='#ef4444';setTimeout(()=>{btn.innerText='Initialize Connection';btn.style.backgroundColor='#0ea5e9';btn.disabled=false;inputs.forEach(i=>{i.disabled=false;i.value='';});},2000);},1500);});</script></body></html>
HTMLEOF
elif [ "$DECOY_CHOICE" = "2" ]; then
    cat > /var/www/decoy/index.html <<'HTMLEOF'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>db_backup_2026.sql</title><style>body{background-color:#1e1e1e;color:#d4d4d4;font-family:'Courier New',Courier,monospace;font-size:14px;padding:20px;white-space:pre-wrap;line-height:1.5}.c{color:#6a9955}.t{color:#4ec9b0}.s{color:#ce9178}.n{color:#b5cea8}</style></head><body><span class="c">-- MySQL dump 10.13 Distrib 8.0.32, for Linux (x86_64)<br>-- Host: localhost Database: xui_panel<br>-- ------------------------------------------------------<br>-- Server version8.0.32</span><br><br>DROP TABLE IF EXISTS <span class="t">`users`</span>;<br>CREATE TABLE <span class="t">`users`</span> (<br>  <span class="t">`id`</span> int NOT NULL AUTO_INCREMENT,<br>  <span class="t">`username`</span> varchar(255) NOT NULL,<br>  <span class="t">`password`</span> varchar(255) NOT NULL,<br>  PRIMARY KEY (<span class="t">`id`</span>)<br>) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;<br><br>LOCK TABLES <span class="t">`users`</span> WRITE;<br>INSERT INTO <span class="t">`users`</span> VALUES (<span class="n">1</span>,<span class="s">'admin'</span>,<span class="s">'$2a$10$X8vP1jK9z7wQ2mR4tY6uO.e5N1c3B7x9A2s4D6f8G0h1J3k5L7m9N'</span>);<br>INSERT INTO <span class="t">`users`</span> VALUES (<span class="n">2</span>,<span class="s">'root'</span>,<span class="s">'$2a$10$Q9wE1rT3y5U7iO9p0A2s4D6f8G0h1J3k5L7m9N1b3V5c7X9z2Q4w6E'</span>);<br>UNLOCK TABLES;<br><br><span class="c">-- Dump completed on 2026-10-28 12:00:00</span></body></html>
HTMLEOF
elif [ "$DECOY_CHOICE" = "3" ]; then
    cat > /var/www/decoy/index.html <<'HTMLEOF'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Admin Panel</title><style>body{background-color:#2d3748;font-family:Arial,sans-serif;display:flex;justify-content:center;align-items:center;height:100vh;margin:0}.login-box{background:#fff;padding:40px;border-radius:8px;box-shadow:0 10px 25px rgba(0,0,0,0.3);width:320px;text-align:center}.logo{font-size:22px;font-weight:bold;color:#2b6cb0;margin-bottom:20px}input{width:100%;padding:12px;margin-bottom:15px;border:1px solid #cbd5e0;border-radius:4px;box-sizing:border-box;font-size:14px}button{width:100%;padding:12px;background-color:#2b6cb0;color:#fff;border:none;border-radius:4px;font-size:16px;font-weight:bold;cursor:pointer}button:hover{background-color:#2c5282}.error{color:#e53e3e;font-size:13px;margin-top:15px;display:none;font-weight:bold}</style></head><body><div class="login-box"><div class="logo">System Administration</div><form id="loginForm"><input type="text" placeholder="Username" required><input type="password" placeholder="Password" required><button type="submit" id="submitBtn">Login</button></form><div id="error" class="error">Access Denied: Invalid Credentials</div></div><script>document.getElementById('loginForm').addEventListener('submit',function(e){e.preventDefault();document.getElementById('error').style.display='block';document.querySelectorAll('input').forEach(i=>i.value='');});</script></body></html>
HTMLEOF
else
    cat > /var/www/decoy/index.html <<'HTMLEOF'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>TeleHealth Portal</title><style>body{background-color:#f0f4f8;font-family:'Segoe UI',Tahoma,Geneva,Verdana,sans-serif;display:flex;justify-content:center;align-items:center;height:100vh;margin:0}.login-box{background:#fff;padding:40px;border-radius:10px;box-shadow:0 4px 15px rgba(0,0,0,0.1);width:360px;text-align:center}.logo{font-size:24px;font-weight:bold;color:#0d9488;margin-bottom:10px}.subtitle{color:#64748b;font-size:14px;margin-bottom:30px}input{width:100%;padding:12px;margin-bottom:15px;border:1px solid #cbd5e1;border-radius:6px;box-sizing:border-box;font-size:14px}input:focus{outline:none;border-color:#0d9488;box-shadow:0 0 0 2px rgba(13,148,136,0.2)}button{width:100%;padding:12px;background:#0d9488;color:#fff;border:none;border-radius:6px;font-size:16px;font-weight:bold;cursor:pointer;margin-top:10px}button:hover{background:#0f766e}.error{color:#ef4444;font-size:13px;margin-top:15px;display:none;font-weight:bold}.footer{margin-top:20px;font-size:12px;color:#94a3b8}</style></head><body><div class="login-box"><div class="logo">TeleHealth System</div><div class="subtitle">Medical Staff & Patient Portal</div><form id="loginForm"><input type="text" placeholder="Doctor ID / Email" required><input type="password" placeholder="Password" required><button type="submit" id="submitBtn">Secure Login</button></form><div id="error" class="error">Error: Invalid credentials or access denied.</div><div class="footer">Authorized personnel only. HIPAA Compliant.</div></div><script>document.getElementById('loginForm').addEventListener('submit',function(e){e.preventDefault();document.getElementById('error').style.display='block';document.querySelector('input[type="password"]').value='';});</script></body></html>
HTMLEOF
fi

CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

if [ ! -f "$CERT_PATH" ]; then
    cat > /etc/nginx/sites-available/decoy <<EOF
server {
    listen 80; server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { root /var/www/decoy; index index.html; }
}
EOF
    ln -sf /etc/nginx/sites-available/decoy /etc/nginx/sites-enabled/decoy
    systemctl restart nginx
    certbot certonly --webroot -w /var/www/certbot -d "$DOMAIN" --non-interactive --agree-tos -m "mrcogahmed@gmail.com" || true
fi

mkdir -p /etc/letsencrypt/renewal-hooks/deploy
echo -e '#!/bin/bash\nsystemctl reload nginx' > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh

# Установка 3x-ui
echo -e "${YELLOW}Установка 3x-ui...${NC}"
wget -qO /tmp/xui-install.sh https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh
printf "1\nn\n4\ny\n" | bash /tmp/xui-install.sh
sleep 7
systemctl stop x-ui
rm -f /etc/x-ui/x-ui.db
systemctl start x-ui
sleep 3
systemctl stop x-ui

export DB_DOMAIN="$DOMAIN"
export DB_PANEL_PORT="$PANEL_PORT"
export DB_WEB_PATH="$WEB_PATH"
export DB_SUB_PORT="$SUB_PORT"
export DB_SUB_PATH="$SUB_PATH"
export DB_CERT_PATH="$CERT_PATH"
export DB_KEY_PATH="$KEY_PATH"
export PROTOCOLS="$PROTOCOLS"

echo -e "${YELLOW}Запись конфигурации...${NC}"
python3 << 'PYEOF'
import os, sqlite3, json, secrets, uuid, subprocess

DOMAIN = os.environ['DB_DOMAIN']
PANEL_PORT = os.environ['DB_PANEL_PORT']
WEB_PATH = os.environ['DB_WEB_PATH']
SUB_PORT = os.environ['DB_SUB_PORT']
SUB_PATH = os.environ['DB_SUB_PATH']
CERT_PATH = os.environ['DB_CERT_PATH']
KEY_PATH = os.environ['DB_KEY_PATH']
PROTOCOLS = os.environ['PROTOCOLS'].split()

db = '/etc/x-ui/x-ui.db'
conn = sqlite3.connect(db)
c = conn.cursor()

c.execute("DELETE FROM clients")
c.execute("DELETE FROM client_inbounds")
c.execute("DELETE FROM inbounds")
c.execute("DELETE FROM settings WHERE key IN ('webPort', 'webBasePath', 'webListen', 'subPort', 'subPath', 'subListen', 'subEnable', 'subDomain', 'subURI')")

settings = [
    ('webPort', PANEL_PORT), ('webBasePath', WEB_PATH), ('webListen', '127.0.0.1'),
    ('subPort', SUB_PORT), ('subPath', SUB_PATH), ('subListen', '127.0.0.1'),
    ('subEnable', 'true'), ('subDomain', DOMAIN), ('subURI', f"https://{DOMAIN}{SUB_PATH}")
]
c.executemany("INSERT INTO settings (key, value) VALUES (?, ?)", settings)

client_names = ["zfold", "passwall", "work", "TV", "note10"]
client_data = []

for name in client_names:
    c_uuid = str(uuid.uuid4())
    c_sub = secrets.token_hex(8)
    client_data.append({"name": name, "uuid": c_uuid, "sub_id": c_sub})
    
    c.execute("INSERT OR REPLACE INTO clients (email, sub_id, uuid, password, auth, enable) VALUES (?, ?, ?, ?, ?, 1)", 
              (name, c_sub, c_uuid, c_uuid, c_uuid))
    client_data[-1]["db_id"] = c.lastrowid

xray_bin = subprocess.check_output("find /usr/local/x-ui/bin/ -name 'xray*' -type f | head -n 1", shell=True).decode().strip()
keys = subprocess.check_output(f"{xray_bin} x25519", shell=True).decode()
priv_key = [line.split()[-1] for line in keys.split('\n') if 'Private' in line][0]
pub_key = [line.split()[-1] for line in keys.split('\n') if 'Password' in line or 'Public' in line][0]

# 1. VLESS Reality
if "1" in PROTOCOLS:
    short_ids = [secrets.token_hex(n)[:n] for n in [6, 2, 4, 8, 16, 10, 12, 14]]
    spider_x = f"/{secrets.token_urlsafe(10)[:15]}"
    
    vless_clients = []
    for cd in client_data:
        vless_clients.append({"id": cd["uuid"], "email": cd["name"], "subId": cd["sub_id"], "flow": "", "limitIp": 0, "totalGB": 0, "expiryTime": 0, "enable": True, "tgId": 0, "reset": 0})
        
    settings_json = json.dumps({"clients": vless_clients, "decryption": "none", "encryption": "none"})
    stream_json = json.dumps({
        "network": "xhttp", "security": "reality",
        "xhttpSettings": {"path": "/api/v3/stream", "mode": "stream-one", "xPaddingBytes": "100-1000", "scMaxBufferedPosts": 30, "scStreamUpServerSecs": "20-80"},
        "realitySettings": {"show": False, "xver": 0, "target": "127.0.0.1:40000", "serverNames": [DOMAIN], "privateKey": priv_key, "shortIds": short_ids, "settings": {"publicKey": pub_key, "fingerprint": "firefox", "spiderX": spider_x}},
        "sockopt": {"tcpFastOpen": True, "tcpcongestion": "bbr"}
    })
    # ИСПОЛЬЗУЕМ INSERT OR REPLACE!
    c.execute("INSERT OR REPLACE INTO inbounds (user_id, port, protocol, settings, stream_settings, tag, sniffing, enable) VALUES (1, 443, 'vless', ?, ?, 'in-443-tcp', '{\"enabled\":true,\"destOverride\":[\"http\",\"tls\",\"quic\",\"fakedns\"]}', 1)", (settings_json, stream_json))
    inbound_id = c.lastrowid
    for cd in client_data:
        c.execute("INSERT OR REPLACE INTO client_inbounds (client_id, inbound_id) VALUES (?, ?)", (cd["db_id"], inbound_id))

# 2. Hysteria 2
if "2" in PROTOCOLS:
    hy_clients = []
    for cd in client_data:
        hy_clients.append({"auth": cd["uuid"], "email": cd["name"]})
        
    settings_json = json.dumps({"clients": hy_clients, "version": 2})
    stream_json = json.dumps({
        "network": "hysteria",
        "hysteriaSettings": {"version": 2, "udpIdleTimeout": 60, "masquerade": {"type": "proxy", "dir": "", "url": f"https://{DOMAIN}/", "rewriteHost": True, "insecure": False, "content": "", "headers": {}, "statusCode": 0}},
        "security": "tls",
        "tlsSettings": {
            "serverName": DOMAIN, "minVersion": "1.3", "maxVersion": "1.3", "cipherSuites": "", "rejectUnknownSni": True, "disableSystemRoot": True, "enableSessionResumption": True,
            "certificates": [{"ocspStapling": 0, "oneTimeLoading": False, "usage": "encipherment", "buildChain": False, "certificateFile": CERT_PATH, "keyFile": KEY_PATH, "useFile": True}],
            "alpn": ["h3"], "echServerKeys": "", "settings": {"fingerprint": "firefox", "echConfigList": "", "pinnedPeerCertSha256": [], "verifyPeerCertByName": ""}
        },
        "finalmask": {"quicParams": {"congestion": "bbr", "maxIncomingStreams": 2048, "initStreamReceiveWindow": 16777216, "maxStreamReceiveWindow": 16777216, "initConnectionReceiveWindow": 33554432, "maxConnectionReceiveWindow": 33554432, "bbrProfile": "aggressive"}}
    })
    c.execute("INSERT OR REPLACE INTO inbounds (user_id, port, protocol, settings, stream_settings, tag, sniffing, enable) VALUES (1, 443, 'hysteria', ?, ?, 'in-443-udp', '{\"enabled\":true,\"destOverride\":[\"http\",\"tls\"]}', 1)", (settings_json, stream_json))
    inbound_id = c.lastrowid
    for cd in client_data:
        c.execute("INSERT OR REPLACE INTO client_inbounds (client_id, inbound_id) VALUES (?, ?)", (cd["db_id"], inbound_id))

# 3. Masque
if "3" in PROTOCOLS:
    masque_clients = []
    for cd in client_data:
        masque_clients.append({"email": cd["name"], "pass": cd["uuid"]})
        
    settings_json = json.dumps({"clients": masque_clients, "address": ["10.14.0.1/24", "fd14::1/64"]})
    stream_json = json.dumps({
        "network": "masque", "security": "tls",
        "masqueSettings": {"path": "/.well-known/masque/ip/*/*/"},
        "tlsSettings": {"alpn": ["h3", "h2"], "certificates": [{"certificateFile": CERT_PATH, "keyFile": KEY_PATH}], "serverName": DOMAIN, "minVersion": "1.3", "maxVersion": "1.3"}
    })
    c.execute("INSERT OR REPLACE INTO inbounds (user_id, port, protocol, settings, stream_settings, tag, sniffing, enable) VALUES (1, 59215, 'masque', ?, ?, 'inbound-59215-udp', '{\"enabled\":true,\"destOverride\":[\"http\",\"tls\"]}', 1)", (settings_json, stream_json))
    inbound_id = c.lastrowid
    for cd in client_data:
        c.execute("INSERT OR REPLACE INTO client_inbounds (client_id, inbound_id) VALUES (?, ?)", (cd["db_id"], inbound_id))

# 4. SOCKS5
if "4" in PROTOCOLS:
    socks_clients = [{"user": "masha", "pass": "wlopfmAb531Mhptwb_oNgYOXpizblX5O"}, {"user": "sofa", "pass": "wlopfmAb531Mhptwb_oNgYOXpizblX5O"}]
    
    settings_json = json.dumps({"auth": "password", "accounts": socks_clients, "udp": True})
    c.execute("INSERT OR REPLACE INTO inbounds (user_id, port, protocol, settings, stream_settings, tag, sniffing, enable) VALUES (1, 65102, 'socks', ?, '{}', 'in-65102-tcp', '{\"enabled\":true,\"destOverride\":[\"http\",\"tls\",\"quic\",\"fakedns\"],\"routeOnly\":true}', 1)", (settings_json,))
    inbound_id = c.lastrowid
    
    for cl in socks_clients:
        c.execute("INSERT OR REPLACE INTO clients (email, sub_id, uuid, password, auth, enable) VALUES (?, ?, ?, ?, ?, 1)", (cl["user"], secrets.token_hex(8), cl["pass"], cl["pass"], cl["pass"]))
        socks_db_id = c.lastrowid
        c.execute("INSERT OR REPLACE INTO client_inbounds (client_id, inbound_id) VALUES (?, ?)", (socks_db_id, inbound_id))

template = {
    "log": {"loglevel": "warning"},
    "outbounds": [{"protocol": "freedom", "tag": "direct"}, {"protocol": "blackhole", "tag": "blocked"}],
    "routing": {"domainStrategy": "AsIs", "rules": [{"type": "field", "ip": ["geoip:private"], "outboundTag": "blocked"}]}
}
c.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('xrayTemplateConfig', ?)", (json.dumps(template),))
conn.commit()
conn.close()
print("\033[0;32mУспешно! Никаких ошибок.\033[0m")
PYEOF

# Nginx
if [[ "$PROTOCOLS" == *"1"* ]]; then
    LISTEN_NGINX="listen 127.0.0.1:${NGINX_PORT} ssl http2;"
    FALLBACK_CONFIG="server {
    listen 80; server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$host\$request_uri; }
}"
else
    LISTEN_NGINX="listen 443 ssl http2;"
    FALLBACK_CONFIG=""
fi

cat > /etc/nginx/sites-available/decoy <<EOF
$FALLBACK_CONFIG
server {
    $LISTEN_NGINX
    server_name $DOMAIN;
    ssl_certificate $CERT_PATH;
    ssl_certificate_key $KEY_PATH;
    set_real_ip_from 127.0.0.1; real_ip_header X-Forwarded-For;
    
    location / { root /var/www/decoy; index index.html; }
    location $WEB_PATH { proxy_pass http://127.0.0.1:$PANEL_PORT; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; }
    location $SUB_PATH { proxy_pass http://127.0.0.1:$SUB_PORT; proxy_set_header Host \$host; }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/decoy /etc/nginx/sites-enabled/decoy
nginx -t && systemctl restart nginx

systemctl start x-ui
sleep 3
x-ui setting -username "$PANEL_USER" -password "$PANEL_PASS" >/dev/null 2>&1
systemctl restart x-ui
sleep 2

echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}        ВСЁ ГОТОВО! СИСТЕМА ЗАПУЩЕНА.               ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "Логин: ${YELLOW}$PANEL_USER${NC} | Пароль: ${YELLOW}$PANEL_PASS${NC}"
echo -e "ССЫЛКА НА ПАНЕЛЬ: ${YELLOW}https://$DOMAIN$WEB_PATH${NC}"
echo -e "ССЫЛКА НА ПОДПИСКИ: ${YELLOW}https://$DOMAIN$SUB_PATH${NC}"
echo -e "${GREEN}====================================================${NC}"
