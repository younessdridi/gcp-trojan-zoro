#!/bin/bash
set -euo pipefail

###############################################
#       ZORO CLOUD RUN MULTI-PROTOCOL
#       VLESS – VMESS – TROJAN-WS
#       FULL PROFESSIONAL DEPLOYER
###############################################

# ==== COLORS ====
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[✔]${NC} $1"
}

warn() {
    echo -e "${RED}[!]${NC} $1"
}

###############################################
#              اختيار البروتوكول
###############################################
clear
echo -e "${CYAN}اختـر البروتوكول للإنشاء:${NC}"
echo "1) Trojan-WS"
echo "2) VLESS-WS"
echo "3) VMess-WS"
read -p "➤ اختر رقم (1/2/3): " P

case $P in
1) PROTOCOL="trojan" ;;
2) PROTOCOL="vless" ;;
3) PROTOCOL="vmess" ;;
*) warn "خيار غير صالح"; exit 1 ;;
esac

###############################################
#        جمع معلومات السرفر من المستخدم
###############################################
read -p "➤ اسم السرفر: " SERVER_NAME
read -p "➤ نوع المعالج (مثال: 2 vCPU): " CPU_INFO
read -p "➤ حجم الذاكرة RAM: " RAM_INFO
read -p "➤ وصف السرفر: " SERVER_DESC

###############################################
#           Telegram Bot Config
###############################################
echo "أدخل معلومات Telegram لإرسال رابط السرفر:"
read -p "➤ Bot Token: " BOT_TOKEN
read -p "➤ Admin ID: " ADMIN_ID

UUID=$(cat /proc/sys/kernel/random/uuid)
log "UUID: $UUID"

###############################################
#      إنشاء مجلد التطبيق + ملف config.json
###############################################
mkdir -p app
log "تم إنشاء مجلد التطبيق."

cat <<EOF > app/config.json
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": 8080,
    "listen": "0.0.0.0",
    "protocol": "$PROTOCOL",
    "settings": {
      "clients": [
        { "id": "$UUID", "password": "$UUID" }
      ]
    },
    "streamSettings": {
      "network": "ws",
      "security": "none",
      "wsSettings": { "path": "/zoro" }
    }
  }],
  "outbounds": [{
    "protocol": "freedom"
  }]
}
EOF

log "تم إنشاء config.json بنجاح."

###############################################
#           إنشاء صفحة HTML احترافية
###############################################
cat <<EOF > app/index.html
<html>
<head>
<title>ZORO SERVER</title>
<style>
body {
  background: #000;
  color: #ff0000;
  font-family: Arial;
  text-align: center;
  padding-top: 80px;
}
.logo {
  font-size: 45px;
  text-shadow: 0 0 20px #ff0000;
}
.box {
  background: rgba(255,0,0,0.1);
  padding: 25px;
  border-radius: 15px;
  width: 60%;
  margin: auto;
  box-shadow: 0 0 15px red;
}
</style>
</head>
<body>
<div class="logo">🔥 ZORO SERVER 🔥</div>
<div class="box">
  <h2>السرفر يعمل بنجاح!</h2>
  <p>الاسم: $SERVER_NAME</p>
  <p>الوصف: $SERVER_DESC</p>
  <p>البروتوكول: $PROTOCOL</p>
</div>
</body>
</html>
EOF

log "تم إنشاء صفحة HTML الاحترافية."

###############################################
#       إنشاء Dockerfile لخدمة Cloud Run
###############################################
cat <<EOF > Dockerfile
FROM alpine:3.18

RUN apk add --no-cache curl bash wget unzip

# تثبيت XRay
RUN wget https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip && \
    unzip Xray-linux-64.zip && \
    install -m 755 xray /usr/local/bin/xray

COPY app /app
WORKDIR /app

EXPOSE 8080
CMD ["/usr/local/bin/xray", "-config", "/app/config.json"]
EOF

log "تم إنشاء Dockerfile."

###############################################
#     إظهار رسالة جاهزية وطلب رابط Cloud Run
###############################################
echo ""
warn "🎯 الآن ادخل رابط Cloud Run النهائي بعد نشر المشروع."
read -p "➤ ضع رابط Cloud Run هنا: " CLOUD_URL

###############################################
#           روابط البروتوكولات النهائية
###############################################
if [[ "$PROTOCOL" == "vless" ]]; then
    LINK="vless://$UUID@$CLOUD_URL:443?type=ws&path=/zoro&security=none&host=$CLOUD_URL#ZORO-VLESS"
elif [[ "$PROTOCOL" == "vmess" ]]; then
    JSON="{\"v\":\"2\",\"ps\":\"ZORO-VMESS\",\"add\":\"$CLOUD_URL\",\"port\":\"443\",\"id\":\"$UUID\",\"net\":\"ws\",\"path\":\"/zoro\",\"tls\":\"none\"}"
    BASE64=$(echo -n "$JSON" | base64 -w 0)
    LINK="vmess://$BASE64"
elif [[ "$PROTOCOL" == "trojan" ]]; then
    LINK="trojan://$UUID@$CLOUD_URL:443?type=ws&path=/zoro&host=$CLOUD_URL&security=none#ZORO-TROJAN"
fi

###############################################
#          إرسال الرسالة إلى Telegram
###############################################
MESSAGE="🔥 تم إنشاء سرفر جديد بنجاح
📡 البروتوكول: $PROTOCOL
💠 الاسم: $SERVER_NAME
🧩 UUID: $UUID
⚙ CPU: $CPU_INFO
💾 RAM: $RAM_INFO
📝 الوصف: $SERVER_DESC
🌐 رابط السرفر:
$LINK
"

curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
-d chat_id="$ADMIN_ID" \
-d text="$MESSAGE"

log "✔ تم إرسال رابط السرفر إلى Telegram بنجاح."
log "🎉 السكربت اكتمل بنجاح — كل شيء يعمل بدون مشاكل."
