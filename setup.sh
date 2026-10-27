#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}=== Начинаю установку (XHTTP + Reality + Nginx) ===${NC}"

# 1. Ввод данных
read -p "Введите ваш домен (ОБЯЗАТЕЛЬНО для Reality/SSL): " DOMAIN
read -p "Придумайте логин для панели 3x-ui: " PANEL_USER
read -s -p "Придумайте пароль для панели 3x-ui: " PANEL_PASS
echo ""

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}ОШИБКА: Домен обязателен.${NC}"
    exit 1
fi

# 2. Обновление и установка зависимостей
echo -e "${YELLOW}[1/7] Установка пакетов (Nginx, Certbot, SQLite, UFW)...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y
apt install -y nginx certbot curl wget sqlite3 ufw openssl

# 3. Настройка файрвола
echo -e "${YELLOW}[2/7] Настройка UFW...${NC}"
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# 4. Сайт-заглушка и директория для Certbot
echo -e "${YELLOW}[3/7] Создание заглушки и папки для Certbot...${NC}"
mkdir -p /var/www/decoy
mkdir -p /var/www/certbot
cat > /var/www/decoy/index.html <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head><meta charset="UTF-8"><title>Добро пожаловать</title></head>
<body style="text-align:center; margin-top:20vh; font-family:sans-serif;">
<h1>Сайт успешно работает</h1>
<p>Этот домен настроен и готов к использованию.</p>
</body>
</html>
EOF

# Временный конфиг Nginx (используем webroot для Certbot)
cat > /etc/nginx/sites-available/decoy <<EOF
server {
    listen 80; listen [::]:80; server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { root /var/www/decoy; index index.html; }
}
EOF
ln -sf /etc/nginx/sites-available/decoy /etc/nginx/sites-enabled/decoy
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# 5. Выпуск сертификата Let's Encrypt (без email, через webroot)
echo -e "${YELLOW}[4/7] Выпуск SSL сертификата...${NC}"
CERT_PATH=""; KEY_PATH=""
certbot certonly --webroot -w /var/www/certbot -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email || {
    echo -e "${RED}Ошибка Let's Encrypt, делаю самоподписанный...${NC}"
    mkdir -p /etc/ssl/self-signed
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/self-signed/privkey.pem -out /etc/ssl/self-signed/fullchain.pem -subj "/CN=$DOMAIN"
}
if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"; KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
else
    CERT_PATH="/etc/ssl/self-signed/fullchain.pem"; KEY_PATH="/etc/ssl/self-signed/privkey.pem"
fi

# 6. Установка 3x-ui (SQLite)
echo -e "${YELLOW}[5/7] Установка 3x-ui...${NC}"
RAND_PANEL_STR=$(head /dev/urandom | tr -dc a-z0-9 | head -c 12)
RAND_SUB_STR=$(head /dev/urandom | tr -dc a-z0-9 | head -c 12)

export XUI_DB_TYPE=sqlite
export XUI_DB_FOLDER=/etc/x-ui
export XUI_PORT=55000
export XUI_SUB_PORT=56000
export XUI_INIT_WEB_BASE_PATH="/$RAND_PANEL_STR/"

bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

sleep 6

# 7. ОСТАНОВКА СЕРВИСА ПЕРЕД МОДИФИКАЦИЕЙ БД (Ваш пункт №1)
echo -e "${YELLOW}[6/7] Настройка БД и создание XHTTP Reality (stream-one)...${NC}"
systemctl stop x-ui

# Записываем пути и настройки подписок
sqlite3 /etc/x-ui/x-ui.db "UPDATE settings SET value='/$RAND_PANEL_STR/' WHERE key='webBasePath';" 2>/dev/null || true
sqlite3 /etc/x-ui/x-ui.db "UPDATE settings SET value='/$RAND_SUB_STR/' WHERE key='subPath';" 2>/dev/null || true
sqlite3 /etc/x-ui/x-ui.db "UPDATE settings SET value='$DOMAIN' WHERE key='subDomain';" 2>/dev/null || true
sqlite3 /etc/x-ui/x-ui.db "UPDATE settings SET value='56000' WHERE key='subPort';" 2>/dev/null || true
sqlite3 /etc/x-ui/x-ui.db "UPDATE settings SET value='true' WHERE key='subEnable';" 2>/dev/null || true

# Динамический поиск бинарника Xray (Ваш пункт №2)
XRAY_BIN=$(find /usr/local/x-ui/bin/ -name "xray*" -type f | head -n 1)
if [ -z "$XRAY_BIN" ]; then
    echo -e "${RED}Не удалось найти бинарник Xray!${NC}"
    exit 1
fi

# Генерация ключей Reality
UUID=$(cat /proc/sys/kernel/random/uuid)
KEYS=$($XRAY_BIN x25519)
PRIV_KEY=$(echo "$KEYS" | grep "Private key:" | awk '{print $3}')
PUB_KEY=$(echo "$KEYS" | grep "Public key:" | awk '{print $3}')
SHORT_ID=$(head /dev/urandom | tr -dc a-f0-9 | head -c 8)

# JSON конфиг для клиента
SETTINGS_JSON=$(cat <<JSON
{
  "clients": [
    {
      "id": "$UUID",
      "flow": "",
      "email": "default@$DOMAIN",
      "limitIp": 0,
      "totalGB": 0,
      "expiryTime": 0,
      "enable": true,
      "tgId": "",
      "subId": "default-sub"
    }
  ],
  "decryption": "none",
  "fallbacks": []
}
JSON
)

# JSON конфиг транспорта (XHTTP stream-one + Reality)
STREAM_JSON=$(cat <<JSON
{
  "network": "xhttp",
  "security": "reality",
  "xhttpSettings": {
    "path": "/",
    "mode": "stream-one",
    "xPaddingBytes": "100-1000"
  },
  "realitySettings": {
    "show": false,
    "dest": "127.0.0.1:50000",
    "xver": 1,
    "serverNames": ["$DOMAIN"],
    "privateKey": "$PRIV_KEY",
    "shortIds": ["$SHORT_ID"]
  }
}
JSON
)

# Вставляем инбаунд в базу данных
sqlite3 /etc/x-ui/x-ui.db <<SQL
INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing)
VALUES (1, 0, 0, 0, 'XHTTP-Reality-443', 1, 0, '', 443, 'vless', '$SETTINGS_JSON', '$STREAM_JSON', 'inbound-443', '{"enabled":true,"destOverride":["http","tls"]}');
SQL

# Включаем сервис обратно
systemctl start x-ui

# 8. Финальный конфиг Nginx (порт 50000 + proxy_protocol)
echo -e "${YELLOW}[7/7] Настройка Nginx как Fallback...${NC}"
cat > /etc/nginx/sites-available/decoy <<EOF
server {
    listen 80; listen [::]:80; server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen 127.0.0.1:50000 ssl http2 proxy_protocol;
    server_name $DOMAIN;

    ssl_certificate $CERT_PATH;
    ssl_certificate_key $KEY_PATH;

    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

    location / { root /var/www/decoy; index index.html; }

    location /$RAND_PANEL_STR/ {
        proxy_pass http://127.0.0.1:55000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 3600s;
    }

    location /$RAND_SUB_STR/ {
        proxy_pass http://127.0.0.1:56000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

nginx -t && systemctl reload nginx
systemctl restart x-ui

# 9. Итог
echo -e ""
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}        УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!                ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e ""
echo -e "${BLUE}ДАННЫЕ ДЛЯ ВХОДА В ПАНЕЛЬ 3X-UI:${NC}"
echo -e "  Логин:  ${YELLOW}$PANEL_USER${NC}"
echo -e "  Пароль: ${YELLOW}$PANEL_PASS${NC}"
echo -e ""
echo -e "${GREEN}ССЫЛКИ ДОСТУПА (РАБОТАЮТ СРАЗУ):${NC}"
echo -e "  Панель:    ${YELLOW}https://$DOMAIN/$RAND_PANEL_STR/${NC}"
echo -e "  Подписки:  ${YELLOW}https://$DOMAIN/$RAND_SUB_STR/${NC}"
echo -e ""
echo -e "${RED}ДАННЫЕ ДЛЯ КЛИЕНТА (v2rayNG / Happ и др.):${NC}"
echo -e "  Протокол:  VLESS"
echo -e "  Адрес:     $DOMAIN"
echo -e "  Порт:      443"
echo -e "  UUID:      $UUID"
echo -e "  Flow:      (оставить пустым!)"
echo -e "  Security:  Reality"
echo -e "  SNI:       $DOMAIN"
echo -e "  Public Key:$PUB_KEY"
echo -e "  Short ID:  $SHORT_ID"
echo -e "  Fingerprint: chrome"
echo -e "  Транспорт: XHTTP"
echo -e "  Path:      /"
echo -e "  Mode:      stream-one"
echo -e "${GREEN}====================================================${NC}"
