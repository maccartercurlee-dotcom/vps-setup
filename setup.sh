#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}=== УНИВЕРСАЛЬНАЯ УСТАНОВКА (ЛЮБОЙ JSON) ===${NC}"

read -p "Введите НОВЫЙ домен для этого сервера: " DOMAIN
read -p "Какой СТАРЫЙ домен в JSON нужно заменить? (Enter - не заменять): " OLD_DOMAIN

PANEL_USER="admin"
PANEL_PASS="admin"

WEB_PATH="/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)/"
SUB_PATH="/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)/"
PANEL_PORT=$(( ( RANDOM % 50000 ) + 10000 ))
SUB_PORT=$(( ( RANDOM % 50000 ) + 10000 ))
NGINX_PORT="40000"

echo -e "\n${YELLOW}Сейчас откроется редактор nano.${NC}"
echo -e "Вставьте ваш JSON-конфиг. Если оставите пустым — сделаю стандартную установку XHTTP."
echo -e "Сохраните: ${GREEN}Ctrl+O${NC}, ${GREEN}Enter${NC}, ${GREEN}Ctrl+X${NC}."
sleep 4
touch /tmp/server_config.json
nano /tmp/server_config.json

USE_CUSTOM="false"
if [ -s /tmp/server_config.json ] && grep -q '{' /tmp/server_config.json; then
    if python3 -c "import json; json.load(open('/tmp/server_config.json'))" 2>/dev/null; then
        USE_CUSTOM="true"
        echo -e "${GREEN}Валидный JSON найден!${NC}"
    else
        echo -e "${RED}ОШИБКА: Невалидный JSON.${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}Конфиг пуст. Стандартная установка XHTTP.${NC}"
fi

echo -e "${YELLOW}Очистка...${NC}"
systemctl stop x-ui nginx >/dev/null 2>&1 || true
apt purge -y nginx nginx-common nginx-core >/dev/null 2>&1 || true
rm -rf /etc/x-ui /usr/local/x-ui /usr/bin/x-ui /etc/systemd/system/x-ui.service /etc/nginx /var/www/decoy /var/www/certbot

export DEBIAN_FRONTEND=noninteractive
apt update && apt install -y nginx certbot curl wget sqlite3 ufw openssl python3

# Открываем популярные порты под разные протоколы
SSH_PORT=$(ss -tlnp | grep sshd | awk '{print $4}' | awk -F':' '{print $NF}' | head -n 1)
SSH_PORT=${SSH_PORT:-22}
ufw allow "$SSH_PORT"/tcp; ufw allow 80/tcp; ufw allow 443/tcp; ufw allow 443/udp; ufw allow 50600/tcp; ufw allow 50600/udp; ufw allow 59215/tcp; ufw allow 59215/udp; ufw allow 65102/tcp; ufw --force enable

# BBR
cat > /etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl --system >/dev/null 2>&1

mkdir -p /var/www/decoy /var/www/certbot
echo "<h1>System Admin</h1>" > /var/www/decoy/index.html

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
    certbot certonly --webroot -w /var/www/certbot -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email || true
fi

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
export DB_OLD_DOMAIN="$OLD_DOMAIN"
export DB_PANEL_PORT="$PANEL_PORT"
export DB_WEB_PATH="$WEB_PATH"
export DB_SUB_PORT="$SUB_PORT"
export DB_SUB_PATH="$SUB_PATH"
export DB_CERT_PATH="$CERT_PATH"
export DB_KEY_PATH="$KEY_PATH"
export USE_CUSTOM="$USE_CUSTOM"

echo -e "${YELLOW}Внедрение конфига...${NC}"
python3 << 'PYEOF'
import os, sqlite3, json, secrets, uuid

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

if os.environ['USE_CUSTOM'] == 'true':
    with open('/tmp/server_config.json', 'r') as f:
        config = json.load(f)

    old_domain = os.environ.get('DB_OLD_DOMAIN', '').strip()
    if old_domain:
        # Меняем только если пользователь ввел старый домен
        config_str = json.dumps(config).replace(old_domain, os.environ['DB_DOMAIN'])
        config = json.loads(config_str)

    def update_certs(obj):
        if isinstance(obj, dict):
            for k, v in obj.items():
                if k in ("certificateFile", "keyFile") and isinstance(v, str):
                    obj[k] = os.environ['DB_CERT_PATH'] if "fullchain" in v else os.environ['DB_KEY_PATH']
                else:
                    update_certs(v)
        elif isinstance(obj, list):
            for item in obj:
                update_certs(item)
    update_certs(config)

    for inb in config.get("inbounds", []):
        if inb.get("tag") in ["api", "panel-egress"]:
            continue
        
        port, protocol = inb["port"], inb["protocol"]
        s_json = json.dumps(inb.get("settings", {}))
        st_json = json.dumps(inb.get("streamSettings", {}))
        sn_json = json.dumps(inb.get("sniffing", {"enabled": True, "destOverride": ["http", "tls"]}))
        tag = inb.get("tag", f"inbound-{port}")

        c.execute("INSERT INTO inbounds (user_id, port, protocol, settings, stream_settings, tag, sniffing, enable) VALUES (1, ?, ?, ?, ?, ?, ?, 1)", 
                  (port, protocol, s_json, st_json, tag, sn_json))
        inbound_id = c.lastrowid

        for client in inb.get("settings", {}).get("clients", []):
            email = client.get("email", "")
            c_uuid = client.get("id") or client.get("auth") or client.get("pass") or str(uuid.uuid4())
            c_sub_id = secrets.token_hex(8)
            try:
                c.execute("INSERT INTO clients (email, sub_id, uuid, enable) VALUES (?, ?, ?, 1)", (email, c_sub_id, c_uuid))
                c.execute("INSERT INTO client_inbounds (client_id, inbound_id) VALUES (?, ?)", (c.lastrowid, inbound_id))
            except sqlite3.IntegrityError:
                pass

    template = config.copy()
    if "inbounds" in template: del template["inbounds"]
    c.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('xrayTemplateConfig', ?)", (json.dumps(template),))
    print("\033[0;32mКастомный конфиг успешно применен!\033[0m")

else:
    # Стандартная XHTTP установка (такая же как в прошлом скрипте)
    client_names = ["zfold", "passwall", "work", "TV", "note10"]
    settings_clients = []
    for name in client_names:
        c_uuid = str(uuid.uuid4())
        c_sub_id = secrets.token_hex(8)
        settings_clients.append({
            "id": c_uuid, "flow": "", "email": f"{name}@{os.environ['DB_DOMAIN']}",
            "limitIp": 0, "totalGB": 0, "expiryTime": 0, "enable": True,
            "tgId": 0, "subId": c_sub_id, "reset": 0
        })
        c.execute("INSERT INTO clients (email, sub_id, uuid, enable) VALUES (?, ?, ?, 1)", 
                  (f"{name}@{os.environ['DB_DOMAIN']}", c_sub_id, c_uuid))

    import subprocess
    xray_bin = subprocess.check_output("find /usr/local/x-ui/bin/ -name 'xray*' -type f | head -n 1", shell=True).decode().strip()
    keys = subprocess.check_output(f"{xray_bin} x25519", shell=True).decode()
    priv_key = [line.split()[-1] for line in keys.split('\n') if 'Private' in line][0]
    pub_key = [line.split()[-1] for line in keys.split('\n') if 'Password' in line or 'Public' in line][0]
    short_id = secrets.token_hex(4)

    settings_json = json.dumps({"clients": settings_clients, "decryption": "none"})
    stream_json = json.dumps({
        "network": "xhttp", "security": "reality",
        "xhttpSettings": {"path": "/api/v3/stream", "mode": "stream-one"},
        "realitySettings": {
            "show": False, "target": "127.0.0.1:40000", "xver": 0,
            "serverNames": [os.environ['DB_DOMAIN']],
            "privateKey": priv_key, "shortIds": [short_id],
            "settings": {"publicKey": pub_key, "fingerprint": "chrome", "spiderX": "/"}
        },
        "sockopt": {"tcpFastOpen": True, "tcpcongestion": "bbr"}
    })

    c.execute("INSERT INTO inbounds (user_id, port, protocol, settings, stream_settings, tag, sniffing, enable) VALUES (1, 443, 'vless', ?, ?, 'inbound-443', '{\"enabled\":true,\"destOverride\":[\"http\",\"tls\"]}', 1)", 
              (settings_json, stream_json))
    inbound_id = c.lastrowid
    for name in client_names:
        c.execute("INSERT INTO client_inbounds (client_id, inbound_id) SELECT id, ? FROM clients WHERE email = ?", 
                  (inbound_id, f"{name}@{os.environ['DB_DOMAIN']}"))
    print("\033[0;32mСтандартная установка завершена!\033[0m")

conn.commit()
conn.close()
PYEOF

echo -e "${YELLOW}Настройка Nginx...${NC}"
cat > /etc/nginx/sites-available/decoy <<EOF
server {
    listen 80; server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$host\$request_uri; }
}
server {
    listen 127.0.0.1:${NGINX_PORT} ssl http2;
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
