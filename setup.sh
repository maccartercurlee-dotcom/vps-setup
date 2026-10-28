#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== УСТАНОВКА (XHTTP + REALITY + SQL DUMP HONEYPOT) ===${NC}"

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

# --- СОЗДАНИЕ ХАНИПОТА (СЛИТЫЙ SQL ДАМП) ---
cat > /var/www/decoy/index.html <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>db_backup_2026.sql</title>
    <style>
        body { background-color: #1e1e1e; color: #d4d4d4; font-family: 'Courier New', Courier, monospace; font-size: 14px; padding: 20px; white-space: pre-wrap; line-height: 1.5; }
        .sql-header { color: #569cd6; }
        .sql-table { color: #4ec9b0; }
        .sql-string { color: #ce9178; }
        .sql-number { color: #b5cea8; }
        .sql-comment { color: #6a9955; }
    </style>
</head>
<body><span class="sql-comment">-- MySQL dump 10.13  Distrib 8.0.32, for Linux (x86_64)
--
-- Host: localhost    Database: xui_panel
-- ------------------------------------------------------
-- Server version	8.0.32-0ubuntu0.22.04.2

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table <span class="sql-table">`users`</span>
--

DROP TABLE IF EXISTS <span class="sql-table">`users`</span>;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE <span class="sql-table">`users`</span> (
  <span class="sql-table">`id`</span> int NOT NULL AUTO_INCREMENT,
  <span class="sql-table">`username`</span> varchar(255) NOT NULL,
  <span class="sql-table">`password`</span> varchar(255) NOT NULL,
  <span class="sql-table">`email`</span> varchar(255) DEFAULT NULL,
  <span class="sql-table">`created_at`</span> datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (<span class="sql-table">`id`</span>)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table <span class="sql-table">`users`</span>
--

LOCK TABLES <span class="sql-table">`users`</span> WRITE;
/*!40000 ALTER TABLE <span class="sql-table">`users`</span> DISABLE KEYS */;
INSERT INTO <span class="sql-table">`users`</span> VALUES (<span class="sql-number">1</span>,<span class="sql-string">'admin'</span>,<span class="sql-string">'$2a$10$X8vP1jK9z7wQ2mR4tY6uO.e5N1c3B7x9A2s4D6f8G0h1J3k5L7m9N'</span>,<span class="sql-string">'admin@localhost'</span>,<span class="sql-string">'2026-01-15 08:30:00'</span>),
(<span class="sql-number">2</span>,<span class="sql-string">'root'</span>,<span class="sql-string">'$2a$10$Q9wE1rT3y5U7iO9p0A2s4D6f8G0h1J3k5L7m9N1b3V5c7X9z2Q4w6E'</span>,<span class="sql-string">'root@127.0.0.1'</span>,<span class="sql-string">'2026-02-20 14:15:22'</span>),
(<span class="sql-number">3</span>,<span class="sql-string">'developer'</span>,<span class="sql-string">'$2a$10$Z1x3C5v7B9n1M3k5J7h9G1f3D5s7A9p1O3i5U7y9T1r3E5w7Q9z2X'</span>,<span class="sql-string">'dev@company.com'</span>,<span class="sql-string">'2026-03-10 09:00:11'</span>);
/*!40000 ALTER TABLE <span class="sql-table">`users`</span> ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table <span class="sql-table">`inbounds`</span>
--

DROP TABLE IF EXISTS <span class="sql-table">`inbounds`</span>;
CREATE TABLE <span class="sql-table">`inbounds`</span> (
  <span class="sql-table">`id`</span> int NOT NULL AUTO_INCREMENT,
  <span class="sql-table">`user_id`</span> int NOT NULL,
  <span class="sql-table">`port`</span> int NOT NULL,
  <span class="sql-table">`protocol`</span> varchar(50) NOT NULL,
  <span class="sql-table">`settings`</span> json NOT NULL,
  PRIMARY KEY (<span class="sql-table">`id`</span>)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

LOCK TABLES <span class="sql-table">`inbounds`</span> WRITE;
INSERT INTO <span class="sql-table">`inbounds`</span> VALUES (<span class="sql-number">1</span>,<span class="sql-number">1</span>,<span class="sql-number">443</span>,<span class="sql-string">'vless'</span>,<span class="sql-string">'{"clients":[{"id":"550e8400-e29b-41d4-a716-446655440000","flow":"xtls-rprx-vision"}]}'</span>);
/*!40000 ALTER TABLE <span class="sql-table">`inbounds`</span> ENABLE KEYS */;
UNLOCK TABLES;

/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;
/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-10-28 12:00:00
</span></body>
</html>
HTMLEOF
# --- КОНЕЦ ХАНИПОТА ---

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

echo -e "${YELLOW}Запись в базу (XHTTP + Reality)...${NC}"
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

settings_json = json.dumps({
    "clients": [
        {
            "id": os.environ['DB_UUID'],
            "flow": "",
            "email": f"default@{os.environ['DB_DOMAIN']}",
            "limitIp": 0,
            "totalGB": 0,
            "expiryTime": 0,
            "enable": True,
            "tgId": 0,
            "subId": os.environ['DB_SUB_ID'],
            "reset": 0
        }
    ], 
    "decryption": "none"
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

try:
    c.execute("INSERT INTO clients (email, sub_id, uuid, enable) VALUES (?, ?, ?, 1)", 
              (f"default@{os.environ['DB_DOMAIN']}", os.environ['DB_SUB_ID'], os.environ['DB_UUID']))
    client_id = c.lastrowid
    c.execute("INSERT INTO client_inbounds (client_id, inbound_id) VALUES (?, ?)", (client_id, inbound_id))
except sqlite3.IntegrityError:
    pass

conn.commit()
conn.close()
PYEOF

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
sleep 5 
x-ui setting -username "$PANEL_USER" -password "$PANEL_PASS"
systemctl restart x-ui
sleep 3

echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}        ВСЁ ГОТОВО! СИСТЕМА ЗАПУЩЕНА.               ${NC}"
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
