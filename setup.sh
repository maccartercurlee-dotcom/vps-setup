#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

clear
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}           ИДЕАЛЬНЫЙ УСТАНОВЩИК (БЕЗ ОШИБОК)        ${NC}"
echo -e "${GREEN}====================================================${NC}"

# 1. Ввод домена с жесткой очисткой от мусора
read -p "Введите домен (напр. llm.atms2006.ru): " RAW_DOMAIN
DOMAIN=$(echo "$RAW_DOMAIN" | tr -cd 'a-zA-Z0-9.-') # Оставляем только латиницу, цифры, точки и дефисы

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Ошибка: домен пустой!${NC}"
    exit 1
fi
echo -e "Используем домен: ${YELLOW}$DOMAIN${NC}"

# 2. Выбор протоколов
echo -e "\n${YELLOW}Выберите протоколы (введите номера через пробел, напр. '1 2'):${NC}"
echo "1) VLESS Reality + XHTTP (TCP 443)"
echo "2) Hysteria 2 (UDP 443)"
echo "3) Masque (UDP 59215)"
echo "4) SOCKS5 (TCP 65102)"
read -p "Ваш выбор: " PROTOCOLS

if [ -z "$PROTOCOLS" ]; then
    echo -e "${RED}Вы ничего не выбрали. Выход.${NC}"
    exit 1
fi

PANEL_USER="admin"
PANEL_PASS="admin"

# 3. Генерация путей и портов
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

# 4. Настройка системы
SSH_PORT=$(ss -tlnp | grep sshd | awk '{print $4}' | awk -F':' '{print $NF}' | head -n 1)
SSH_PORT=${SSH_PORT:-22}
ufw allow "$SSH_PORT"/tcp; ufw allow 80/tcp; ufw allow 443/tcp; ufw allow 443/udp; ufw allow 59215/tcp; ufw allow 59215/udp; ufw allow 65102/tcp; ufw --force enable

cat > /etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl --system >/dev/null 2>&1

# 5. Ханипот и Сертификаты
mkdir -p /var/www/decoy /var/www/certbot
echo "<h1>Nexus AI Node</h1>" > /var/www/decoy/index.html

CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

if [ ! -f "$CERT_PATH" ]; then
    echo -e "${YELLOW}Запрос SSL сертификата...${NC}"
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

# 6. Установка 3x-ui
echo -e "${YELLOW}Установка 3x-ui...${NC}"
wget -qO /tmp/xui-install.sh https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh
printf "1\nn\n4\ny\n" | bash /tmp/xui-install.sh
sleep 7
systemctl stop x-ui
rm -f /etc/x-ui/x-ui.db
systemctl start x-ui
sleep 3
systemctl stop x-ui

# 7. Внедрение в базу через Python (самый надежный способ)
export DB_DOMAIN="$DOMAIN"
export DB_PANEL_PORT="$PANEL_PORT"
export DB_WEB_PATH="$WEB_PATH"
export DB_SUB_PORT="$SUB_PORT"
export DB_SUB_PATH="$SUB_PATH"
export DB_CERT_PATH="$CERT_PATH"
export DB_KEY_PATH="$KEY_PATH"
export PROTOCOLS="$PROTOCOLS"

echo -e "${YELLOW}Запись конфигурации в базу...${NC}"
python3 << 'PYEOF'
import os, sqlite3, json, secrets, uuid, subprocess, sys

# Получаем переменные (они уже очищены от мусора в bash)
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

# ГЛАВНЫЙ ФИКС: Очищаем таблицы от старых данных, чтобы избежать UNIQUE constraint
c.execute("DELETE FROM clients")
c.execute("DELETE FROM client_inbounds")
c.execute("DELETE FROM inbounds")
c.execute("DELETE FROM settings WHERE key IN ('webPort', 'webBasePath', 'webListen', 'subPort', 'subPath', 'subListen', 'subEnable', 'subDomain', 'subURI')")

# Настройки панели
settings = [
    ('webPort', PANEL_PORT), ('webBasePath', WEB_PATH),
    ('webListen', '127.0.0.1'), ('subPort', SUB_PORT),
    ('subPath', SUB_PATH), ('subListen', '127.0.0.1'),
    ('subEnable', 'true'), ('subDomain', DOMAIN),
    ('subURI', f"https://{DOMAIN}{SUB_PATH}")
]
c.executemany("INSERT INTO settings (key, value) VALUES (?, ?)", settings)

clients = ["zfold", "passwall", "work", "TV", "note10"]

# Генерируем ключи Xray
xray_bin = subprocess.check_output("find /usr/local/x-ui/bin/ -name 'xray*' -type f | head -n 1", shell=True).decode().strip()
keys = subprocess.check_output(f"{xray_bin} x25519", shell=True).decode()
priv_key = [line.split()[-1] for line in keys.split('\n') if 'Private' in line][0]
pub_key = [line.split()[-1] for line in keys.split('\n') if 'Password' in line or 'Public' in line][0]
short_id = secrets.token_hex(4)

# 1. VLESS Reality + XHTTP
if "1" in PROTOCOLS:
    vless_clients = []
    for name in clients:
        c_uuid = str(uuid.uuid4())
        c_sub_id = secrets.token_hex(8)
        vless_clients.append({"id": c_uuid, "flow": "", "email": f"{name}@vless", "limitIp": 0, "totalGB": 0, "expiryTime": 0, "enable": True, "tgId": 0, "subId": c_sub_id, "reset": 0})
        # Записываем сразу в 3 поля, чтобы Xray не ругался
        c.execute("INSERT INTO clients (email, sub_id, uuid, password, auth, enable) VALUES (?, ?, ?, ?, ?, 1)", (f"{name}@vless", c_sub_id, c_uuid, c_uuid, c_uuid))
    
    settings_json = json.dumps({"clients": vless_clients, "decryption": "none"})
    stream_json = json.dumps({
        "network": "xhttp", "security": "reality",
        "xhttpSettings": {"path": "/api/v3/stream", "mode": "stream-one", "xPaddingBytes": "100-1000"},
        "realitySettings": {"show": False, "target": "127.0.0.1:40000", "xver": 0, "serverNames": [DOMAIN], "privateKey": priv_key, "shortIds": [short_id], "settings": {"publicKey": pub_key, "fingerprint": "chrome", "spiderX": "/"}},
        "sockopt": {"tcpFastOpen": True, "tcpcongestion": "bbr"}
    })
    c.execute("INSERT INTO inbounds (user_id, port, protocol, settings, stream_settings, tag, sniffing, enable) VALUES (1, 443, 'vless', ?, ?, 'inbound-443', '{\"enabled\":true,\"destOverride\":[\"http\",\"tls\"]}', 1)", (settings_json, stream_json))
    inbound_id = c.lastrowid
    for name in clients: c.execute("INSERT INTO client_inbounds (client_id, inbound_id) SELECT id, ? FROM clients WHERE email = ?", (inbound_id, f"{name}@vless"))

# 2. Hysteria 2
if "2" in PROTOCOLS:
    hy_clients = []
    for name in clients:
        c_key = secrets.token_hex(8)
        hy_clients.append({"auth": c_key, "email": f"{name}@hy2"})
        c.execute("INSERT INTO clients (email, sub_id, uuid, password, auth, enable) VALUES (?, ?, ?, ?, ?, 1)", (f"{name}@hy2", secrets.token_hex(8), c_key, c_key, c_key))
    
    settings_json = json.dumps({"clients": hy_clients, "version": 2})
    stream_json = json.dumps({
        "network": "hysteria", "security": "tls",
        "finalmask": {"quicParams": {"bbrProfile": "aggressive", "congestion": "bbr", "initConnectionReceiveWindow": 33554432, "initStreamReceiveWindow": 16777216, "maxConnectionReceiveWindow": 33554432, "maxIncomingStreams": 2048, "maxStreamReceiveWindow": 16777216}},
        "hysteriaSettings": {"version": 2, "masquerade": {"type": "proxy", "url": f"https://{DOMAIN}/", "rewriteHost": True}},
        "tlsSettings": {"alpn": ["h3"], "certificates": [{"certificateFile": CERT_PATH, "keyFile": KEY_PATH}], "serverName": DOMAIN, "minVersion": "1.3", "maxVersion": "1.3"}
    })
    c.execute("INSERT INTO inbounds (user_id, port, protocol, settings, stream_settings, tag, sniffing, enable) VALUES (1, 443, 'hysteria', ?, ?, 'inbound-443-udp', '{\"enabled\":true,\"destOverride\":[\"http\",\"tls\"]}', 1)", (settings_json, stream_json))
    inbound_id = c.lastrowid
    for name in clients: c.execute("INSERT INTO client_inbounds (client_id, inbound_id) SELECT id, ? FROM clients WHERE email = ?", (inbound_id, f"{name}@hy2"))

# 3. Masque
if "3" in PROTOCOLS:
    masque_clients = []
    for name in clients:
        c_key = secrets.token_hex(8)
        masque_clients.append({"email": f"{name}@masque", "pass": c_key})
        c.execute("INSERT INTO clients (email, sub_id, uuid, password, auth, enable) VALUES (?, ?, ?, ?, ?, 1)", (f"{name}@masque", secrets.token_hex(8), c_key, c_key, c_key))
    
    settings_json = json.dumps({"clients": masque_clients, "address": ["10.14.0.1/24", "fd14::1/64"]})
    stream_json = json.dumps({
        "network": "masque", "security": "tls",
        "masqueSettings": {"path": "/.well-known/masque/ip/*/*/"},
        "tlsSettings": {"alpn": ["h3", "h2"], "certificates": [{"certificateFile": CERT_PATH, "keyFile": KEY_PATH}], "serverName": DOMAIN, "minVersion": "1.3", "maxVersion": "1.3"}
    })
    c.execute("INSERT INTO inbounds (user_id, port, protocol, settings, stream_settings, tag, sniffing, enable) VALUES (1, 59215, 'masque', ?, ?, 'inbound-59215-udp', '{\"enabled\":true,\"destOverride\":[\"http\",\"tls\"]}', 1)", (settings_json, stream_json))
    inbound_id = c.lastrowid
    for name in clients: c.execute("INSERT INTO client_inbounds (client_id, inbound_id) SELECT id, ? FROM clients WHERE email = ?", (inbound_id, f"{name}@masque"))

# 4. SOCKS5
if "4" in PROTOCOLS:
    socks_clients = [{"user": "masha", "pass": "wlopfmAb531Mhptwb_oNgYOXpizblX5O"}, {"user": "sofa", "pass": "wlopfmAb531Mhptwb_oNgYOXpizblX5O"}]
    for cl in socks_clients:
        c.execute("INSERT INTO clients (email, sub_id, uuid, password, auth, enable) VALUES (?, ?, ?, ?, ?, 1)", (f"{cl['user']}@socks", secrets.token_hex(8), cl['pass'], cl['pass'], cl['pass']))
    
    settings_json = json.dumps({"auth": "password", "accounts": socks_clients, "udp": True})
    c.execute("INSERT INTO inbounds (user_id, port, protocol, settings, stream_settings, tag, sniffing, enable) VALUES (1, 65102, 'socks', ?, '{}', 'in-22644-udp', '{\"enabled\":true,\"destOverride\":[\"http\",\"tls\",\"quic\",\"fakedns\"],\"routeOnly\":true}', 1)", (settings_json,))
    inbound_id = c.lastrowid
    for cl in socks_clients: c.execute("INSERT INTO client_inbounds (client_id, inbound_id) SELECT id, ? FROM clients WHERE email = ?", (inbound_id, f"{cl['user']}@socks"))

# Чистый шаблон Xray
template = {
    "log": {"loglevel": "warning"},
    "outbounds": [{"protocol": "freedom", "tag": "direct"}, {"protocol": "blackhole", "tag": "blocked"}],
    "routing": {"domainStrategy": "AsIs", "rules": [{"type": "field", "ip": ["geoip:private"], "outboundTag": "blocked"}]}
}
c.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('xrayTemplateConfig', ?)", (json.dumps(template),))

conn.commit()
conn.close()
print("\033[0;32mБаза заполнена успешно!\033[0m")
PYEOF

# 8. Настройка Nginx
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

# 9. Запуск
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
