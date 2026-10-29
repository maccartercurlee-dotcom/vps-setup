#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

clear
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}     УСТАНОВЩИК (ЧИСТЫЕ НАСТРОЙКИ + СОХРАНЕНИЕ КЛЮЧЕЙ) ${NC}"
echo -e "${GREEN}====================================================${NC}"

read -p "Введите ваш домен (например, llm.atms2006.ru): " DOMAIN

PANEL_USER="admin"
PANEL_PASS="admin"
EMAIL="mrcogahmed@gmail.com"

WEB_PATH="/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)/"
SUB_PATH="/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)/"
PANEL_PORT=$(( ( RANDOM % 50000 ) + 10000 ))
SUB_PORT=$(( ( RANDOM % 50000 ) + 10000 ))
NGINX_PORT="40000"

echo -e "\n${YELLOW}Выберите протоколы (введите номера через пробел, напр. '1 2'):${NC}"
echo "1) VLESS Reality + XHTTP (TCP 443)"
echo "2) Hysteria 2 (UDP 443)"
echo "3) Masque (UDP 59215)"
echo "4) SOCKS5 (TCP 65102) + 2 доп. клиента"
read -p "Ваш выбор: " PROTOCOLS

if [ -z "$PROTOCOLS" ]; then
    echo -e "${RED}Вы ничего не выбрали. Выход.${NC}"
    exit 1
fi

echo -e "\n${YELLOW}Сохранить существующие ключи клиентов (UUID, пароли)?${NC}"
echo "1) Да, у меня есть старый JSON (устройства подключатся без изменений)"
echo "2) Нет, сгенерировать новые ключи"
read -p "Ваш выбор (1-2): " KEEP_KEYS

USE_OLD_JSON="false"
if [ "$KEEP_KEYS" = "1" ]; then
    USE_OLD_JSON="true"
    echo -e "\n${YELLOW}Сейчас откроется nano.${NC} Вставьте ваш СТАРЫЙ JSON-конфиг."
    echo -e "Скрипт возьмет из него ТОЛЬКО UUID и пароли клиентов."
    sleep 3
    touch /tmp/old_config.json
    nano /tmp/old_config.json
    if ! python3 -c "import json; json.load(open('/tmp/old_config.json'))" 2>/dev/null; then
        echo -e "${RED}ОШИБКА: Невалидный JSON!${NC}"
        exit 1
    fi
fi

echo -e "\n${YELLOW}Очистка старых установок...${NC}"
systemctl stop x-ui nginx >/dev/null 2>&1 || true
apt purge -y nginx nginx-common nginx-core >/dev/null 2>&1 || true
rm -rf /etc/x-ui /usr/local/x-ui /usr/bin/x-ui /etc/systemd/system/x-ui.service /etc/nginx /var/www/decoy /var/www/certbot

export DEBIAN_FRONTEND=noninteractive
apt update && apt install -y nginx certbot curl wget sqlite3 ufw openssl python3

# --- ФАЙРВОЛ И BBR ---
echo -e "${YELLOW}Настройка файрвола и BBR...${NC}"
SSH_PORT=$(ss -tlnp | grep sshd | awk '{print $4}' | awk -F':' '{print $NF}' | head -n 1)
SSH_PORT=${SSH_PORT:-22}
ufw allow "$SSH_PORT"/tcp; ufw allow 80/tcp; ufw allow 443/tcp; ufw allow 443/udp; ufw allow 59215/tcp; ufw allow 59215/udp; ufw allow 65102/tcp; ufw --force enable

cat > /etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl --system >/dev/null 2>&1

# --- ХАНИПОТ И СЕРТИФИКАТЫ ---
mkdir -p /var/www/decoy /var/www/certbot
cat > /var/www/decoy/index.html <<'HTMLEOF'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Nexus AI Node</title><style>body{background-color:#0f172a;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;color:#fff}.login-box{background-color:#1e293b;padding:40px;border-radius:12px;box-shadow:0 10px 25px rgba(0,0,0,0.5);width:340px;text-align:center;box-sizing:border-box}.logo{font-size:24px;font-weight:700;color:#0ea5e9;margin-bottom:8px}.subtitle{color:#94a3b8;font-size:13px;margin-bottom:30px}input{width:100%;padding:12px 16px;margin-bottom:16px;background-color:#0f172a;border:1px solid #334155;border-radius:6px;color:#fff;font-size:14px;box-sizing:border-box;transition:border-color 0.2s}input:focus{outline:none;border-color:#0ea5e9}button{width:100%;padding:14px;background-color:#0ea5e9;color:#fff;border:none;border-radius:6px;font-size:15px;font-weight:600;cursor:pointer;margin-top:8px}button:hover{background-color:#0284c7}.footer{margin-top:24px;font-size:12px;color:#475569}</style></head><body><div class="login-box"><div class="logo">Nexus AI Node</div><div class="subtitle">Restricted Access Area</div><form id="loginForm"><input type="text" placeholder="Email / Node ID" required><input type="password" placeholder="Access Key" required><button type="submit" id="submitBtn">Initialize Connection</button></form><div class="footer">v 2.4.1 | End-to-End Encrypted</div></div><script>document.getElementById('loginForm').addEventListener('submit',function(e){e.preventDefault();const btn=document.getElementById('submitBtn');const inputs=document.querySelectorAll('input');btn.innerText='Connecting...';btn.style.backgroundColor='#475569';btn.disabled=true;inputs.forEach(i=>i.disabled=true);setTimeout(()=>{btn.innerText='Access Denied';btn.style.backgroundColor='#ef4444';setTimeout(()=>{btn.innerText='Initialize Connection';btn.style.backgroundColor='#0ea5e9';btn.disabled=false;inputs.forEach(i=>{i.disabled=false;i.value='';});},2000);},1500);});</script></body></html>
HTMLEOF

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
    certbot certonly --webroot -w /var/www/certbot -d "$DOMAIN" --non-interactive --agree-tos -m $EMAIL || true
fi

# --- АВТО-ОБНОВЛЕНИЕ СЕРТИФИКАТОВ ---
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
echo -e '#!/bin/bash\nsystemctl reload nginx' > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh

# --- УСТАНОВКА 3X-UI ---
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
export USE_OLD_JSON="$USE_OLD_JSON"

# --- ВНЕДРЕНИЕ В БАЗУ ---
echo -e "${YELLOW}Генерация и внедрение конфигурации...${NC}"
python3 << 'PYEOF'
import os, sqlite3, json, secrets, uuid, subprocess

db = '/etc/x-ui/x-ui.db'
conn = sqlite3.connect(db)
c = conn.cursor()

# 1. Настройки панели
settings = [
    ('webPort', os.environ['DB_PANEL_PORT']), ('webBasePath', os.environ['DB_WEB_PATH']),
    ('webListen', '127.0.0.1'), ('subPort', os.environ['DB_SUB_PORT']),
    ('subPath', os.environ['DB_SUB_PATH']), ('subListen', '127.0.0.1'),
    ('subEnable', 'true'), ('subDomain', os.environ['DB_DOMAIN']),
    ('subURI', f"https://{os.environ['DB_DOMAIN']}{os.environ['DB_SUB_PATH']}")
]
c.execute("DELETE FROM settings WHERE key IN ('webPort', 'webBasePath', 'webListen', 'subPort', 'subPath', 'subListen', 'subEnable', 'subDomain', 'subURI')")
c.executemany("INSERT INTO settings (key, value) VALUES (?, ?)", settings)

# 2. Парсим старые ключи
old_keys = {}
if os.environ['USE_OLD_JSON'] == 'true':
    try:
        with open('/tmp/old_config.json', 'r') as f:
            old_config = json.load(f)
            for inb in old_config.get("inbounds", []):
                for client in inb.get("settings", {}).get("clients", []):
                    email = client.get("email", "").split('@')[0]
                    key = client.get("id") or client.get("auth") or client.get("pass")
                    if email and key:
                        old_keys[email] = key
        print(f"\033[0;33mНайдено старых ключей: {len(old_keys)}\033[0m")
    except Exception as e:
        print(f"\033[0;31mОшибка чтения JSON: {e}. Будут созданы новые ключи.\033[0m")

# 3. Генерация инбаундов
protocols = os.environ['PROTOCOLS'].split()
clients = ["zfold", "passwall", "work", "TV", "note10"]

xray_bin = subprocess.check_output("find /usr/local/x-ui/bin/ -name 'xray*' -type f | head -n 1", shell=True).decode().strip()
keys = subprocess.check_output(f"{xray_bin} x25519", shell=True).decode()
priv_key = [line.split()[-1] for line in keys.split('\n') if 'Private' in line][0]
pub_key = [line.split()[-1] for line in keys.split('\n') if 'Password' in line or 'Public' in line][0]
short_id = secrets.token_hex(4)

def get_key(name, protocol):
    if name in old_keys:
        return old_keys[name]
    if protocol in ["vless", "vmess"]:
        return str(uuid.uuid4())
    else:
        return secrets.token_hex(8)

# 1. VLESS Reality
if "1" in protocols:
    vless_clients = []
    for name in clients:
        c_key = get_key(name, "vless")
        c_sub_id = secrets.token_hex(8)
        vless_clients.append({"id": c_key, "flow": "", "email": f"{name}@{os.environ['DB_DOMAIN']}", "limitIp": 0, "totalGB": 0, "expiryTime": 0, "enable": True, "tgId": 0, "subId": c_sub_id, "reset": 0})
        # Заполняем uuid, password и auth для совместимости
        c.execute("INSERT INTO clients (email, sub_id, uuid, password, auth, enable) VALUES (?, ?, ?, ?, ?, 1)", (f"{name}@{os.environ['DB_DOMAIN']}", c_sub_id, c_key, c_key, c_key))
    
    settings_json = json.dumps({"clients": vless_clients, "decryption": "none"})
    stream_json = json.dumps({
        "network": "xhttp", "security": "reality",
        "xhttpSettings": {"path": "/api/v3/stream", "mode": "stream-one", "xPaddingBytes": "100-1000"},
        "realitySettings": {"show": False, "target": "127.0.0.1:40000", "xver": 0, "serverNames": [os.environ['DB_DOMAIN']], "privateKey": priv_key, "shortIds": [short_id], "settings": {"publicKey": pub_key, "fingerprint": "chrome", "spiderX": "/"}},
        "sockopt": {"tcpFastOpen": True, "tcpcongestion": "bbr"}
    })
    c.execute("INSERT INTO inbounds (user_id, port, protocol, settings, stream_settings, tag, sniffing, enable) VALUES (1, 443, 'vless', ?, ?, 'inbound-443', '{\"enabled\":true,\"destOverride\":[\"http\",\"tls\"]}', 1)", (settings_json, stream_json))
    inbound_id = c.lastrowid
    for name in clients: c.execute("INSERT INTO client_inbounds (client_id, inbound_id) SELECT id, ? FROM clients WHERE email = ?", (inbound_id, f"{name}@{os.environ['DB_DOMAIN']}"))

# 2. Hysteria 2
if "2" in protocols:
    hy_clients = []
    for name in clients:
        c_key = get_key(name, "hysteria")
        hy_clients.append({"auth": c_key, "email": name})
        c.execute("INSERT INTO clients (email, sub_id, uuid, password, auth, enable) VALUES (?, ?, ?, ?, ?, 1)", (name, secrets.token_hex(8), c_key, c_key, c_key))
    settings_json = json.dumps({"clients": hy_clients, "version": 2})
    stream_json = json.dumps({
        "network": "hysteria", "security": "tls",
        "finalmask": {"quicParams": {"bbrProfile": "aggressive", "congestion": "bbr", "initConnectionReceiveWindow": 33554432, "initStreamReceiveWindow": 16777216, "maxConnectionReceiveWindow": 33554432, "maxIncomingStreams": 2048, "maxStreamReceiveWindow": 16777216}},
        "hysteriaSettings": {"version": 2, "masquerade": {"type": "proxy", "url": f"https://{os.environ['DB_DOMAIN']}/", "rewriteHost": True}},
        "tlsSettings": {"alpn": ["h3"], "certificates": [{"certificateFile": os.environ['DB_CERT_PATH'], "keyFile": os.environ['DB_KEY_PATH']}], "serverName": os.environ['DB_DOMAIN'], "minVersion": "1.3", "maxVersion": "1.3"}
    })
    c.execute("INSERT INTO inbounds (user_id, port, protocol, settings, stream_settings, tag, sniffing, enable) VALUES (1, 443, 'hysteria', ?, ?, 'inbound-443-udp', '{\"enabled\":true,\"destOverride\":[\"http\",\"tls\"]}', 1)", (settings_json, stream_json))
    inbound_id = c.lastrowid
    for name in clients: c.execute("INSERT INTO client_inbounds (client_id, inbound_id) SELECT id, ? FROM clients WHERE email = ?", (inbound_id, name))

# 3. Masque
if "3" in protocols:
    masque_clients = []
    for name in clients:
        c_key = get_key(name, "masque")
        masque_clients.append({"email": name, "pass": c_key})
        c.execute("INSERT INTO clients (email, sub_id, uuid, password, auth, enable) VALUES (?, ?, ?, ?, ?, 1)", (name, secrets.token_hex(8), c_key, c_key, c_key))
    settings_json = json.dumps({"clients": masque_clients, "address": ["10.14.0.1/24", "fd14::1/64"]})
    stream_json = json.dumps({
        "network": "masque", "security": "tls",
        "masqueSettings": {"path": "/.well-known/masque/ip/*/*/"},
        "tlsSettings": {"alpn": ["h3", "h2"], "certificates": [{"certificateFile": os.environ['DB_CERT_PATH'], "keyFile": os.environ['DB_KEY_PATH']}], "serverName": os.environ['DB_DOMAIN'], "minVersion": "1.3", "maxVersion": "1.3"}
    })
    c.execute("INSERT INTO inbounds (user_id, port, protocol, settings, stream_settings, tag, sniffing, enable) VALUES (1, 59215, 'masque', ?, ?, 'inbound-59215-udp', '{\"enabled\":true,\"destOverride\":[\"http\",\"tls\"]}', 1)", (settings_json, stream_json))
    inbound_id = c.lastrowid
    for name in clients: c.execute("INSERT INTO client_inbounds (client_id, inbound_id) SELECT id, ? FROM clients WHERE email = ?", (inbound_id, name))

# 4. SOCKS5
if "4" in protocols:
    socks_clients = [{"user": "masha", "pass": "wlopfmAb531Mhptwb_oNgYOXpizblX5O"}, {"user": "sofa", "pass": "wlopfmAb531Mhptwb_oNgYOXpizblX5O"}]
    for cl in socks_clients:
        c.execute("INSERT INTO clients (email, sub_id, uuid, password, auth, enable) VALUES (?, ?, ?, ?, ?, 1)", (cl["user"], secrets.token_hex(8), cl["pass"], cl["pass"], cl["pass"]))
    settings_json = json.dumps({"auth": "password", "accounts": socks_clients, "udp": True})
    c.execute("INSERT INTO inbounds (user_id, port, protocol, settings, stream_settings, tag, sniffing, enable) VALUES (1, 65102, 'socks', ?, '{}', 'in-22644-udp', '{\"enabled\":true,\"destOverride\":[\"http\",\"tls\",\"quic\",\"fakedns\"],\"routeOnly\":true}', 1)", (settings_json,))
    inbound_id = c.lastrowid
    for cl in socks_clients: c.execute("INSERT INTO client_inbounds (client_id, inbound_id) SELECT id, ? FROM clients WHERE email = ?", (inbound_id, cl["user"]))

# Чистый шаблон Xray
template = {
    "log": {"loglevel": "warning"},
    "outbounds": [{"protocol": "freedom", "tag": "direct"}, {"protocol": "blackhole", "tag": "blocked"}],
    "routing": {"domainStrategy": "AsIs", "rules": [{"type": "field", "ip": ["geoip:private"], "outboundTag": "blocked"}]}
}
c.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('xrayTemplateConfig', ?)", (json.dumps(template),))
print("\033[0;32mНастройки сгенерированы!\033[0m")

conn.commit()
conn.close()
PYEOF

# --- НАСТРОЙКА NGINX ---
echo -e "${YELLOW}Настройка Nginx...${NC}"
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
sleep 5 
x-ui setting -username "$PANEL_USER" -password "$PANEL_PASS" >/dev/null 2>&1
systemctl restart x-ui
sleep 3

echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}        ВСЁ ГОТОВО! СИСТЕМА ЗАПУЩЕНА.               ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "Логин: ${YELLOW}$PANEL_USER${NC} | Пароль: ${YELLOW}$PANEL_PASS${NC}"
echo -e "ССЫЛКА НА ПАНЕЛЬ: ${YELLOW}https://$DOMAIN$WEB_PATH${NC}"
echo -e "ССЫЛКА НА ПОДПИСКИ: ${YELLOW}https://$DOMAIN$SUB_PATH${NC}"
echo -e "${GREEN}====================================================${NC}"
