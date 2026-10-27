#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== Начинаю установку (с автоопределением путей из БД) ===${NC}"

# 1. Ввод данных
read -p "Введите ваш домен (или оставьте пустым для IP): " DOMAIN
read -p "Придумайте логин для панели 3x-ui: " PANEL_USER
read -s -p "Придумайте пароль для панели 3x-ui: " PANEL_PASS
echo ""

# 2. Зависимости
echo -e "${YELLOW}[1/7] Установка Nginx, Certbot, UFW, SQLite...${NC}"
apt update && apt upgrade -y
apt install -y nginx certbot python3-certbot-nginx curl wget sqlite3 ufw

# 3. Файрвол
echo -e "${YELLOW}[2/7] Настройка UFW...${NC}"
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# 4. Сайт-заглушка
echo -e "${YELLOW}[3/7] Создание заглушки...${NC}"
mkdir -p /var/www/decoy
cat > /var/www/decoy/index.html <<'EOF'
<!DOCTYPE html>
<html lang="ru"><head><meta charset="UTF-8"><title>Добро пожаловать</title></head>
<body style="text-align:center; margin-top:20vh; font-family:sans-serif;">
<h1>Сайт успешно работает</h1><p>Этот домен настроен и готов к использованию.</p>
</body></html>
EOF

if [ -z "$DOMAIN" ]; then
    SERVER_NAME="_"
    USE_DOMAIN=false
else
    SERVER_NAME="$DOMAIN"
    USE_DOMAIN=true
fi

# Временный конфиг Nginx для Certbot
cat > /etc/nginx/sites-available/decoy <<EOF
server {
    listen 80; listen [::]:80; server_name $SERVER_NAME;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { root /var/www/decoy; index index.html; }
}
EOF
ln -sf /etc/nginx/sites-available/decoy /etc/nginx/sites-enabled/decoy
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# 5. Сертификат
echo -e "${YELLOW}[4/7] Выпуск SSL...${NC}"
CERT_PATH=""; KEY_PATH=""
if [ "$USE_DOMAIN" = true ]; then
    certbot certonly --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" --no-eff-email || {
        echo -e "${RED}Ошибка Let's Encrypt, делаю самоподписанный...${NC}"
        mkdir -p /etc/ssl/self-signed
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/self-signed/privkey.pem -out /etc/ssl/self-signed/fullchain.pem -subj "/CN=$SERVER_NAME"
        CERT_PATH="/etc/ssl/self-signed/fullchain.pem"; KEY_PATH="/etc/ssl/self-signed/privkey.pem"
    }
    if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
        CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"; KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    fi
else
    IP=$(curl -s ifconfig.me); mkdir -p /etc/ssl/self-signed
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/self-signed/privkey.pem -out /etc/ssl/self-signed/fullchain.pem -subj "/CN=$IP"
    CERT_PATH="/etc/ssl/self-signed/fullchain.pem"; KEY_PATH="/etc/ssl/self-signed/privkey.pem"
fi

# 6. Установка 3x-ui
echo -e "${YELLOW}[5/7] Установка 3x-ui...${NC}"
export XUI_DB_TYPE=sqlite
export XUI_DB_FOLDER=/etc/x-ui
export XUI_PORT=55000
export XUI_SUB_PORT=56000
# Временный путь, чтобы панель запустилась и создала БД
export XUI_INIT_WEB_BASE_PATH=/panel/ 

bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

sleep 5
x-ui setting -username "$PANEL_USER" -password "$PANEL_PASS" || true

# 7. ИЗВЛЕЧЕНИЕ ПУТЕЙ ИЗ БД И НАСТРОЙКА NGINX
echo -e "${YELLOW}[6/7] Чтение путей из базы данных SQLite...${NC}"

# Функция для получения значения из БД (с фолбэком, если ключа нет)
get_setting() {
    local key=$1
    local default=$2
    local val=$(sqlite3 /etc/x-ui/x-ui.db "SELECT value FROM settings WHERE key='$key';" 2>/dev/null)
    if [ -z "$val" ]; then echo "$default"; else echo "$val"; fi
}

# Получаем пути (нормализуем: добавляем ведущий / и убираем завершающий /)
WEB_BASE_RAW=$(get_setting "webBasePath" "/panel/")
SUB_PATH_RAW=$(get_setting "subPath" "/sub/")

WEB_BASE_PATH=$(echo "$WEB_BASE_RAW" | sed 's|^[^/]|/&|; s|/*$||')/
SUB_PATH=$(echo "$SUB_PATH_RAW" | sed 's|^[^/]|/&|; s|/*$||')/

echo -e "Найден путь панели: ${GREEN}$WEB_BASE_PATH${NC}"
echo -e "Найден путь подписки: ${GREEN}$SUB_PATH${NC}"

# 8. Финальный конфиг Nginx
echo -e "${YELLOW}[7/7] Настройка Nginx с динамическими путями...${NC}"
cat > /etc/nginx/sites-available/decoy <<EOF
server {
    listen 80; listen [::]:80; server_name $SERVER_NAME;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen 127.0.0.1:50000 ssl http2;
    server_name $SERVER_NAME;

    ssl_certificate $CERT_PATH;
    ssl_certificate_key $KEY_PATH;

    location / { root /var/www/decoy; index index.html; }

    # Панель (путь берется из БД 3x-ui)
    location $WEB_BASE_PATH {
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

    # Подписки (путь берется из БД 3x-ui)
    location $SUB_PATH {
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
IP=$(curl -s ifconfig.me); URL_HOST="$IP"
[ "$USE_DOMAIN" = true ] && URL_HOST="$DOMAIN"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Установка завершена!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Логин: ${YELLOW}$PANEL_USER${NC}"
echo -e "Пароль: ${YELLOW}$PANEL_PASS${NC}"
echo -e ""
echo -e "${GREEN}АКТУАЛЬНЫЕ ПУТИ (из БД):${NC}"
echo -e "Панель:    ${YELLOW}https://$URL_HOST$WEB_BASE_PATH${NC}"
echo -e "Подписки:  ${YELLOW}https://$URL_HOST$SUB_PATH${NC}"
echo -e ""
echo -e "${RED}ВАЖНО! НАСТРОЙКА FALLBACK В 3X-UI:${NC}"
echo -e "1. Создайте Inbound VLESS Reality на порту 443."
echo -e "2. В настройках Reality Fallbacks добавьте:"
echo -e "   Dest: 127.0.0.1:50000 (Xver: 1)"
echo -e "${GREEN}========================================${NC}"
