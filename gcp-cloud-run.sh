#!/bin/bash

set -euo pipefail

# --- Configuration Constants ---
DEFAULT_DEPLOY_DURATION="5h" # ၅ နာရီ (MST တွက်တွက်ရန် အသုံးပြုသည်။)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Region list for selection
declare -A REGIONS=(
    [1]="us-central1|Iowa, USA|🇺🇸"
    [2]="us-west1|Oregon, USA|🇺🇸"
    [3]="us-east1|South Carolina, USA|🇺🇸"
    [4]="europe-west1|Belgium|🇧🇪"
    [5]="asia-southeast1|Singapore|🇸🇬"
    [6]="asia-southeast2|Indonesia|🇮🇩"
    [7]="asia-northeast1|Tokyo, Japan|🇯🇵"
    [8]="asia-east1|Taiwan|🇹🇼"
    [9]="australia-southeast1|Sydney, Australia|🇦🇺"
    [10]="southamerica-east1|São Paulo, Brazil|🇧🇷"
    [11]="northamerica-northeast1|Montreal, Canada|🇨🇦"
    [12]="africa-south1|Johannesburg, South Africa|🇿🇦"
    [13]="asia-south1|Mumbai, India|🇮🇳"
)

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

validate_uuid() {
    local uuid_pattern='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    if [[ ! $1 =~ $uuid_pattern ]]; then
        error "Invalid UUID format: $1"
        return 1
    fi
    return 0
}

validate_bot_token() {
    local token_pattern='^[0-9]{8,10}:[a-zA-Z0-9_-]{35,45}$'
    if [[ ! $1 =~ $token_pattern ]]; then
        error "Invalid Telegram Bot Token format"
        return 1
    fi
    return 0
}

validate_ids() {
    local ids="$1"
    if [[ ! $ids =~ ^-?[0-9]+(,-?[0-9]+)*$ ]]; then
        error "Invalid ID format: Please use comma-separated numbers (e.g., -1001234567,123456)"
        return 1
    fi
    return 0
}

validate_url() {
    local url="$1"
    local url_pattern='^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/[a-zA-Z0-9._~:/?#[\]@!$&'"'"'()*+,;=-]*)?$'
    local telegram_pattern='^https?://t\.me/[a-zA-Z0-9_]+$'
    if [[ "$url" =~ $telegram_pattern ]]; then
        return 0
    elif [[ "$url" =~ $url_pattern ]]; then
        return 0
    else
        error "Invalid URL format: $url"
        error "Please use a valid URL format like:"
        error "  - https://t.me/channel_name"
        error "  - https://example.com"
        return 1
    fi
}

select_cpu() {
    echo
    info "=== CPU Configuration ==="
    echo "1. 1 CPU Core (Default)"
    echo "2. 2 CPU Cores"
    echo "3. 4 CPU Cores"
    echo "4. 8 CPU Cores"
    echo
    while true; do
        read -p "Select CPU cores (1-4): " cpu_choice
        case $cpu_choice in
            1) CPU="1"; break ;;
            2) CPU="2"; break ;;
            3) CPU="4"; break ;;
            4) CPU="8"; break ;;
            *) echo "Invalid selection. Please enter a number between 1-4." ;;
        esac
    done
    info "Selected CPU: $CPU core(s)"
}

select_memory() {
    echo
    info "=== Memory Configuration ==="
    case $CPU in
        1) echo "Recommended memory: 512Mi - 2Gi" ;;
        2) echo "Recommended memory: 1Gi - 4Gi" ;;
        4) echo "Recommended memory: 2Gi - 8Gi" ;;
        8) echo "Recommended memory: 4Gi - 16Gi" ;;
    esac
    echo
    echo "Memory Options:"
    echo "1. 512Mi"
    echo "2. 1Gi"
    echo "3. 2Gi"
    echo "4. 4Gi"
    echo "5. 8Gi"
    echo "6. 16Gi"
    echo

    while true; do
        read -p "Select memory (1-6): " memory_choice
        case $memory_choice in
            1) MEMORY="512Mi"; break ;;
            2) MEMORY="1Gi"; break ;;
            3) MEMORY="2Gi"; break ;;
            4) MEMORY="4Gi"; break ;;
            5) MEMORY="8Gi"; break ;;
            6) MEMORY="16Gi"; break ;;
            *) echo "Invalid selection. Please enter a number between 1-6." ;;
        esac
    done
    validate_memory_config
    info "Selected Memory: $MEMORY"
}

validate_memory_config() {
    local cpu_num=$CPU
    local memory_num=$(echo $MEMORY | sed 's/[^0-9]*//g')
    local memory_unit=$(echo $MEMORY | sed 's/[0-9]*//g')
    if [[ "$memory_unit" == "Gi" ]]; then
        memory_num=$((memory_num * 1024))
    fi
    local min_memory=0
    local max_memory=0
    case $cpu_num in
        1)
            min_memory=512
            max_memory=2048
            ;;
        2)
            min_memory=1024
            max_memory=4096
            ;;
        4)
            min_memory=2048
            max_memory=8192
            ;;
        8)
            min_memory=4096
            max_memory=16384
            ;;
    esac
    if [[ $memory_num -lt $min_memory ]]; then
        warn "Memory configuration ($MEMORY) might be too low for $CPU CPU core(s)."
        warn "Recommended minimum: $((min_memory / 1024))Gi"
        read -p "Do you want to continue with this configuration? (y/n): " confirm
        if [[ ! $confirm =~ [Yy] ]]; then
            select_memory
        fi
    elif [[ $memory_num -gt $max_memory ]]; then
        warn "Memory configuration ($MEMORY) might be too high for $CPU CPU core(s)."
        warn "Recommended maximum: $((max_memory / 1024))Gi"
        read -p "Do you want to continue with this configuration? (y/n): " confirm
        if [[ ! $confirm =~ [Yy] ]]; then
            select_memory
        fi
    fi
}

select_region() {
    echo
    info "=== Region Selection ==="
    local keys=($(for k in "${!REGIONS[@]}"; do echo $k; done | sort -n))
    local count=1
    for key in "${keys[@]}"; do
        IFS='|' read -r region_id region_name flag <<< "${REGIONS[$key]}"
        echo "$key. $region_id ($region_name)"
    done
    echo
    while true; do
        read -p "Select region (1-${#REGIONS[@]}): " region_choice
        if [[ -v REGIONS[$region_choice] ]]; then
            IFS='|' read -r REGION REGION_NAME FLAG_EMOJI <<< "${REGIONS[$region_choice]}"
            break
        else
            echo "Invalid selection. Please enter a number between 1-${#REGIONS[@]}."
        fi
    done
    info "Selected region: $REGION ($REGION_NAME)"
}

select_telegram_destination() {
    echo
    info "=== Telegram Destination ==="
    echo "1. Send to Channel(s) only"
    echo "2. Send to Bot private message(s) only"
    echo "3. Send to both Channel(s) and Bot"
    echo "4. Don't send to Telegram"
    echo
    while true; do
        read -p "Select destination (1-4): " telegram_choice
        case $telegram_choice in
            1)
                TELEGRAM_DESTINATION="channel"
                while true; do
                    read -p "Enter Telegram Channel ID(s) (comma-separated if multiple): " TELEGRAM_CHANNEL_ID
                    if validate_ids "$TELEGRAM_CHANNEL_ID"; then
                        break
                    fi
                done
                break ;;
            2)
                TELEGRAM_DESTINATION="bot"
                while true; do
                    read -p "Enter your Chat ID(s) (comma-separated if multiple, for bot private message): " TELEGRAM_CHAT_ID
                    if validate_ids "$TELEGRAM_CHAT_ID"; then
                        break
                    fi
                done
                break ;;
            3)
                TELEGRAM_DESTINATION="both"
                while true; do
                    read -p "Enter Telegram Channel ID(s) (comma-separated if multiple): " TELEGRAM_CHANNEL_ID
                    if validate_ids "$TELEGRAM_CHANNEL_ID"; then
                        break
                    fi
                done
                while true; do
                    read -p "Enter your Chat ID(s) (comma-separated if multiple, for bot private message): " TELEGRAM_CHAT_ID
                    if validate_ids "$TELEGRAM_CHAT_ID"; then
                        break
                    fi
                done
                break ;;
            4)
                TELEGRAM_DESTINATION="none"
                break ;;
            *) echo "Invalid selection. Please enter a number between 1-4." ;;
        esac
    done
}

get_channel_url() {
    echo
    info "=== Channel URL Configuration ==="
    echo "Default URL: https://t.me/zero_1101_tg"
    echo "You can use the default URL or enter your own custom URL."
    echo
    while true; do
        read -p "Enter Channel URL [default: https://t.me/zero_1101_tg]: " CHANNEL_URL
        CHANNEL_URL=${CHANNEL_URL:-"https://t.me/zero_1101_tg"}
        CHANNEL_URL=$(echo "$CHANNEL_URL" | sed 's|/*$||')
        if validate_url "$CHANNEL_URL"; then
            break
        else
            warn "Please enter a valid URL"
        fi
    done
    if [[ "$CHANNEL_URL" == *"t.me/"* ]]; then
        CHANNEL_NAME=$(echo "$CHANNEL_URL" | sed 's|.*t.me/||' | sed 's|/*$||')
    else
        CHANNEL_NAME=$(echo "$CHANNEL_URL" | sed 's|.*://||' | sed 's|/.*||' | sed 's|www\.||')
    fi
    if [[ -z "$CHANNEL_NAME" ]]; then
        CHANNEL_NAME="1101 Channel"
    fi
    if [[ ${#CHANNEL_NAME} -gt 20 ]]; then
        CHANNEL_NAME="${CHANNEL_NAME:0:17}..."
    fi
    info "Channel URL: $CHANNEL_URL"
    info "Channel Name: $CHANNEL_NAME"
}

get_user_input() {
    echo
    info "=== Service Configuration ==="
    while true; do
        read -p "Enter service name: " SERVICE_NAME
        if [[ -n "$SERVICE_NAME" ]]; then
            break
        else
            error "Service name cannot be empty"
        fi
    done
    while true; do
        read -p "Enter UUID [default: 5652a909-a0b4-48dd-ae29-972757489bf0]: " UUID_INPUT
        UUID=${UUID_INPUT:-"5652a909-a0b4-48dd-ae29-972757489bf0"}
        if validate_uuid "$UUID"; then
            break
        fi
    done
    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        while true; do
            read -p "Enter Telegram Bot Token: " TELEGRAM_BOT_TOKEN
            if validate_bot_token "$TELEGRAM_BOT_TOKEN"; then
                break
            fi
        done
        get_channel_url
    fi
    read -p "Enter host domain [default: m.googleapis.com]: " HOST_DOMAIN
    HOST_DOMAIN=${HOST_DOMAIN:-"m.googleapis.com"}
    info "Default Deployment Duration is set to $DEFAULT_DEPLOY_DURATION (for expiry time calculation)."
}

show_config_summary() {
    echo
    info "=== Configuration Summary ==="
    echo "Project ID:    $(gcloud config get-value project)"
    echo "Region:        ${FLAG_EMOJI} $REGION ($REGION_NAME)"
    echo "Service Name:  $SERVICE_NAME"
    echo "Host Domain:   $HOST_DOMAIN"
    echo "UUID:          $UUID"
    echo "CPU:           $CPU core(s)"
    echo "Memory:        $MEMORY"
    echo "Duration:      $DEFAULT_DEPLOY_DURATION (Calculated)"
    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        echo "Bot Token:     ${TELEGRAM_BOT_TOKEN:0:8}..."
        echo "Destination:   $TELEGRAM_DESTINATION"
        if [[ "$TELEGRAM_DESTINATION" == "channel" || "$TELEGRAM_DESTINATION" == "both" ]]; then
            echo "Channel ID(s): $TELEGRAM_CHANNEL_ID"
        fi
        if [[ "$TELEGRAM_DESTINATION" == "bot" || "$TELEGRAM_DESTINATION" == "both" ]]; then
            echo "Chat ID(s):    $TELEGRAM_CHAT_ID"
        fi
        echo "Channel URL:   $CHANNEL_URL"
        echo "Button Text:   $CHANNEL_NAME"
    else
        echo "Telegram:      Not configured"
    fi
    echo
    while true; do
        read -p "Proceed with deployment? (y/n): " confirm
        case $confirm in
            [Yy]* ) break;;
            [Nn]* )
                info "Deployment cancelled by user"
                exit 0
                ;;
            * ) echo "Please answer yes (y) or no (n).";;
        esac
    done
}

validate_prerequisites() {
    log "Validating prerequisites..."
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    if ! command -v git &> /dev/null; then
        error "git is not installed. Please install git."
        exit 1
    fi
    local PROJECT_ID=$(gcloud config get-value project)
    if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
        error "No project configured. Run: gcloud config set project PROJECT_ID"
        exit 1
    fi
}

cleanup() {
    log "Cleaning up temporary files..."
    if [[ -d "gcp-v2ray" ]]; then
        rm -rf gcp-v2ray
    fi
}

send_to_telegram() {
    local chat_id="$1"
    local message="$2"
    local response
    local keyboard=$(cat << EOF
{
    "inline_keyboard": [[
        {
            "text": "🔗 zero_1101_tg",
            "url": "$CHANNEL_URL"
        }
    ]]
}
EOF
)
    response=$(curl -s -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "{
            \"chat_id\": \"${chat_id}\",
            \"text\": \"$message\",
            \"parse_mode\": \"MARKDOWN\",
            \"disable_web_page_preview\": true,
            \"reply_markup\": $keyboard
        }" \
        https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage)
    local http_code="${response: -3}"
    local content="${response%???}"
    if [[ "$http_code" == "200" ]]; then
        return 0
    else
        error "Failed to send to Telegram (HTTP $http_code) for chat ID $chat_id: $content"
        return 1
    fi
}

send_deployment_notification() {
    local message="$1"
    local success_count=0
    case $TELEGRAM_DESTINATION in
        "channel"|"both")
            log "Sending to Telegram Channel(s)..."
            IFS=',' read -r -a CHANNEL_IDS <<< "$TELEGRAM_CHANNEL_ID"
            for id in "${CHANNEL_IDS[@]}"; do
                if send_to_telegram "$id" "$message"; then
                    log "✅ Successfully sent to Telegram Channel ID: $id"
                    success_count=$((success_count + 1))
                else
                    error "❌ Failed to send to Telegram Channel ID: $id"
                fi
            done
            ;;
    esac
    case $TELEGRAM_DESTINATION in
        "bot"|"both")
            log "Sending to Bot private message(s)..."
            IFS=',' read -r -a CHAT_IDS <<< "$TELEGRAM_CHAT_ID"
            for id in "${CHAT_IDS[@]}"; do
                if send_to_telegram "$id" "$message"; then
                    log "✅ Successfully sent to Bot private message ID: $id"
                    success_count=$((success_count + 1))
                else
                    error "❌ Failed to send to Bot private message ID: $id"
                fi
            done
            ;;
    esac
    if [[ $success_count -gt 0 ]]; then
        log "Telegram notification completed ($success_count successful)"
        return 0
    else
        warn "All Telegram notifications failed, but deployment was successful"
        return 1
    fi
}

main() {
    info "=== GCP Cloud Run V2Ray Deployment ==="

    select_region
    select_cpu
    select_memory
    select_telegram_destination
    get_user_input
    show_config_summary

    PROJECT_ID=$(gcloud config get-value project)

    log "Starting Cloud Run deployment..."

    validate_prerequisites

    trap cleanup EXIT

    log "Enabling required APIs..."
    gcloud services enable \
        cloudbuild.googleapis.com \
        run.googleapis.com \
        iam.googleapis.com \
        --quiet

    cleanup

    log "Cloning repository..."
    if ! git clone https://github.com/KaungSattKyaw/gcp-v2ray.git; then
        error "Failed to clone repository"
        exit 1
    fi

    cd gcp-v2ray

    log "Building container image..."
    if ! gcloud builds submit --tag gcr.io/${PROJECT_ID}/gcp-v2ray-image --quiet; then
        error "Build failed"
        exit 1
    fi

    log "Deploying to Cloud Run..."
    if ! gcloud run deploy ${SERVICE_NAME} \
        --image gcr.io/${PROJECT_ID}/gcp-v2ray-image \
        --platform managed \
        --region ${REGION} \
        --allow-unauthenticated \
        --cpu ${CPU} \
        --memory ${MEMORY} \
        --quiet; then
        error "Deployment failed"
        exit 1
    fi

    SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} \
        --region ${REGION} \
        --format 'value(status.url)' \
        --quiet)

    DOMAIN=$(echo $SERVICE_URL | sed 's|https://||')

    # --- TIMING CALCULATIONS (မြန်မာစံတော်ချိန်) --- (FIXED)
    export TZ='Asia/Yangon'
    now_epoch=$(date +%s)
    start_time=$(date -d @$now_epoch +"%b %d, %I:%M %p (MST)")
    expiry_epoch=$((now_epoch + 5*3600))
    expiry_time=$(date -d @$expiry_epoch +"%b %d, %I:%M %p (MST)")
    unset TZ

    # Create Vless share link
    VLESS_LINK="vless://${UUID}@${HOST_DOMAIN}:443?path=%2Ftgkmks26381Mr&security=tls&alpn=none&encryption=none&host=${DOMAIN}&type=ws&sni=${DOMAIN}#${SERVICE_NAME}"

    MESSAGE="
🚀 *GCP Mytel  Bypass Deployment Successful* 🚀
━━━━━━━━━━━━━━━━━━━━
📅 *စတင်ချိန်:* \`${start_time}\`
⏱️ *ပြီးဆုံးမည့်အချိန်:* \`${expiry_time}\` 
━━━━━━━━━━━━━━━━━━━━
✨ *Deployment Details*
*Service:* \`${SERVICE_NAME}\`
*Region:* \`${FLAG_EMOJI} ${REGION} (${REGION_NAME})\`
*Resources:* \`${CPU} CPU | ${MEMORY} RAM\`
*Domain:* \`${DOMAIN}\`
━━━━━━━━━━━━━━━━━━━━
🔗 *Configuration Link (Click to copy):*
\`\`\`
${VLESS_LINK}
\`\`\`
━━━━━━━━━━━━━━━━━━━━
📝 *အသုံးပြုနည်း လမ်းညွှန်*
1. 🔗 configuration link ကို copy ကူးပါ။
2. 📱 V2rayNg,NPVTunnel,NetMode နဲ့အသုံးပြုချင်သည့် Appကိုဖွင့်ပါ။
3. 📥 clipboard မှ import လုပ်ပါ။
4. ✅ ချိတ်ဆက်ပြီး စတင်အသုံးပြုပါ။ 🎉
"

    CONSOLE_MESSAGE="
🚀 GCP Mytel  Bypass Deployment Successful 🚀
━━━━━━━━━━━━━━━━━━━━
📅 စတင်ချိန်: ${start_time}
⏱️ ပြီးဆုံးမည့်အချိန်: ${expiry_time}
━━━━━━━━━━━━━━━━━━━━
✨ Deployment Details:
• Project: ${PROJECT_ID}
• Service: ${SERVICE_NAME}
• Region: ${FLAG_EMOJI} ${REGION} (${REGION_NAME})
• Resources: ${CPU} CPU | ${MEMORY} RAM
• Domain: ${DOMAIN}

🔗 Configuration Link:
${VLESS_LINK}

📝 အသုံးပြုနည်း လမ်းညွှန်:
1. 🔗 configuration link ကို copy ကူးပါ။
2. 📱 V2rayNg,NPVTunnel,NetMode နဲ့အသုံးပြုချင်သည့် Appကိုဖွင့်ပါ။
3. 📥 clipboard မှ import လုပ်ပါ။
4. ✅ ချိတ်ဆက်ပြီး စတင်အသုံးပြုပါ။ 🎉
━━━━━━━━━━━━━━━━━━━━"

    echo "$CONSOLE_MESSAGE" > deployment-info.txt
    log "Deployment info saved to deployment-info.txt"

    echo
    info "=== Deployment Information ==="
    echo "$CONSOLE_MESSAGE"
    echo

    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        log "Sending deployment info to Telegram..."
        send_deployment_notification "$MESSAGE"
    else
        log "Skipping Telegram notification as per user selection"
    fi

    log "Deployment completed successfully!"
    log "Service URL: $SERVICE_URL"
    log "Configuration saved to: deployment-info.txt"
}

main "$@"
