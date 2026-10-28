#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== ИДЕАЛЬНАЯ УСТАНОВКА (ОБХОД БАГА БАЗЫ) ===${NC}"

read -p "Домен (напр. llm.atms2006.ru): " DOMAIN
read -p "Email (Enter - пропустить): " EMAIL
read -p "Логин панели: " PANEL_USER
read -s -p "Пароль панели: " PANEL_PASS
echo ""
read -p "Путь ПАНЕЛИ (напр. /panel/): " WEB_PATH
read -p "Порт ПАНЕЛИ (напр. 45000): " PANEL_PORT
read -p "Путь ПОДПИСОК (напр. /sub/): " SUB_PATH
read -p "Порт ПОДПИСОК (напр. 55000): " SUB_PORT

[[ "$WEB_PATH" != /* ]] && WEB_PATH="/$WEB_PATH"
[[ "$WEB_PATH" != */ ]] && WEB_PATH="$WEB_PATH/"
[[ "$SUB_PATH" != /* ]] && SUB_PATH="/$SUB_PATH"
[[ "$SUB_PATH" != */ ]] && SUB_PATH="$SUB_PATH/"

systemctl stop x-ui nginx >/dev/null 2>&1 || true
apt purge -y nginx nginx-common nginx-core >/dev/null 2>&1 || true
rm -rf /etc/x-ui /usr/local/x-ui /usr/bin/x-ui /etc/systemd/system/x-ui.service /etc/nginx /var/www/decoy /var/www/certbot

export DEBIAN_FRONTEND=noninteractive
apt update && apt install -y nginx certbot curl wget sqlite3 ufw openssl python3
ufw allow 22/tcp; ufw allow 80/tcp; ufw allow 443/tcp; ufw --force enable

mkdir -p /var/www/decoy /var/www/certbot
cat > /var/www/decoy/index.html <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8"><title>Database Admin</title>
<style>body{background:#f0f2f5;font-family:sans-serif;display:flex;justify-content:center;align-items:center;height:100vh;margin:0}.box{background:#fff;padding:40px;border-radius:8px;box-shadow:0 4px 12px rgba(0,0,0,.15);width:300px;text-align:center}input{width:100%;padding:10px;margin:10px 0;border:1px solid #ccc;border-radius:4px;box-sizing:border-box}button{width:100%;padding:10px;background:#007bff;color:#fff;border:none;border-radius:4px;cursor:pointer}.err{color:red;font-size:12px;display:none;margin-top:10px}</style></head>
<body><div class="box"><h3>Secure Database</h3>
<form onsubmit="event.preventDefault();document.getElementById('e').style.display='block'">
<input type="text" placeholder="Username" required><input type="password" placeholder="Password" required>
<button type="submit">Sign In</button></form><div id="e" class="err">Access Denied: Invalid credentials.</div></div></body></html>
HTMLEOF

CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

if [ ! -f "$CERT_PATH" ]; then
    printf '%s\n' 'server {' '    listen 80;' "    server_name $DOMAIN;" '    location /.well-known/acme-challenge/ { root /var/www/certbot; }' '    location / { root /var/www/decoy; index index.html; }' '}' > /etc/nginx/sites-available/decoy
    ln -sf /etc/nginx/sites-available/decoy /etc/nginx/sites-enabled/decoy
    systemctl restart nginx
    EMAIL_ARG="--register-unsafely-without-email"
    [ -n "$EMAIL" ] && EMAIL_ARG="-m $EMAIL"
    certbot certonly --webroot -w /var/www/certbot -d "$DOMAIN" --non-interactive --agree-tos $EMAIL_ARG || true
fi

wget -qO /tmp/xui-install.sh https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh
printf "1\nn\n4\ny\n" | bash /tmp/xui-install.sh
sleep 7
systemctl stop x-ui
rm -f /etc/x-ui/x-ui.db
systemctl start x-ui
sleep 3
systemctl stop x-ui

XRAY_BIN=$(find /usr/local/x-ui/bin/ -name "xray*" -type f | head -n 1)
UUID=$(cat /proc/sys/kernel/random/uuid)
SUB_ID=$(head /dev/urandom | tr -dc a-f0-9 | head -c 16)
KEYS=$($XRAY_BIN x25519)
PRIV_KEY=$(echo "$KEYS" | grep -i "Private" | awk '{print $NF}')
PUB_KEY=$(echo "$KEYS" | grep -i "Password" | awk '{print $NF}')
SHORT_ID=$(head /dev/urandom | tr -dc a-f0-9 | head -c 8)
SPIDER_X="/$(head /dev/urandom | tr -dc a-zA-Z0-9 | head -c 12)"

export DB_DOMAIN="$DOMAIN"
export DB_PANEL_PORT="$PANEL_PORT"
export DB_WEB_PATH="$WEB_PATH"
export DB_SUB_PORT="$SUB_PORT"
export DB_SUB_PATH="$SUB_PATH"
export DB_UUID="$UUID"
export DB_SUB_ID="$SUB_ID"
export DB_PRIV_KEY="$PRIV_KEY"
export DB_PUB_KEY="$PUB_KEY"
export DB_SHORT_ID="$SHORT_ID"
export DB_SPIDER_X="$SPIDER_X"

echo -e "${YELLOW}Запись в базу (Fallback внутри JSON)...${NC}"
python3 << 'PYEOF'
import os, sqlite3, json

db = '/etc/x-ui/x-ui.db'
conn = sqlite3.connect(db)
c = conn.cursor()

settings = [
    ('webPort', os.environ['DB_PANEL_PORT']),
    ('webBasePath', os.environ['DB_WEB_PATH']),
    ('webListen', '127.0.0.1'),
    ('subPort', os.environ['DB_SUB_PORT']),
    ('subPath', os.environ['DB_SUB_PATH']),
    ('subListen', '127.0.0.1'),
    ('subEnable', 'true'),
    ('subDomain', os.environ['DB_DOMAIN']),
    ('subURI', f"https://{os.environ['DB_DOMAIN']}{os.environ['DB_SUB_PATH']}")
]
c.execute("DELETE FROM settings WHERE key IN ('webPort', 'webBasePath', 'webListen', 'subPort', 'subPath', 'subListen', 'subEnable', 'subDomain', 'subURI')")
c.executemany("INSERT INTO settings (key, value) VALUES (?, ?)", settings)

# ВОТ ГЛАВНЫЙ ФИКС: Fallback внутри JSON, игнорируем таблицу inbound_fallbacks
settings_json = json.dumps({
    "clients": [], 
    "decryption": "none",
    "fallbacks": [{"dest": 40000, "xver": 0}]
})

stream_json = json.dumps({
    "network": "xhttp",
    "security": "reality",
    "xhttpSettings": {"path": "/api/v3/stream", "mode": "stream-one"},
    "realitySettings": {
        "show": False, "target": "127.0.0.1:40000", "xver": 0,
        "serverNames": [os.environ['DB_DOMAIN']],
        "privateKey": os.environ['DB_PRIV_KEY'],
        "shortIds": [os.environ['DB_SHORT_ID']],
        "settings": {"publicKey": os.environ['DB_PUB_KEY'], "fingerprint": "chrome", "spiderX": os.environ['DB_SPIDER_X']}
    },
    "sockopt": {"tcpFastOpen": True, "tcpcongestion": "bbr"}
})
sniffing_json = json.dumps({"enabled": True, "destOverride": ["http", "tls"]})

c.execute("INSERT INTO inbounds (user_id, port, protocol, settings, stream_settings, tag, sniffing, enable) VALUES (1, 443, 'vless', ?, ?, 'inbound-443', ?, 1)", 
          (settings_json, stream_json, sniffing_json))
inbound_id = c.lastrowid

c.execute("INSERT INTO clients (email, sub_id, uuid, enable) VALUES (?, ?, ?, 1)", 
          (f"default@{os.environ['DB_DOMAIN']}", os.environ['DB_SUB_ID'], os.environ['DB_UUID']))
client_id = c.lastrowid

c.execute("INSERT INTO client_inbounds (client_id, inbound_id) VALUES (?, ?)", (client_id, inbound_id))

conn.commit()
conn.close()
print("База данных заполнена (Fallback в JSON)!")
PYEOF

systemctl start x-ui
sleep 2
x-ui setting -username "$PANEL_USER" -password "$PANEL_PASS"
systemctl stop x-ui

echo -e "${YELLOW}Настройка Nginx...${NC}"
python3 -c "
config = '''
server {
    listen 80; server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$host\$request_uri; }
}
server {
    listen 127.0.0.1:40000 ssl http2;
    server_name $DOMAIN;
    ssl_certificate $CERT_PATH;
    ssl_certificate_key $KEY_PATH;
    set_real_ip_from 127.0.0.1; real_ip_header X-Forwarded-For;
    
    location / { root /var/www/decoy; index index.html; }
    location $WEB_PATH { proxy_pass http://127.0.0.1:$PANEL_PORT; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \"upgrade\"; proxy_set_header Host \$host; }
    location $SUB_PATH { proxy_pass http://127.0.0.1:$SUB_PORT; proxy_set_header Host \$host; }
}
'''
with open('/etc/nginx/sites-available/decoy', 'w') as f:
    f.write(config)
"

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/decoy /etc/nginx/sites-enabled/decoy
nginx -t && systemctl restart nginx
systemctl start x-ui

echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}        ВСЁ ГОТОВО! БАЗА ЗАПОЛНЕНА ИДЕАЛЬНО.        ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "Логин: $PANEL_USER | Пароль: $PANEL_PASS"
echo -e "ПАНЕЛЬ:   ${YELLOW}https://$DOMAIN$WEB_PATH${NC}"
echo -e "ПОДПИСКИ: ${YELLOW}https://$DOMAIN$SUB_PATH${NC}"
echo -e ""
echo -e "${RED}ДАННЫЕ ДЛЯ КЛИЕНТА (VLESS):${NC}"
echo -e "  Адрес: $DOMAIN | Порт: 443 | UUID: $UUID"
echo -e "  Public Key: $PUB_KEY | Short ID: $SHORT_ID"
echo -e "  SNI: $DOMAIN | Транспорт: XHTTP (stream-one)"
echo -e "${GREEN}====================================================${NC}"
