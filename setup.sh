#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

clear
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}     АБСОЛЮТНО ИДЕАЛЬНЫЙ СКРИПТ (VLESS + HYSTERIA)  ${NC}"
echo -e "${GREEN}====================================================${NC}"

read -p "Введите домен (напр. pan.agema2026.ru): " RAW_DOMAIN
DOMAIN=$(echo "$RAW_DOMAIN" | tr -cd 'a-zA-Z0-9.-')

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Ошибка: домен пустой или содержит недопустимые символы!${NC}"
    exit 1
fi

echo -e "\n${YELLOW}Выберите протоколы (1 - VLESS, 2 - Hysteria, или '1 2'):${NC}"
read -p "Ваш выбор: " PROTOCOLS

PANEL_USER="admin"
PANEL_PASS="admin"
WEB_PATH="/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)/"
SUB_PATH="/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)/"
PANEL_PORT=$(( ( RANDOM % 50000 ) + 10000 ))
SUB_PORT=$(( ( RANDOM % 50000 ) + 10000 ))
NGINX_PORT="40000"

echo -e "\n${YELLOW}Очистка старых установок...${NC}"
systemctl stop x-ui nginx >/dev/null 2>&1 || true
apt purge -y nginx nginx-common nginx-core >/dev/null 2>&1 || true
rm -rf /etc/x-ui /usr/local/x-ui /usr/bin/x-ui /etc/systemd/system/x-ui.service /etc/nginx /var/www/decoy /var/www/certbot

export DEBIAN_FRONTEND=noninteractive
apt update && apt install -y nginx certbot curl wget sqlite3 ufw openssl python3

# Установка 3x-ui
echo -e "${YELLOW}Установка 3x-ui...${NC}"
wget -qO /tmp/xui-install.sh https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh
printf "1\nn\n4\ny\n" | bash /tmp/xui-install.sh
sleep 7

# Ханипот
mkdir -p /var/www/decoy /var/www/certbot
echo '<h1>Welcome</h1>' > /var/www/decoy/index.html

CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

echo -e "${YELLOW}Получение SSL сертификата...${NC}"
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

# ЕСЛИ CERTBOT УПАЛ, ДЕЛАЕМ САМОПОДПИСАННЫЙ
if [ ! -f "$CERT_PATH" ]; then
    echo -e "${RED}Certbot не смог получить сертификат. Создаю самоподписанный...${NC}"
    mkdir -p /etc/ssl/self-signed
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/self-signed/privkey.pem -out /etc/ssl/self-signed/fullchain.pem -subj "/CN=$DOMAIN"
    CERT_PATH="/etc/ssl/self-signed/fullchain.pem"
    KEY_PATH="/etc/ssl/self-signed/privkey.pem"
fi

# ПЕРЕСОЗДАЕМ БАЗУ
systemctl stop x-ui
rm -f /etc/x-ui/x-ui.db
systemctl start x-ui
sleep 5
systemctl stop x-ui

export DB_DOMAIN="$DOMAIN"
export DB_PANEL_PORT="$PANEL_PORT"
export DB_WEB_PATH="$WEB_PATH"
export DB_SUB_PORT="$SUB_PORT"
export DB_SUB_PATH="$SUB_PATH"
export DB_CERT_PATH="$CERT_PATH"
export DB_KEY_PATH="$KEY_PATH"
export DB_PROTOCOLS="$PROTOCOLS"

echo -e "${YELLOW}Заполнение базы...${NC}"
python3 << 'PYEOF'
import os, sqlite3, json, secrets, uuid, subprocess

DOMAIN = os.environ['DB_DOMAIN']
PANEL_PORT = os.environ['DB_PANEL_PORT']
WEB_PATH = os.environ['DB_WEB_PATH']
SUB_PORT = os.environ['DB_SUB_PORT']
SUB_PATH = os.environ['DB_SUB_PATH']
CERT_PATH = os.environ['DB_CERT_PATH']
KEY_PATH = os.environ['DB_KEY_PATH']
PROTOCOLS = os.environ['DB_PROTOCOLS'].split()

db = '/etc/x-ui/x-ui.db'
conn = sqlite3.connect(db)
c = conn.cursor()

# Обновляем настройки (не удаляем, а обновляем)
c.execute("UPDATE settings SET value = ? WHERE key = 'webPort'", (PANEL_PORT,))
c.execute("UPDATE settings SET value = ? WHERE key = 'webBasePath'", (WEB_PATH,))
c.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('webListen', '127.0.0.1')")
c.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('subPort', ?)", (SUB_PORT,))
c.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('subPath', ?)", (SUB_PATH,))
c.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('subListen', '127.0.0.1')")
c.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('subEnable', 'true')")
c.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('subDomain', ?)", (DOMAIN,))
c.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('subURI', ?)", (f"https://{DOMAIN}{SUB_PATH}",))

# Очищаем только целевые таблицы
c.execute("DELETE FROM clients")
c.execute("DELETE FROM client_inbounds")
c.execute("DELETE FROM client_traffics")
c.execute("DELETE FROM inbounds")

client_names = ["zfold", "passwall", "work", "TV", "note10"]
client_data = []

# Генерируем ключи Reality
xray_bin = subprocess.check_output("find /usr/local/x-ui/bin/ -name 'xray*' -type f | head -n 1", shell=True).decode().strip()
keys = subprocess.check_output(f"{xray_bin} x25519", shell=True).decode()
priv_key = [line.split()[-1] for line in keys.split('\n') if 'Private' in line][0]
pub_key = [line.split()[-1] for line in keys.split('\n') if 'Password' in line or 'Public' in line][0]

# 1. Создаем базовых клиентов в таблице clients
for name in client_names:
    c_uuid = str(uuid.uuid4())
    c_sub = secrets.token_hex(8)
    client_data.append({"name": name, "uuid": c_uuid, "sub_id": c_sub})
    
    c.execute("INSERT INTO clients (email, sub_id, uuid, password, auth, enable) VALUES (?, ?, ?, ?, ?, 1)", 
              (name, c_sub, c_uuid, c_uuid, c_uuid))
    client_data[-1]["db_id"] = c.lastrowid

# --- VLESS ---
if "1" in PROTOCOLS:
    short_ids = [secrets.token_hex(n)[:n] for n in [6, 2, 4, 8, 16]]
    spider_x = f"/{secrets.token_urlsafe(10)[:15]}"
    vless_clients = [{"id": cd["uuid"], "email": cd["name"], "subId": cd["sub_id"], "flow": "", "limitIp": 0, "totalGB": 0, "expiryTime": 0, "enable": True, "tgId": 0, "reset": 0} for cd in client_data]
        
    settings_json = json.dumps({"clients": vless_clients, "decryption": "none", "encryption": "none"})
    stream_json = json.dumps({
        "network": "xhttp", "security": "reality",
        "xhttpSettings": {"path": "/api/v3/stream", "mode": "stream-one"},
        "realitySettings": {"show": False, "xver": 0, "target": "127.0.0.1:40000", "serverNames": [DOMAIN], "privateKey": priv_key, "shortIds": short_ids, "settings": {"publicKey": pub_key, "fingerprint": "firefox", "spiderX": spider_x}},
        "sockopt": {"tcpFastOpen": True, "tcpcongestion": "bbr"}
    })
    c.execute("INSERT INTO inbounds (user_id, port, protocol, settings, stream_settings, tag, sniffing, enable) VALUES (1, 443, 'vless', ?, ?, 'in-443-tcp', '{\"enabled\":true,\"destOverride\":[\"http\",\"tls\",\"quic\",\"fakedns\"]}', 1)", (settings_json, stream_json))
    inbound_id = c.lastrowid
    
    for cd in client_data:
        c.execute("INSERT INTO client_inbounds (client_id, inbound_id) VALUES (?, ?)", (cd["db_id"], inbound_id))
        c.execute("INSERT INTO client_traffics (inbound_id, enable, email, up, down, expiry_time, total, reset, last_online) VALUES (?, 1, ?, 0, 0, 0, 0, 0, 0)", (inbound_id, cd["name"]))

# --- Hysteria ---
if "2" in PROTOCOLS:
    hy_clients = [{"id": cd["uuid"], "auth": cd["uuid"], "email": cd["name"]} for cd in client_data]
    settings_json = json.dumps({"clients": hy_clients, "version": 2})
    stream_json = json.dumps({
        "network": "hysteria", "hysteriaSettings": {"version": 2, "udpIdleTimeout": 60, "masquerade": {"type": "proxy", "dir": "", "url": f"https://{DOMAIN}/", "rewriteHost": True}},
        "security": "tls", "tlsSettings": {"serverName": DOMAIN, "minVersion": "1.3", "maxVersion": "1.3", "certificates": [{"certificateFile": CERT_PATH, "keyFile": KEY_PATH}], "alpn": ["h3"], "settings": {"fingerprint": "firefox"}},
        "finalmask": {"quicParams": {"congestion": "bbr", "bbrProfile": "aggressive"}}
    })
    c.execute("INSERT INTO inbounds (user_id, port, protocol, settings, stream_settings, tag, sniffing, enable) VALUES (1, 443, 'hysteria', ?, ?, 'in-443-udp', '{\"enabled\":true,\"destOverride\":[\"http\",\"tls\"]}', 1)", (settings_json, stream_json))
    inbound_id_hy = c.lastrowid
    
    for cd in client_data:
        c.execute("INSERT INTO client_inbounds (client_id, inbound_id) VALUES (?, ?)", (cd["db_id"], inbound_id_hy))
        c.execute("INSERT INTO client_traffics (inbound_id, enable, email, up, down, expiry_time, total, reset, last_online) VALUES (?, 1, ?, 0, 0, 0, 0, 0, 0)", (inbound_id_hy, cd["name"]))

# --- ИДЕАЛЬНЫЙ ШАБЛОН XRAY ---
template = {
    "log": {"loglevel": "warning"},
    "api": {"services": ["HandlerService", "LoggerService", "StatsService", "RoutingService"], "tag": "api"},
    "stats": {},
    "policy": {
        "levels": {"0": {"statsUserUplink": True, "statsUserDownlink": True, "statsUserOnline": True}},
        "system": {"statsInboundUplink": True, "statsInboundDownlink": True, "statsOutboundUplink": True, "statsOutboundDownlink": True}
    },
    "inbounds": [
        {"listen": "127.0.0.1", "port": 62789, "protocol": "dokodemo-door", "settings": {"address": "127.0.0.1"}, "tag": "api", "sniffing": {"enabled": False}}
    ],
    "outbounds": [
        {"protocol": "freedom", "tag": "direct"},
        {"protocol": "blackhole", "tag": "blocked"}
    ],
    "routing": {
        "domainStrategy": "AsIs",
        "rules": [
            {"type": "field", "inboundTag": ["api"], "outboundTag": "api"},
            {"type": "field", "ip": ["geoip:private"], "outboundTag": "blocked"}
        ]
    }
}
c.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('xrayTemplateConfig', ?)", (json.dumps(template),))

conn.commit()
conn.close()
print("\033[0;32mБаза данных сгенерирована идеально!\033[0m")
PYEOF

# Настройка Nginx (Fallback)
LISTEN_NGINX="listen 127.0.0.1:${NGINX_PORT} ssl http2;"
FALLBACK_CONFIG="server {
    listen 80; server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$host\$request_uri; }
}"

cat > /etc/nginx/sites-available/decoy <<NGINXEOF
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
NGINXEOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/decoy /etc/nginx/sites-enabled/decoy
nginx -t && systemctl restart nginx

systemctl start x-ui
sleep 3
x-ui setting -username "$PANEL_USER" -password "$PANEL_PASS" >/dev/null 2>&1
systemctl restart x-ui
sleep 2

# Отключение UFW
ufw disable

echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}        ВСЁ ГОТОВО! СИСТЕМА ЗАПУЩЕНА.               ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "Логин: ${YELLOW}$PANEL_USER${NC} | Пароль: ${YELLOW}$PANEL_PASS${NC}"
echo -e "ССЫЛКА НА ПАНЕЛЬ: ${YELLOW}https://$DOMAIN$WEB_PATH${NC}"
echo -e "ССЫЛКА НА ПОДПИСКИ: ${YELLOW}https://$DOMAIN$SUB_PATH${NC}"
echo -e "${GREEN}====================================================${NC}"