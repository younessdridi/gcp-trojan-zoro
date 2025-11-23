#!/bin/bash

set -e

GREEN="\e[32m"
CYAN="\e[36m"
RESET="\e[0m"

echo -e "${CYAN}=== ZORO TROJAN CLOUD RUN SETUP ===${RESET}"

# Ask for BOT TOKEN
read -p "أدخل توكن البوت: " BOT_TOKEN

# Ask for ADMIN ID
read -p "أدخل آيدي الأدمن: " ADMIN_ID

# Generate UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
PATCH="/@zoro_40_khanchlyyy"

echo -e "${GREEN}[✔] UUID Generated:${RESET} $UUID"
echo -e "${GREEN}[✔] Patch:${RESET} $PATCH"

# Create project folder
mkdir -p trojan-zoro
cd trojan-zoro

####################################
# 1. Create config.json
####################################
cat > config.json <<EOF
{
  "inbounds": [
    {
      "port": 8080,
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "$UUID",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "$PATCH"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

####################################
# 2. Create Professional HTML Page
####################################
mkdir -p html

cat > html/index.html <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>ZORO VIP TROJAN SERVER</title>
<style>
body{
  margin:0;
  padding:0;
  background:#000;
  color:#fff;
  font-family:Arial;
  text-align:center;
}
.header{
  margin-top:80px;
  font-size:40px;
  font-weight:bold;
  color:#ff0000;
  text-shadow:0 0 15px red;
}
.logo{
  margin-top:40px;
}
</style>
</head>
<body>
<div class="header">ZORO TROJAN SERVER</div>
<div class="logo">
<img src="https://i.postimg.cc/HsdfyCW7/ZORO-LOGO.png" width="200">
</div>
<p>Powered by ZORO</p>
</body>
</html>
EOF

####################################
# 3. Dockerfile
####################################
cat > Dockerfile <<EOF
FROM teddysun/v2ray:latest
EXPOSE 8080

COPY config.json /etc/v2ray/config.json
COPY html /var/www/html

CMD ["v2ray", "run", "-config", "/etc/v2ray/config.json"]
EOF

####################################
# 4. Collect System Info
####################################
CPU=$(lscpu | grep "Model name" | awk -F ':' '{print $2}')
RAM=$(free -h | grep Mem | awk '{print $2}')
DISK=$(df -h / | awk 'NR==2 {print $2}')
IP=$(curl -s ifconfig.me)
OS=$(hostnamectl | grep "Operating System" | awk -F ':' '{print $2}')

####################################
# 5. Send Info to Telegram
####################################
MESSAGE="🔥 *ZORO TROJAN DEPLOYED* 🔥

*UUID:* \`${UUID}\`
*Patch:* ${PATCH}

*CPU:* ${CPU}
*RAM:* ${RAM}
*Disk:* ${DISK}
*IP:* ${IP}
*System:* ${OS}

استعمل السكريبت في Cloud Run"

curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
-d chat_id="${ADMIN_ID}" \
-d text="${MESSAGE}" \
-d parse_mode="Markdown"

####################################
# 6. Deploy Cloud Run
####################################
gcloud run deploy zoro-trojan --source . --region us-central1 --platform managed --allow-unauthenticated

URL=$(gcloud run services describe zoro-trojan --region us-central1 --format 'value(status.url)')

####################################
# 7. Generate Trojan Link
####################################
TROJAN_LINK="trojan://${UUID}@${URL}:443?path=$(echo -n $PATCH | sed 's/\//%2F/g')&security=none&type=ws&host=${URL/#https:\/\//}#ZORO-TROJAN"

echo -e "${GREEN}=== READY ===${RESET}"
echo "$TROJAN_LINK"

echo -e "${GREEN}تم إرسال جميع المعلومات إلى البوت ✔${RESET}"
