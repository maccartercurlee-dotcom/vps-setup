#!/bin/bash
set -e
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
clear
echo -e "${GREEN}=== УСТАНОВКА VPN (ПРАВИЛЬНЫЕ JSON) ===${NC}"
read -p "Домен (agema1979.ru): " RAW_DOMAIN
DOMAIN=$(echo "$RAW_DOMAIN" | tr -cd 'a-zA-Z0-9.-')
[ -z "$DOMAIN" ] && { echo "Домен пуст"; exit 1; }
echo -e "${YELLOW}Протоколы (1=VLESS, 2=Hysteria, '1 2'=оба) [1 2]:${NC}"
read -p "Выбор: " PROTOCOLS
[ -z "$PROTOCOLS" ] && PROTOCOLS="1 2"

PANEL_USER="admin"
PANEL_PASS="admin"
WEB_PATH="/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)/"
SUB_PATH="/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)/"
PANEL_PORT=2053
SUB_PORT=2096
NGINX_PORT="40000"

ufw --force disable >/dev/null 2>&1 || true
systemctl stop x-ui nginx >/dev/null 2>&1 || true
apt purge -y nginx nginx-common nginx-core nginx-full >/dev/null 2>&1 || true
rm -rf /etc/x-ui /usr/local/x-ui /usr/bin/x-ui /etc/systemd/system/x-ui.service /etc/nginx /var/www/decoy /var/www/certbot
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y nginx certbot curl wget sqlite3 openssl python3

echo -e "${YELLOW}Установка 3x-ui...${NC}"
wget -qO /tmp/xui-install.sh https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh
printf "1\nn\n4\ny\n" | bash /tmp/xui-install.sh
sleep 7

systemctl start x-ui
sleep 4
systemctl stop x-ui

mkdir -p /var/www/decoy /var/www/certbot
echo '<h1>Welcome</h1>' > /var/www/decoy/index.html
CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

echo -e "${YELLOW}Получаем сертификат...${NC}"
cat > /etc/nginx/sites-available/decoy <<EOF
server {
    listen 80; server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { root /var/www/decoy; index index.html; }
}
EOF
ln -sf /etc/nginx/sites-available/decoy /etc/nginx/sites-enabled/decoy
systemctl restart nginx
certbot certonly --webroot -w /var/www/certbot -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" || true

if [ ! -f "$CERT_PATH" ]; then
  mkdir -p /etc/ssl/self-signed
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/self-signed/privkey.pem -out /etc/ssl/self-signed/fullchain.pem -subj "/CN=$DOMAIN"
  CERT_PATH="/etc/ssl/self-signed/fullchain.pem"
  KEY_PATH="/etc/ssl/self-signed/privkey.pem"
fi

export DB_DOMAIN="$DOMAIN" DB_PANEL_PORT="$PANEL_PORT" DB_WEB_PATH="$WEB_PATH"
export DB_SUB_PORT="$SUB_PORT" DB_SUB_PATH="$SUB_PATH" DB_CERT_PATH="$CERT_PATH"
export DB_KEY_PATH="$KEY_PATH" DB_PROTOCOLS="$PROTOCOLS"

echo -e "${YELLOW}Заполнение базы (с полными JSON)...${NC}"
python3 << 'PYEOF'
import os, sqlite3, json, secrets, uuid, subprocess, time
DOMAIN=os.environ['DB_DOMAIN']; PANEL_PORT=os.environ['DB_PANEL_PORT']
WEB_PATH=os.environ['DB_WEB_PATH']; SUB_PORT=os.environ['DB_SUB_PORT']
SUB_PATH=os.environ['DB_SUB_PATH']; CERT_PATH=os.environ['DB_CERT_PATH']
KEY_PATH=os.environ['DB_KEY_PATH']; PROTOCOLS=os.environ['DB_PROTOCOLS'].split()
conn=sqlite3.connect('/etc/x-ui/x-ui.db'); c=conn.cursor(); now=int(time.time()*1000)

c.execute("DELETE FROM client_inbounds"); c.execute("DELETE FROM client_traffics")
c.execute("DELETE FROM clients"); c.execute("DELETE FROM inbounds"); c.execute("DELETE FROM settings")

settings = [
    ('webPort', str(PANEL_PORT)), ('webBasePath', WEB_PATH), ('webListen', '127.0.0.1'),
    ('subPort', str(SUB_PORT)), ('subPath', SUB_PATH), ('subListen', '127.0.0.1'),
    ('subEnable', 'true'), ('subDomain', DOMAIN), ('subURI', f"https://{DOMAIN}{SUB_PATH}"),
]
for k,v in settings: c.execute("INSERT INTO settings (key, value) VALUES (?, ?)", (k,v))

names=["zfold","passwall","work","TV","note10"]
cd=[{"name":n,"uuid":str(uuid.uuid4()),"sub":secrets.token_hex(8)} for n in names]

xb=subprocess.check_output("find /usr/local/x-ui/bin/ -name 'xray*' -type f | head -n 1",shell=True).decode().strip()
k=subprocess.check_output(f"{xb} x25519",shell=True).decode()
pk=[l.split()[-1] for l in k.split('\n') if 'Private' in l][0]
pub=[l.split()[-1] for l in k.split('\n') if 'Password' in l or 'Public' in l][0]

vless_id=None; hy_id=None

# --- VLESS REALITY ---
if "1" in PROTOCOLS:
    shorts=[secrets.token_hex(n)[:n] for n in [8,2,10,6,14,4,12,16]]
    spider="/"+secrets.token_urlsafe(10)[:15]
    vc=[{"id":x["uuid"],"email":x["name"],"subId":x["sub"],"flow":"","security":"auto","limitIp":0,"totalGB":0,"expiryTime":0,"enable":True,"tgId":0,"reset":0,"resetDay":0,"resetWeekday":0,"resetMax":0,"comment":"","created_at":now,"updated_at":now} for x in cd]
    
    vless_settings = {"clients": vc, "decryption": "none", "encryption": "none"}
    
    vless_stream = {
        "network": "xhttp",
        "xhttpSettings": {
            "path": "/api/v3/stream", "host": "", "mode": "stream-one",
            "xPaddingBytes": "100-1000", "xPaddingObfsMode": False, "xPaddingKey": "",
            "xPaddingHeader": "", "xPaddingPlacement": "", "xPaddingMethod": "",
            "sessionIDPlacement": "", "sessionIDKey": "", "sessionIDTable": "",
            "sessionIDLength": "", "seqPlacement": "", "seqKey": "",
            "uplinkDataPlacement": "", "uplinkDataKey": "", "scMaxEachPostBytes": "",
            "noSSEHeader": False, "scMaxBufferedPosts": 30, "scStreamUpServerSecs": "20-80",
            "serverMaxHeaderBytes": 0, "uplinkHTTPMethod": "", "headers": {},
            "scMinPostsIntervalMs": "", "uplinkChunkSize": 0, "noGRPCHeader": False,
            "enableXmux": False
        },
        "security": "reality",
        "realitySettings": {
            "show": False, "xver": 0, "target": "127.0.0.1:40000",
            "serverNames": [DOMAIN], "privateKey": pk,
            "minClientVer": "", "maxClientVer": "", "maxTimediff": 0,
            "shortIds": shorts, "mldsa65Seed": "",
            "settings": {
                "publicKey": pub, "fingerprint": "firefox",
                "serverName": "", "spiderX": spider, "mldsa65Verify": ""
            }
        },
        "sockopt": {
            "tcpFastOpen": True, "tcpcongestion": "bbr", "acceptProxyProtocol": False,
            "mark": 0, "tproxy": "off", "tcpMptcp": False, "penetrate": False,
            "domainStrategy": "AsIs", "tcpMaxSeg": 0, "dialerProxy": "",
            "tcpKeepAliveInterval": 0, "tcpKeepAliveIdle": 0, "tcpUserTimeout": 0,
            "V6Only": False, "tcpWindowClamp": 0, "interface": "",
            "trustedXForwardedFor": [], "addressPortStrategy": "none", "customSockopt": []
        }
    }
    c.execute("INSERT INTO inbounds (user_id,up,down,total,expiry_time,remark,port,protocol,settings,stream_settings,tag,sniffing,enable) VALUES (1,0,0,0,0,'VLESS-REALITY',443,'vless',?,?,'in-443-tcp',?,1)",(json.dumps(vless_settings),json.dumps(vless_stream),'{"enabled":true,"destOverride":["http","tls","quic","fakedns"]}'))
    vless_id=c.lastrowid

# --- Hysteria2 ---
if "2" in PROTOCOLS:
    hc=[{"id":x["uuid"],"email":x["name"],"subId":x["sub"],"auth":x["uuid"],"password":x["uuid"],"flow":"","security":"auto","limitIp":0,"totalGB":0,"expiryTime":0,"enable":True,"tgId":0,"reset":0,"resetDay":0,"resetWeekday":0,"resetMax":0,"comment":"","created_at":now,"updated_at":now} for x in cd]
    
    hy_settings = {"clients": hc, "version": 2}
    
    hy_stream = {
        "network": "hysteria",
        "hysteriaSettings": {
            "version": 2, "udpIdleTimeout": 60,
            "masquerade": {"type": "proxy", "url": f"https://{DOMAIN}/", "rewriteHost": True}
        },
        "security": "tls",
        "tlsSettings": {
            "serverName": DOMAIN, "minVersion": "1.3", "maxVersion": "1.3",
            "certificates": [{"certificateFile": CERT_PATH, "keyFile": KEY_PATH, "useFile": True}],
            "alpn": ["h3"],
            "settings": {"fingerprint": "firefox", "echConfigList": "", "echServerKeys": ""}
        },
        "finalmask": {
            "quicParams": {
                "congestion": "bbr", "debug": False, "maxIdleTimeout": 30,
                "keepAlivePeriod": 10, "disablePathMTUDiscovery": False,
                "maxIncomingStreams": 2048, "initStreamReceiveWindow": 16777216,
                "maxStreamReceiveWindow": 16777216, "initConnectionReceiveWindow": 33554432,
                "maxConnectionReceiveWindow": 33554432, "bbrProfile": "aggressive"
            }
        }
    }
    c.execute("INSERT INTO inbounds (user_id,up,down,total,expiry_time,remark,port,protocol,settings,stream_settings,tag,sniffing,enable) VALUES (1,0,0,0,0,'Hysteria2',443,'hysteria',?,?,'in-443-udp',?,1)",(json.dumps(hy_settings),json.dumps(hy_stream),'{"enabled":true,"destOverride":["http","tls"]}'))
    hy_id=c.lastrowid

first_inb = vless_id if vless_id else hy_id
for x in cd:
    c.execute("INSERT INTO clients (email,sub_id,uuid,password,auth,flow,security,limit_ip,total_gb,expiry_time,enable,tg_id,comment,reset,group_name,created_at,updated_at) VALUES (?,?,?,?,?,'','auto',0,0,0,1,0,'',0,'',?,?)",(x["name"],x["sub"],x["uuid"],x["uuid"],x["uuid"],now,now))
    cid=c.lastrowid
    for iid in (vless_id,hy_id):
        if iid is None: continue
        c.execute("INSERT INTO client_inbounds (client_id,inbound_id,flow_override,created_at) VALUES (?,?,'',?)",(cid,iid,now))
    c.execute("INSERT INTO client_traffics (inbound_id,enable,email,up,down,expiry_time,total,reset,last_online) VALUES (?,1,?,0,0,0,0,0,0)",(first_inb,x["name"]))

tmpl={"log":{"loglevel":"warning"},"api":{"services":["HandlerService","LoggerService","StatsService","RoutingService"],"tag":"api"},"stats":{},"policy":{"levels":{"0":{"statsUserUplink":True,"statsUserDownlink":True,"statsUserOnline":True}},"system":{"statsInboundUplink":True,"statsInboundDownlink":True,"statsOutboundUplink":True,"statsOutboundDownlink":True}},"inbounds":[{"listen":"127.0.0.1","port":62789,"protocol":"dokodemo-door","settings":{"address":"127.0.0.1"},"tag":"api","sniffing":{"enabled":False}}],"outbounds":[{"protocol":"freedom","tag":"direct"},{"protocol":"blackhole","tag":"blocked"}],"routing":{"domainStrategy":"AsIs","rules":[{"type":"field","inboundTag":["api"],"outboundTag":"api"},{"type":"field","ip":["geoip:private"],"outboundTag":"blocked"}]}}
c.execute("INSERT INTO settings (key, value) VALUES ('xrayTemplateConfig', ?)",(json.dumps(tmpl),))

conn.commit(); conn.close()
print("DB OK")
PYEOF

if echo "$PROTOCOLS" | grep -qw "1"; then
  LISTEN="listen 127.0.0.1:${NGINX_PORT} ssl http2;"
else
  LISTEN="listen 443 ssl http2;"
fi
cat > /etc/nginx/sites-available/decoy <<NGINXEOF
server {
    listen 80; server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$host\$request_uri; }
}
server {
    $LISTEN
    server_name $DOMAIN;
    ssl_certificate     $CERT_PATH;
    ssl_certificate_key $KEY_PATH;
    ssl_protocols       TLSv1.2 TLSv1.3;
    location / { root /var/www/decoy; index index.html; }
    location $WEB_PATH { proxy_pass http://127.0.0.1:$PANEL_PORT; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$scheme; proxy_read_timeout 86400; }
    location $SUB_PATH { proxy_pass http://127.0.0.1:$SUB_PORT; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$scheme; }
}
NGINXEOF
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/decoy /etc/nginx/sites-enabled/decoy
nginx -t && systemctl restart nginx
systemctl start x-ui
sleep 3
x-ui setting -username "$PANEL_USER" -password "$PANEL_PASS" >/dev/null 2>&1 || true
systemctl restart x-ui
sleep 3
echo ""
echo -e "${GREEN}=== ГОТОВО ===${NC}"
echo "Логин: $PANEL_USER | Пароль: $PANEL_PASS"
echo "Панель:   https://$DOMAIN$WEB_PATH"
echo "Подписки: https://$DOMAIN$SUB_PATH"
echo ""
x-ui status
echo ""
ss -tlnp | grep -E ':(443|40000)\b' || true
echo ""
sqlite3 /etc/x-ui/x-ui.db "SELECT id,remark,port,protocol FROM inbounds;"
echo ""
echo "--- Тест Fallback ---"
curl -kI "https://$DOMAIN/" 2>&1 | head -n 3
echo ""
echo "--- Тест Панели ---"
curl -kI "https://$DOMAIN$WEB_PATH" 2>&1 | head -n 3
