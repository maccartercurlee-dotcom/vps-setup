#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}=== Начинаю установку (с авто-настройкой подписок и SNI) ===${NC}"

# 1. Ввод данных
read -p "Введите ваш домен (ОБЯЗАТЕЛЬНО для Reality, или оставьте пустым для IP): " DOMAIN
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

IP_ADDR=$(curl -s ifconfig.me)
if [ -z "$DOMAIN" ]; then
    SERVER_NAME="_"
    USE_DOMAIN=false
    URL_HOST="$IP_ADDR"
else
    SERVER_NAME="$DOMAIN"
    USE_DOMAIN=true
    URL_HOST="$DOMAIN"
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
    mkdir -p /etc/ssl/self-signed
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/self-signed/privkey.pem -out /etc/ssl/self-signed/fullchain.pem -subj "/CN=$URL_HOST"
    CERT_PATH="/etc/ssl/self-signed/fullchain.pem"; KEY_PATH="/etc/ssl/self-signed/privkey.pem"
fi

# 6. Генерация путей и установка 3x-ui
echo -e "${YELLOW}[5/7] Установка 3x-ui и генерация путей...${NC}"
RAND_PANEL_STR=$(head /dev/urandom | tr -dc a-z0-9 | head -c 12)
RAND_SUB_STR=$(head /dev/urandom | tr -dc a-z0-9 | head -c 12)

export XUI_DB_TYPE=sqlite
export XUI_DB_FOLDER=/etc/x-ui
export XUI_PORT=55000
export XUI_SUB_PORT=56000
export XUI_INIT_WEB_BASE_PATH="/$RAND_PANEL_STR/"

bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

sleep 5
x-ui setting -username "$PANEL_USER" -password "$PANEL_PASS" || true

# 7. АВТОМАТИЧЕСКАЯ НАСТРОЙКА ПОДПИСОК В БАЗЕ ДАННЫХ
echo -e "${YELLOW}[6/7] Автоматическая настройка параметров подписки в БД...${NC}"

sqlite3 /etc/x-ui/x-ui.db "UPDATE settings SET value='/$RAND_PANEL_STR/' WHERE key='webBasePath';" 2>/dev/null || true
sqlite3 /etc/x-ui/x-ui.db "UPDATE settings SET value='/$RAND_SUB_STR/' WHERE key='subPath';" 2>/dev/null || true
sqlite3 /etc/x-ui/x-ui.db "UPDATE settings SET value='$URL_HOST' WHERE key='subDomain';" 2>/dev/null || true
sqlite3 /etc/x-ui/x-ui.db "UPDATE settings SET value='56000' WHERE key='subPort';" 2>/dev/null || true
sqlite3 /etc/x-ui/x-ui.db "UPDATE settings SET value='true' WHERE key='subEnable';" 2>/dev/null || true

get_setting() {
    local key=$1
    local default=$2
    local val=$(sqlite3 /etc/x-ui/x-ui.db "SELECT value FROM settings WHERE key='$key';" 2>/dev/null)
    if [ -z "$val" ]; then echo "$default"; else echo "$val"; fi
}

WEB_BASE_RAW=$(get_setting "webBasePath" "/$RAND_PANEL_STR/")
SUB_PATH_RAW=$(get_setting "subPath" "/$RAND_SUB_STR/")

WEB_BASE_PATH=$(echo "$WEB_BASE_RAW" | sed 's|/*$||')
SUB_PATH=$(echo "$SUB_PATH_RAW" | sed 's|/*$||')

# 8. Финальный конфиг Nginx (С ПОДДЕРЖКОЙ PROXY PROTOCOL)
echo -e "${YELLOW}[7/7] Настройка Nginx...${NC}"
cat > /etc/nginx/sites-available/decoy <<EOF
server {
    listen 80; listen [::]:80; server_name $SERVER_NAME;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$host\$request_uri; }
}

server {
    # proxy_protocol нужен, так как Xray передает реальный IP клиента (Xver: 1)
    listen 127.0.0.1:50000 ssl http2 proxy_protocol;
    server_name $SERVER_NAME;

    ssl_certificate $CERT_PATH;
    ssl_certificate_key $KEY_PATH;

    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

    location / { root /var/www/decoy; index index.html; }

    location $WEB_BASE_PATH/ {
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

    location $SUB_PATH/ {
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

# 9. КРАСИВЫЙ И ПОНЯТНЫЙ ИТОГ (С SNI)
echo -e ""
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}        УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!                ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e ""
echo -e "${BLUE}ДАННЫЕ ДЛЯ ВХОДА В ПАНЕЛЬ 3X-UI:${NC}"
echo -e "  Логин:  ${YELLOW}$PANEL_USER${NC}"
echo -e "  Пароль: ${YELLOW}$PANEL_PASS${NC}"
echo -e ""
echo -e "${BLUE}ВАШИ СЕКРЕТНЫЕ АДРЕСА (сохранены в БД):${NC}"
echo -e "  Панель:    ${YELLOW}https://$URL_HOST$WEB_BASE_PATH/${NC}"
echo -e "  Подписки:  ${YELLOW}https://$URL_HOST$SUB_PATH/${NC}"
echo -e ""
echo -e "${RED}ВНИМАНИЕ! КАК ЗАЙТИ В ПАНЕЛЬ В ПЕРВЫЙ РАЗ:${NC}"
echo -e "Так как Reality на 443 порту еще не настроен, ссылка выше пока не работает."
echo -e "Воспользуйтесь SSH-туннелем. На ВАШЕМ ПК выполните:"
echo -e "${YELLOW}ssh -L 50000:127.0.0.1:50000 root@$IP_ADDR${NC}"
echo -e "И откройте в браузере на ПК:"
echo -e "${YELLOW}https://127.0.0.1:50000$WEB_BASE_PATH/${NC}"
echo -e "(Согласитесь с предупреждением сертификата)."
echo -e ""
echo -e "${RED}====================================================${NC}"
echo -e "${RED}   КРИТИЧЕСКИ ВАЖНО! НАСТРОЙКА REALITY (SNI)        ${NC}"
echo -e "${RED}====================================================${NC}"
echo -e "В панели 3x-ui при создании Inbound (VLESS) на порту 443,"
echo -e "в разделе Security -> Reality укажите СЛЕДУЮЩИЕ ПАРАМЕТРЫ:"
echo -e ""
echo -e "  1. Dest (Target):       ${YELLOW}127.0.0.1:50000${NC}"
echo -e "  2. SNI (Server Names):  ${YELLOW}$URL_HOST${NC}  <--- ОЧЕНЬ ВАЖНО!"
echo -e "  3. Xver (Proxy Protocol): ${YELLOW}1${NC}"
echo -e ""
echo -e "Если вы не укажете SNI = $URL_HOST, сайт-заглушка и панель"
echo -e "не откроются при попытке зайти на сервер через браузер."
echo -e "${GREEN}====================================================${NC}"
