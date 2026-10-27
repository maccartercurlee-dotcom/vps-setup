#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== Установка (XHTTP + Reality + Nginx) ===${NC}"

# 1. Ввод данных
read -p "Введите домен: " DOMAIN
read -p "Email для Let's Encrypt (Enter - пропустить): " EMAIL
read -p "Логин для панели: " PANEL_USER
read -s -p "Пароль для панели: " PANEL_PASS
echo ""

if [ -z "$DOMAIN" ]; then echo -e "${RED}Домен обязателен!${NC}"; exit 1; fi

# 2. Зависимости
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

# 6. Установка 3x-ui
RAND_PANEL_STR="secret-$(head /dev/urandom | tr -dc a-z0-9 | head -c 8)"
RAND_SUB_STR="sub-$(head /dev/urandom | tr -dc a-z0-9 | head -c 8)"

bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
sleep 5
x-ui setting -username "$PANEL_USER" -password "$PANEL_PASS" || true
systemctl stop x-ui

# 7. ЖЕСТКАЯ НАСТРОЙКА БАЗЫ
echo -e "${YELLOW}Настройка базы данных...${NC}"
sqlite3 /etc/x-ui/x-ui.db <<SQL
INSERT OR REPLACE INTO settings (key, value) VALUES ('webBasePath', '/$RAND_PANEL_STR/');
INSERT OR REPLACE INTO settings (key, value) VALUES ('subPath', '/$RAND_SUB_STR/');
INSERT OR REPLACE INTO settings (key, value) VALUES ('subDomain', '$DOMAIN');
INSERT OR REPLACE INTO settings (key, value) VALUES ('subPort', '56000');
INSERT OR REPLACE INTO settings (key, value) VALUES ('subEnable', 'true');
INSERT OR REPLACE INTO settings (key, value) VALUES ('webListen', '127.0.0.1');
INSERT OR REPLACE INTO settings (key, value) VALUES ('webPort', '55000');
SQL

# 8. Создание инбаунда (Исправлен парсинг ключей)
XRAY_BIN=$(find /usr/local/x-ui/bin/ -name "xray*" -type f | head -n 1)
UUID=$(cat /proc/sys/kernel/random/uuid)
KEYS=$($XRAY_BIN x25519)
PRIV_KEY=$(echo "$KEYS" | grep -i "Private" | awk '{print $2}')
PUB_KEY=$(echo "$KEYS" | grep -i "Password" | awk '{print $3}')
SHORT_ID=$(head /dev/urandom | tr -dc a-f0-9 | head -c 8)

SETTINGS_JSON="{\"clients\":[{\"id\":\"$UUID\",\"flow\":\"\",\"email\":\"default@$DOMAIN\",\"limitIp\":0,\"totalGB\":0,\"expiryTime\":0,\"enable\":true,\"subId\":\"default-sub\"}],\"decryption\":\"none\",\"fallbacks\":[]}"
STREAM_JSON="{\"network\":\"xhttp\",\"security\":\"reality\",\"xhttpSettings\":{\"path\":\"/\",\"mode\":\"stream-one\",\"xPaddingBytes\":\"100-1000\"},\"realitySettings\":{\"show\":false,\"dest\":\"127.0.0.1:50000\",\"xver\":1,\"serverNames\":[\"$DOMAIN\"],\"privateKey\":\"$PRIV_KEY\",\"shortIds\":[\"$SHORT_ID\"]}}"

sqlite3 /etc/x-ui/x-ui.db "INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing) VALUES (1, 0, 0, 0, 'XHTTP-Reality', 1, 0, '', 443, 'vless', '$SETTINGS_JSON', '$STREAM_JSON', 'inbound-443', '{\"enabled\":true,\"destOverride\":[\"http\",\"tls\"]}');"

# 9. Nginx Fallback
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
    location /$RAND_PANEL_STR/ { proxy_pass http://127.0.0.1:55000; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; }
    location /$RAND_SUB_STR/ { proxy_pass http://127.0.0.1:56000; proxy_set_header Host \$host; }
}
EOF

nginx -t && systemctl reload nginx
systemctl start x-ui

echo -e "${GREEN}=== ГОТОВО ===${NC}"
echo "Панель: https://$DOMAIN/$RAND_PANEL_STR/"
echo "Подписка: https://$DOMAIN/$RAND_SUB_STR/"
echo "UUID: $UUID"
echo "Public Key: $PUB_KEY"
echo "SNI: $DOMAIN"
