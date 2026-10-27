#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== Начинаю установку (Архитектура: Nginx за Fallback) ===${NC}"

# 1. Ввод данных
read -p "Введите ваш домен (или оставьте пустым для IP): " DOMAIN
read -p "Придумайте логин для панели 3x-ui: " PANEL_USER
read -s -p "Придумайте пароль для панели 3x-ui: " PANEL_PASS
echo ""

# 2. Зависимости
echo -e "${YELLOW}[1/6] Установка Nginx, Certbot, UFW...${NC}"
apt update && apt upgrade -y
apt install -y nginx certbot python3-certbot-nginx curl wget sqlite3 ufw

# 3. Файрвол (ТОЛЬКО 22, 80, 443)
echo -e "${YELLOW}[2/6] Настройка UFW...${NC}"
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# 4. Сайт-заглушка
echo -e "${YELLOW}[3/6] Создание заглушки...${NC}"
mkdir -p /var/www/decoy
cat > /var/www/decoy/index.html <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>Добро пожаловать</title>
</head>
<body style="text-align:center; margin-top:20vh; font-family:sans-serif;">
    <h1>Сайт успешно работает</h1>
    <p>Этот домен настроен и готов к использованию.</p>
</body>
</html>
EOF

if [ -z "$DOMAIN" ]; then
    SERVER_NAME="_"
    USE_DOMAIN=false
else
    SERVER_NAME="$DOMAIN"
    USE_DOMAIN=true
fi

# Временный конфиг Nginx только для Certbot (порт 80)
cat > /etc/nginx/sites-available/decoy <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $SERVER_NAME;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { root /var/www/decoy; index index.html; }
}
EOF
ln -sf /etc/nginx/sites-available/decoy /etc/nginx/sites-enabled/decoy
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# 5. Выпуск сертификата
echo -e "${YELLOW}[4/6] Выпуск SSL...${NC}"
CERT_PATH=""
KEY_PATH=""

if [ "$USE_DOMAIN" = true ]; then
    certbot certonly --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" --no-eff-email || {
        echo -e "${RED}Ошибка Let's Encrypt, делаю самоподписанный...${NC}"
        mkdir -p /etc/ssl/self-signed
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/self-signed/privkey.pem -out /etc/ssl/self-signed/fullchain.pem -subj "/CN=$SERVER_NAME"
        CERT_PATH="/etc/ssl/self-signed/fullchain.pem"
        KEY_PATH="/etc/ssl/self-signed/privkey.pem"
    }
    if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
        CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
        KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    fi
else
    IP=$(curl -s ifconfig.me)
    mkdir -p /etc/ssl/self-signed
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/self-signed/privkey.pem -out /etc/ssl/self-signed/fullchain.pem -subj "/CN=$IP"
    CERT_PATH="/etc/ssl/self-signed/fullchain.pem"
    KEY_PATH="/etc/ssl/self-signed/privkey.pem"
fi

# 6. Финальный конфиг Nginx (порт 50000 для Fallback)
echo -e "${YELLOW}[5/6] Настройка путей Nginx...${NC}"
cat > /etc/nginx/sites-available/decoy <<EOF
# HTTP -> HTTPS редирект
server {
    listen 80;
    listen [::]:80;
    server_name $SERVER_NAME;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$host\$request_uri; }
}

# Слушаем 50000 для Fallback от 3x-ui Reality
server {
    listen 127.0.0.1:50000 ssl http2;
    server_name $SERVER_NAME;

    ssl_certificate $CERT_PATH;
    ssl_certificate_key $KEY_PATH;

    # Сайт-заглушка
    location / {
        root /var/www/decoy;
        index index.html;
    }

    # Прокси для панели (внешний путь /panel/)
    location /panel/ {
        proxy_pass http://127.0.0.1:55000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Прокси для подписок (внешний путь /sub/)
    location /sub/ {
        proxy_pass http://127.0.0.1:56000/sub/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
nginx -t && systemctl reload nginx

# 7. Установка 3x-ui (SQLite, порты 55000/56000)
echo -e "${YELLOW}[6/6] Установка 3x-ui...${NC}"
export XUI_DB_TYPE=sqlite
export XUI_DB_FOLDER=/etc/x-ui
export XUI_PORT=55000
export XUI_SUB_PORT=56000
export XUI_INIT_WEB_BASE_PATH=/panel/

bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

sleep 5
x-ui setting -username "$PANEL_USER" -password "$PANEL_PASS" || true
systemctl restart x-ui

# 8. Вывод результатов
IP=$(curl -s ifconfig.me)
URL_HOST="$IP"
[ "$USE_DOMAIN" = true ] && URL_HOST="$DOMAIN"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Установка завершена!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Логин: ${YELLOW}$PANEL_USER${NC}"
echo -e "Пароль: ${YELLOW}$PANEL_PASS${NC}"
echo -e ""
echo -e "${GREEN}ДОСТУП К ПАНЕЛИ И ПОДПИСКАМ (через Nginx/Fallback):${NC}"
echo -e "Панель:    ${YELLOW}https://$URL_HOST/panel/${NC}"
echo -e "Подписки:  ${YELLOW}https://$URL_HOST/sub/${NC}"
echo -e ""
echo -e "${RED}ВАЖНО! НАСТРОЙКА FALLBACK В 3X-UI:${NC}"
echo -e "1. Зайдите в панель (пока напрямую: http://127.0.0.1:55000/panel/ или через SSH-туннель)."
echo -e "2. Создайте Inbound VLESS Reality на порту 443."
echo -e "3. В настройках Reality Fallbacks добавьте:"
echo -e "   Name: nginx"
echo -e "   Dest: 127.0.0.1:50000"
echo -e "   Xver: 1"
echo -e "   Path: /"
echo -e "4. Теперь весь трафик на 443 идет в Xray, а обычные запросы падают в Nginx на 50000."
echo -e "${GREEN}========================================${NC}"
