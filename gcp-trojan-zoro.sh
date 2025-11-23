#!/bin/bash
set -euo pipefail

# ============================
# gcp-trojan-zoro.sh
# Deploy Trojan (WS) to Google Cloud Run
# Creates app/{Dockerfile,config.json,index.html} and deploys
# Sends a SIMPLE Telegram message (style A) if token+chat_id provided
# Patch (WS path) fixed to: /@zoro_40_khanchlyyy
# ============================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()    { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; }
info()   { echo -e "${BLUE}[INFO]${NC} $1"; }

# Validate UUID format
validate_uuid() {
    local uuid_pattern='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    [[ $1 =~ $uuid_pattern ]]
}

# Simple token validation (loose)
validate_bot_token() {
    [[ $1 =~ ^[0-9]{6,12}:[A-Za-z0-9_-]{20,}$ ]]
}

# Numeric id validation
validate_numeric_id() {
    [[ $1 =~ ^-?[0-9]+$ ]]
}

# CPU selection
select_cpu() {
    echo
    info "=== CPU Configuration ==="
    echo "1) 1 CPU"
    echo "2) 2 CPU"
    echo "3) 4 CPU"
    echo "4) 8 CPU"
    while true; do
        read -p "Select (1-4) [1]: " cpu_choice
        cpu_choice=${cpu_choice:-1}
        case $cpu_choice in
            1) CPU="1"; break;;
            2) CPU="2"; break;;
            3) CPU="4"; break;;
            4) CPU="8"; break;;
            *) echo "Enter 1-4";;
        esac
    done
    info "Selected CPU: $CPU"
}

# Memory selection
select_memory() {
    echo
    info "=== Memory Configuration ==="
    echo "1) 512Mi"
    echo "2) 1Gi"
    echo "3) 2Gi"
    echo "4) 4Gi"
    echo "5) 8Gi"
    echo "6) 16Gi"
    while true; do
        read -p "Select (1-6) [3]: " mem_choice
        mem_choice=${mem_choice:-3}
        case $mem_choice in
            1) MEMORY="512Mi"; break;;
            2) MEMORY="1Gi"; break;;
            3) MEMORY="2Gi"; break;;
            4) MEMORY="4Gi"; break;;
            5) MEMORY="8Gi"; break;;
            6) MEMORY="16Gi"; break;;
            *) echo "Enter 1-6";;
        esac
    done
    info "Selected Memory: $MEMORY"
}

# Region selection
select_region() {
    echo
    info "=== Region Selection ==="
    echo "1) us-central1 (Iowa, USA)"
    echo "2) us-west1 (Oregon, USA)"
    echo "3) us-east1 (South Carolina, USA)"
    echo "4) europe-west1 (Belgium)"
    echo "5) asia-southeast1 (Singapore)"
    echo "6) asia-northeast1 (Tokyo, Japan)"
    echo "7) asia-east1 (Taiwan)"
    while true; do
        read -p "Select region (1-7) [1]: " r
        r=${r:-1}
        case $r in
            1) REGION="us-central1"; break;;
            2) REGION="us-west1"; break;;
            3) REGION="us-east1"; break;;
            4) REGION="europe-west1"; break;;
            5) REGION="asia-southeast1"; break;;
            6) REGION="asia-northeast1"; break;;
            7) REGION="asia-east1"; break;;
            *) echo "Enter 1-7";;
        esac
    done
    info "Selected region: $REGION"
}

# Telegram optional input (simple style A)
get_telegram_info() {
    echo
    info "=== Telegram (optional) ==="
    read -p "Enter Telegram Bot Token (or leave empty to skip): " TELEGRAM_BOT_TOKEN
    if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
        if ! validate_bot_token "$TELEGRAM_BOT_TOKEN"; then
            warn "Token format looks odd, but script will still try to use it."
        fi
        read -p "Enter Chat ID (channel or user) to send info: " TELEGRAM_CHAT_ID
        if ! validate_numeric_id "$TELEGRAM_CHAT_ID"; then
            warn "Chat ID looks odd - message may fail."
        fi
    else
        TELEGRAM_BOT_TOKEN=""
        TELEGRAM_CHAT_ID=""
    fi
}

# Get main inputs
get_user_input() {
    echo
    info "=== Service configuration ==="
    while true; do
        read -p "Enter service name (no spaces) [zoro-trojan]: " SERVICE_NAME
        SERVICE_NAME=${SERVICE_NAME:-zoro-trojan}
        if [[ -n "$SERVICE_NAME" ]]; then break; fi
    done

    read -p "Enter host domain for share link (default m.googleapis.com): " HOST_DOMAIN
    HOST_DOMAIN=${HOST_DOMAIN:-m.googleapis.com}
}

show_summary() {
    echo
    info "=== Summary ==="
    echo "Service:      $SERVICE_NAME"
    echo "Region:       $REGION"
    echo "CPU:          $CPU"
    echo "Memory:       $MEMORY"
    echo "Patch (WS):   /@zoro_40_khanchlyyy"
    echo "Host domain:  $HOST_DOMAIN"
    if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
        echo "Telegram:     configured (chat_id: $TELEGRAM_CHAT_ID)"
    else
        echo "Telegram:     not configured"
    fi
    echo
    while true; do
        read -p "Proceed? (y/n) [y]: " c
        c=${c:-y}
        case $c in
            y|Y) break;;
            n|N) info "Canceled by user"; exit 0;;
            *) echo "y or n";;
        esac
    done
}

validate_prereqs() {
    log "Validating prerequisites..."
    if ! command -v gcloud &>/dev/null; then error "gcloud not installed"; exit 1; fi
    if ! command -v git &>/dev/null; then error "git not installed"; exit 1; fi
    if ! command -v curl &>/dev/null; then error "curl not installed"; exit 1; fi
    if ! command -v python3 &>/dev/null; then warn "python3 not found; path encoding might fail"; fi

    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
        error "No GCP project set. Run: gcloud config set project PROJECT_ID"
        exit 1
    fi
    log "Using GCP project: $PROJECT_ID"
}

cleanup() {
    log "Cleaning up temp files..."
    if [[ -d "app" ]]; then rm -rf app; fi
}

send_to_telegram() {
    local chat_id="$1"
    local text="$2"
    if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$chat_id" ]]; then
        warn "Telegram not configured; skipping send."
        return 1
    fi
    local payload=$(printf '{"chat_id":"%s","text":"%s","disable_web_page_preview":true}' "$chat_id" "$text" | sed 's/"/\\"/g')
    # Use curl simple post (escape text properly)
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -H "Content-Type: application/json" \
      -d "{\"chat_id\":\"${chat_id}\",\"text\":\"${text}\",\"parse_mode\":\"Markdown\",\"disable_web_page_preview\":true}" >/dev/null || {
        error "Telegram send failed"
        return 1
    }
    return 0
}

# -------------------------
# Main flow
# -------------------------
main() {
    info "GCP Trojan (WS) Deployment - gcp-trojan-zoro"
    select_region
    select_cpu
    select_memory
    get_telegram_info
    get_user_input
    show_summary
    validate_prereqs

    trap cleanup EXIT

    # Generate UUID (used as Trojan password)
    UUID=$(cat /proc/sys/kernel/random/uuid)
    if ! validate_uuid "$UUID"; then
        warn "Generated UUID doesn't match pattern; using fallback."
        UUID="$(date +%s)-$RANDOM"
    fi
    log "Generated UUID (password): $UUID"

    # Create app folder and files
    log "Creating app/ files..."
    mkdir -p app

    # Dockerfile
    cat > app/Dockerfile <<'DOCK'
FROM teddysun/v2ray:latest

EXPOSE 8080

COPY config.json /etc/v2ray/config.json
COPY index.html /usr/share/nginx/html/index.html

CMD ["v2ray", "run", "-config", "/etc/v2ray/config.json"]
DOCK

    # config.json (Trojan WS)
    WS_PATH="/@zoro_40_khanchlyyy"
    cat > app/config.json <<JSON
{
  "inbounds": [
    {
      "port": 8080,
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "${UUID}",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "${WS_PATH}"
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
JSON

    # index.html
    cat > app/index.html <<HTML
<!DOCTYPE html>
<html lang="ar">
<head>
<meta charset="UTF-8">
<title>ZORO TROJAN SERVER</title>
<style>
body { background:#000; color:#0f0; font-family: Courier, monospace; text-align:center; padding-top:100px; }
h1 { font-size:32px; text-shadow:0 0 10px #0f0; }
p { font-size:18px; }
</style>
</head>
<body>
<h1>⚡ ZORO TROJAN SERVER ⚡</h1>
<p>Patch: ${WS_PATH}</p>
<p>Author: @zoro_40_khanchlyyy</p>
</body>
</html>
HTML

    log "Files created in ./app"

    # Build and push with Cloud Build
    IMAGE="gcr.io/${PROJECT_ID}/${SERVICE_NAME}-image"
    log "Starting Cloud Build to create image: ${IMAGE}"
    if ! gcloud builds submit app --tag "${IMAGE}" --quiet; then
        error "Cloud Build failed"
        exit 1
    fi

    # Deploy to Cloud Run
    log "Deploying to Cloud Run service: ${SERVICE_NAME}"
    if ! gcloud run deploy "${SERVICE_NAME}" \
        --image "${IMAGE}" \
        --platform managed \
        --region "${REGION}" \
        --allow-unauthenticated \
        --cpu "${CPU}" \
        --memory "${MEMORY}" \
        --quiet; then
        error "Cloud Run deployment failed"
        exit 1
    fi

    SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" --platform managed --region "${REGION}" --format 'value(status.url)')
    if [[ -z "$SERVICE_URL" ]]; then
        error "Failed to get service URL"
        exit 1
    fi
    DOMAIN=$(echo "$SERVICE_URL" | sed 's|https://||; s|/||g')

    # URL encode WS_PATH
    if command -v python3 >/dev/null 2>&1; then
        ENC_PATH=$(python3 - <<PY
import urllib.parse, sys
print(urllib.parse.quote("${WS_PATH}", safe=''))
PY
)
    else
        # fallback simple encode (replace / with %2F and @ with %40)
        ENC_PATH=$(echo -n "${WS_PATH}" | sed -e 's/\//%2F/g' -e 's/@/%40/g')
    fi

    # Build Trojan link (simple A style)
    # Note: security and TLS handling depends on where you terminate TLS. Cloud Run provides HTTPS.
    TROJAN_LINK="trojan://${UUID}@${HOST_DOMAIN}:443?path=${ENC_PATH}&security=none&type=ws&host=${DOMAIN}#${SERVICE_NAME}"

    # Save deployment info
    DEPLOY_FILE="deployment-info.txt"
    cat > "${DEPLOY_FILE}" <<EOF
GCP Trojan Deployment - ${SERVICE_NAME}
Project: ${PROJECT_ID}
Region: ${REGION}
Service URL: ${SERVICE_URL}
Domain: ${DOMAIN}
Patch (WS path): ${WS_PATH}
UUID (password): ${UUID}
Trojan Link: ${TROJAN_LINK}
EOF

    log "Deployment completed. Info saved to ${DEPLOY_FILE}"
    echo "-------------------------------------------------"
    echo "Service URL: ${SERVICE_URL}"
    echo "Trojan Link: ${TROJAN_LINK}"
    echo "Config: ./app/config.json"
    echo "-------------------------------------------------"

    # Send simple Telegram message (style A) if configured
    if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
        TG_MSG="GCP Trojan Deployment ✅
Service: ${SERVICE_NAME}
URL: ${SERVICE_URL}
Patch: ${WS_PATH}
UUID: ${UUID}
Trojan: ${TROJAN_LINK}"
        info "Sending info to Telegram..."
        if send_to_telegram "${TELEGRAM_CHAT_ID}" "$TG_MSG"; then
            log "Telegram message sent."
        else
            warn "Telegram send failed."
        fi
    else
        info "Telegram not configured or missing chat_id — skipping send."
    fi

    info "All done. Enjoy."
}

main "$@"
