#!/bin/bash
set -e  # Остановить выполнение при любой ошибке

# --- Цвета для вывода ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== Начинаю установку и настройку сервера ===${NC}"

# --- 1. Запрос данных у пользователя ---
read -p "Введите ваш домен (или оставьте пустым для использования IP): " DOMAIN
read -p "Придумайте логин для панели 3x-ui: " PANEL_USER
read -s -p "Придумайте пароль для панели 3x-ui: " PANEL_PASS
echo "" # перенос строки после скрытого ввода

# --- 2. Обновление системы и установка зависимостей ---
echo -e "${YELLOW}[1/6] Обновление пакетов и установка Nginx, Certbot...${NC}"
apt update && apt upgrade -y
apt install -y nginx certbot python3-certbot-nginx curl wget sqlite3 ufw

# --- 3. Настройка UFW (базовая защита) ---
echo -e "${YELLOW}[2/6] Настройка файрвола...${NC}"
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP (Certbot + заглушка)
ufw allow 443/tcp   # HTTPS (для 3x-ui VLESS Reality)
# Порты 50000, 55000, 56000 НЕ открываем — они слушают только localhost
ufw --force enable

# --- 4. Создание сайта-заглушки и настройка Nginx ---
echo -e "${YELLOW}[3/6] Создание сайта-заглушки и конфигурации Nginx...${NC}"

# Создаём папку для заглушки
mkdir -p /var/www/decoy
cat > /var/www/decoy/index.html <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>Добро пожаловать</title>
    <style>
        body { font-family: sans-serif; text-align: center; margin-top: 20vh; background: #f4f4f4; }
        h1 { color: #333; }
        p { color: #666; }
    </style>
</head>
<body>
    <h1>Сайт успешно работает</h1>
    <p>Этот домен настроен и готов к использованию.</p>
</body>
</html>
EOF

# Определяем, использовать ли домен или IP
if [ -z "$DOMAIN" ]; then
    echo -e "${YELLOW}Домен не указан. Будет использован IP-адрес сервера.${NC}"
    SERVER_NAME="_"  # wildcard для Nginx, чтобы принимал запросы по IP
    USE_DOMAIN=false
else
    SERVER_NAME="$DOMAIN"
    USE_DOMAIN=true
fi

# Временный конфиг Nginx ТОЛЬКО для проверки Certbot (порт 80)
cat > /etc/nginx/sites-available/decoy <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $SERVER_NAME;

    root /var/www/decoy;
    index index.html;

    # Папка для проверки Certbot
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

# Активируем конфиг и перезагружаем Nginx
ln -sf /etc/nginx/sites-available/decoy /etc/nginx/sites-enabled/decoy
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

# --- 5. Выпуск сертификата (Let's Encrypt или самоподписанный) ---
echo -e "${YELLOW}[4/6] Выпуск SSL-сертификата...${NC}"

CERT_PATH=""
KEY_PATH=""

if [ "$USE_DOMAIN" = true ]; then
    echo "Запрашиваю сертификат Let's Encrypt для домена: $DOMAIN"
    # Certbot в режиме --nginx сам настроит редирект, но мы сделаем это позже вручную
    certbot certonly --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" --no-eff-email || {
        echo -e "${RED}Не удалось получить сертификат Let's Encrypt. Проверьте DNS-запись домена.${NC}"
        echo -e "${YELLOW}Создаю самоподписанный сертификат как запасной вариант...${NC}"
        mkdir -p /etc/ssl/self-signed
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/ssl/self-signed/privkey.pem \
            -out /etc/ssl/self-signed/fullchain.pem \
            -subj "/CN=$SERVER_NAME"
        CERT_PATH="/etc/ssl/self-signed/fullchain.pem"
        KEY_PATH="/etc/ssl/self-signed/privkey.pem"
    }
    if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
        CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
        KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    fi
else
    echo -e "${YELLOW}Домен не указан. Создаю самоподписанный сертификат для IP...${NC}"
    IP=$(curl -s ifconfig.me)
    mkdir -p /etc/ssl/self-signed
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/self-signed/privkey.pem \
        -out /etc/ssl/self-signed/fullchain.pem \
        -subj "/CN=$IP"
    CERT_PATH="/etc/ssl/self-signed/fullchain.pem"
    KEY_PATH="/etc/ssl/self-signed/privkey.pem"
fi

# --- 6. Обновление конфига Nginx: заглушка + прокси для 3x-ui ---
echo -e "${YELLOW}[5/6] Настройка обратного прокси для 3x-ui и заглушки...${NC}"

# Перезаписываем конфиг Nginx
cat > /etc/nginx/sites-available/decoy <<EOF
# HTTP -> HTTPS редирект (только если есть домен и валидный сертификат)
server {
    listen 80;
    listen [::]:80;
    server_name $SERVER_NAME;

    # Оставляем доступ к ACME для обновления сертификатов
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Редирект на HTTPS (если сертификат Let's Encrypt)
    # Если сертификат самоподписанный — можно закомментировать, чтобы не было предупреждений
    # return 301 https://\$host\$request_uri;
    location / {
        root /var/www/decoy;
        index index.html;
    }
}

# HTTPS сервер для сайта-заглушки и проксирования 3x-ui (только localhost:50000)
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

    # Прокси для панели 3x-ui (порт 55000)
    location /panel/ {
        proxy_pass http://127.0.0.1:55000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Прокси для подписок 3x-ui (порт 56000)
    location /sub/ {
        proxy_pass http://127.0.0.1:56000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Проверка и перезагрузка Nginx
nginx -t
systemctl reload nginx

# --- 7. Установка 3x-ui с SQLite и нужными портами ---
echo -e "${YELLOW}[6/6] Установка панели 3x-ui...${NC}"

# Официальный скрипт установки. Передаём переменные окружения для SQLite и портов.
# Панель будет слушать 127.0.0.1:55000 (XUI_PORT), подписка — 127.0.0.1:56000 (XUI_SUB_PORT).
export XUI_DB_TYPE=sqlite
export XUI_DB_FOLDER=/etc/x-ui
export XUI_PORT=55000
export XUI_SUB_PORT=56000
export XUI_INIT_WEB_BASE_PATH=/panel/   # Чтобы панель была доступна по /panel/

bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

# После установки меняем логин и пароль по умолчанию
# (Установщик создаёт случайные, но мы зададим свои)
sleep 5  # ждём запуска
x-ui setting -username "$PANEL_USER" -password "$PANEL_PASS" || {
    echo -e "${YELLOW}Не удалось автоматически сменить логин/пароль. Сделайте это вручную после входа.${NC}"
}

# Перезапускаем 3x-ui, чтобы применились порты (если установщик их не подхватил)
systemctl restart x-ui

# --- Завершение ---
IP=$(curl -s ifconfig.me)
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Установка завершена!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Панель 3x-ui:"
echo -e "  Логин: ${YELLOW}$PANEL_USER${NC}"
echo -e "  Пароль: ${YELLOW}$PANEL_PASS${NC}"
if [ "$USE_DOMAIN" = true ]; then
    echo -e "  Доступ через Nginx (локально): ${YELLOW}http://127.0.0.1:50000/panel/${NC}"
    echo -e "  Внешний доступ (если откроете порт 50000): ${YELLOW}https://$DOMAIN:50000/panel/${NC}"
else
    echo -e "  Доступ через Nginx (локально): ${YELLOW}http://127.0.0.1:50000/panel/${NC}"
    echo -e "  Внешний доступ (если откроете порт 50000): ${YELLOW}https://$IP:50000/panel/${NC}"
fi
echo -e ""
echo -e "${YELLOW}ВАЖНО:${NC}"
echo -e "1. Порт 443 оставлен свободным для VLESS Reality в 3x-ui."
echo -e "2. Зайдите в панель 3x-ui и создайте inbound VLESS Reality на порту 443."
echo -e "3. Для self-steal настройте в inbound 'Fallback' на ваш Nginx (например, 127.0.0.1:50000)."
echo -e "4. Если вы указали домен, не забудьте направить его A-запись на IP: $IP"
echo -e "${GREEN}========================================${NC}"
