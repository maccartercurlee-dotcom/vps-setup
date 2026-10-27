#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== Установка (XHTTP + Reality + Nginx) ===${NC}"

# 1. Ввод данных
read -p "Введите ваш домен: " DOMAIN
read -p "Email для Let's Encrypt (Enter - пропустить): " EMAIL
read -p "Придумайте логин для панели: " PANEL_USER
read -s -p "Придумайте пароль для панели: " PANEL_PASS
echo ""

if [ -z "$DOMAIN" ]; then echo -e "${RED}Домен обязателен!${NC}"; exit 1; fi

# 2. Зависимости
export DEBIAN_FRONTEND=noninteractive
apt update && apt install -y nginx certbot curl wget sqlite3 ufw openssl

# 3. UFW
ufw allow 22/tcp; ufw allow 80/tcp; ufw allow 443/tcp; ufw --force enable

# 4. Заглушка и Certbot
mkdir -p /var/www/decoy /var/www/certbot
echo "<h1>Welcome</h1>" > /var/www/decoy/index.html
cat > /etc/nginx/sites-available/decoy <<EOF
server {
    listen 80; server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { root /var/www/decoy; index index.html; }
}
EOF
ln -sf /etc/nginx/sites-available/decoy /etc/nginx/sites-enabled/decoy
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# 5. Сертификат
EMAIL_ARG="--register-unsafely-without-email"
[ -n "$EMAIL" ] && EMAIL_ARG="-m $EMAIL"
certbot certonly --webroot -w /var/www/certbot -d "$DOMAIN" --non-interactive --agree-tos $EMAIL_ARG || true

CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
if [ ! -f "$CERT_PATH" ]; then
    mkdir -p /etc/ssl/self-signed
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/self-signed/privkey.pem -out /etc/ssl/self-signed/fullchain.pem -subj "/CN=$DOMAIN"
    CERT_PATH="/etc/ssl/self-signed/fullchain.pem"; KEY_PATH="/etc/ssl/self-signed/privkey.pem"
fi

# 6. Установка 3x-ui (Автоматические ответы)
echo -e "${YELLOW}Установка 3x-ui (авто-режим)...${NC}"
wget -qO /tmp/xui-install.sh https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh
printf "1\nn\n4\ny\n" | bash /tmp/xui-install.sh

sleep 5
systemctl stop x-ui

# 7. ЖЕСТКАЯ ПЕРЕЗАПИСЬ БАЗЫ (порты и локальный адрес)
echo -e "${YELLOW}Принудительная настройка базы данных...${NC}"
x-ui setting -username "$PANEL_USER" -password "$PANEL_PASS" || true

sqlite3 /etc/x-ui/x-ui.db <<SQL
INSERT OR REPLACE INTO settings (key, value) VALUES ('webPort', '55000');
INSERT OR REPLACE INTO settings (key, value) VALUES ('webListen', '127.0.0.1');
INSERT OR REPLACE INTO settings (key, value) VALUES ('subPort', '56000');
INSERT OR REPLACE INTO settings (key, value) VALUES ('subListen', '127.0.0.1');
INSERT OR REPLACE INTO settings (key, value) VALUES ('subDomain', '$DOMAIN');
INSERT OR REPLACE INTO settings (key, value) VALUES ('subEnable', 'true');
SQL

# 8. Создание инбаунда XHTTP+Reality
echo -e "${YELLOW}Создание инбаунда...${NC}"
XRAY_BIN=$(find /usr/local/x-ui/bin/ -name "xray*" -type f | head -n 1)
UUID=$(cat /proc/sys/kernel/random/uuid)
KEYS=$($XRAY_BIN x25519)
PRIV_KEY=$(echo "$KEYS" | grep -i "PrivateKey" | awk '{print $NF}')
PUB_KEY=$(echo "$KEYS" | grep -i "Password" | awk '{print $NF}')
SHORT_ID=$(head /dev/urandom | tr -dc a-f0-9 | head -c 8)

SETTINGS_JSON="{\"clients\":[{\"id\":\"$UUID\",\"flow\":\"\",\"email\":\"default@$DOMAIN\",\"limitIp\":0,\"totalGB\":0,\"expiryTime\":0,\"enable\":true,\"subId\":\"default-sub\"}],\"decryption\":\"none\",\"fallbacks\":[]}"
STREAM_JSON="{\"network\":\"xhttp\",\"security\":\"reality\",\"xhttpSettings\":{\"path\":\"/\",\"mode\":\"stream-one\",\"xPaddingBytes\":\"100-1000\"},\"realitySettings\":{\"show\":false,\"dest\":\"127.0.0.1:50000\",\"xver\":1,\"serverNames\":[\"$DOMAIN\"],\"privateKey\":\"$PRIV_KEY\",\"shortIds\":[\"$SHORT_ID\"]}}"

sqlite3 /etc/x-ui/x-ui.db "INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing) VALUES (1, 0, 0, 0, 'XHTTP-Reality', 1, 0, '', 443, 'vless', '$SETTINGS_JSON', '$STREAM_JSON', 'inbound-443', '{\"enabled\":true,\"destOverride\":[\"http\",\"tls\"]}');"

# 9. ВЫТАСКИВАЕМ РЕАЛЬНЫЕ ПУТИ ИЗ БАЗЫ (которые создал установщик) И СТРОИМ NGINX
REAL_WEB_PATH=$(sqlite3 /etc/x-ui/x-ui.db "SELECT value FROM settings WHERE key='webBasePath';")
REAL_SUB_PATH=$(sqlite3 /etc/x-ui/x-ui.db "SELECT value FROM settings WHERE key='subPath';")

echo -e "${YELLOW}Настройка Nginx...${NC}"
cat > /etc/nginx/sites-available/decoy <<EOF
server {
    listen 80; server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$host\$request_uri; }
}
server {
    listen 127.0.0.1:50000 ssl http2 proxy_protocol;
    server_name $DOMAIN;
    ssl_certificate $CERT_PATH; ssl_certificate_key $KEY_PATH;
    set_real_ip_from 127.0.0.1; real_ip_header proxy_protocol;
    location / { root /var/www/decoy; index index.html; }
    location $REAL_WEB_PATH { proxy_pass http://127.0.0.1:55000; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; }
    location $REAL_SUB_PATH { proxy_pass http://127.0.0.1:56000; proxy_set_header Host \$host; }
}
EOF

nginx -t && systemctl reload nginx
systemctl restart x-ui

# 10. Итог
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}=== УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА ===${NC}"
echo -e "${GREEN}========================================${NC}"
echo "Панель: https://$DOMAIN$REAL_WEB_PATH"
echo "Подписка: https://$DOMAIN$REAL_SUB_PATH"
echo "Логин: $PANEL_USER"
echo "Пароль: $PANEL_PASS"
echo "----------------------------------------"
echo "Данные для клиента (VLESS):"
echo "  Адрес: $DOMAIN"
echo "  Порт: 443"
echo "  UUID: $UUID"
echo "  Public Key: $PUB_KEY"
echo "  Short ID: $SHORT_ID"
echo "  SNI: $DOMAIN"
echo "  Транспорт: XHTTP (stream-one)"
echo -e "${GREEN}========================================${NC}"
