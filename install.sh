#!/bin/bash

# Цвета для красивого вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

clear
echo -e "${CYAN}==============================================================${NC}"
echo -e "${GREEN}   Автоматический установщик NaiveProxy by Ilya Rublev   ${NC}"
echo -e "${CYAN}==============================================================${NC}"
echo ""

# Проверка на root-права
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Пожалуйста, запустите скрипт с правами root (sudo -i).${NC}"
  exit 1
fi

# Запрос данных у пользователя
read -p "Введите ваше доменное имя (например, domain.com): " DOMAIN
read -p "Введите ваш email для Let's Encrypt: " EMAIL

echo -e "\n${YELLOW}[1/8] Обновление системы и установка зависимостей...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y
apt install -y wget curl nano ufw tar libcap2-bin

echo -e "\n${YELLOW}[2/8] Оптимизация сети (BBR)...${NC}"
cat << EOF >> /etc/sysctl.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl -p

echo -e "\n${YELLOW}[3/8] Установка Go (Golang)...${NC}"
rm -rf /usr/local/go
wget https://go.dev/dl/go1.22.1.linux-amd64.tar.gz -O /tmp/go.tar.gz
tar -C /usr/local -xzf /tmp/go.tar.gz
rm /tmp/go.tar.gz
export PATH=$PATH:/usr/local/go/bin

echo -e "\n${YELLOW}[4/8] Сборка Caddy с модулем NaiveProxy...${NC}"
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive
chmod +x caddy
mv caddy /usr/bin/
setcap cap_net_bind_service=+ep /usr/bin/caddy

echo -e "\n${YELLOW}[5/8] Настройка среды Caddy...${NC}"
groupadd --system caddy || true
useradd --system --gid caddy --create-home --home-dir /var/lib/caddy --shell /usr/sbin/nologin caddy || true
mkdir -p /etc/caddy

# Генерация логина и пароля (только латиница, > 12 символов)
USERNAME=$(tr -dc 'A-Za-z' < /dev/urandom | head -c 14)
PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 18)

# Создание Caddyfile
cat << EOF > /etc/caddy/Caddyfile
{
    debug
    order forward_proxy before reverse_proxy
}

:443, $DOMAIN {
    tls $EMAIL

    forward_proxy {
        basic_auth $USERNAME $PASSWORD
        hide_ip
        hide_via
        probe_resistance
    }

    reverse_proxy https://kernel.org {
        header_up Host {upstream_hostport}
    }
}
EOF

echo -e "\n${YELLOW}[6/8] Создание системной службы (systemd)...${NC}"
cat << 'EOF' > /etc/systemd/system/caddy.service
[Unit]
Description=Caddy Web Server
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable caddy
systemctl restart caddy

echo -e "\n${YELLOW}[7/8] Настройка Firewall (UFW)...${NC}"
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw --force enable

echo -e "\n${YELLOW}[8/8] Проверка статуса Caddy...${NC}"
sleep 3
if systemctl is-active --quiet caddy; then
    echo -e "${GREEN}Caddy успешно запущен!${NC}"
else
    echo -e "${RED}Внимание: Caddy работает с ошибками. Проверьте логи: journalctl -u caddy --no-pager | tail -n 20${NC}"
fi

echo -e "\n${CYAN}==============================================================${NC}"
echo -e "${GREEN}Установка NaiveProxy успешно завершена!${NC}"
echo -e "${CYAN}==============================================================${NC}"
echo -e "Ваши данные для подключения (используйте их в v2rayN, NekoBox, Shadowrocket):"
echo ""
echo -e "Домен/Сервер: ${GREEN}$DOMAIN${NC}"
echo -e "Ваш логин:    ${YELLOW}$USERNAME${NC}"
echo -e "Ваш пароль:   ${YELLOW}$PASSWORD${NC}"
echo -e "Порт:         ${GREEN}443${NC}"
echo ""
echo -e "Формат JSON для клиента (naive.json):"
echo -e "${CYAN}{\n  \"listen\": \"socks://127.0.0.1:1080\",\n  \"proxy\": \"https://${USERNAME}:${PASSWORD}@${DOMAIN}\"\n}${NC}"
echo -e "${CYAN}==============================================================${NC}"
echo -e "Спасибо, что используете этот скрипт!"
echo -e "Автор: ${GREEN}Ilya Rublev${NC}"
echo -e "ОС: Ubuntu 24.04 LTS"
echo ""
echo -e "Подписывайтесь на мои ресурсы, чтобы не пропустить новые решения:"
echo -e "▶ YouTube:  ${YELLOW}https://www.youtube.com/@Ilya_Rublev${NC}"
echo -e "💎 Boosty:   ${YELLOW}https://boosty.to/rublev13${NC}"
echo -e "✈️ Telegram: ${YELLOW}https://t.me/Rublev_YouTube${NC}"
echo -e "${CYAN}==============================================================${NC}"
