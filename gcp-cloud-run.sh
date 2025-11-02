#!/bin/bash

# This script deploys a V2Ray service to Google Cloud Run,
# handles user input for configuration, and sends deployment details
# to multiple Telegram channels/chats if configured.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Configuration Constants ---
DEFAULT_DEPLOY_DURATION="5h" # အလိုအလျောက်သတ်မှတ်ထားသော ကြာချိန်: ၅ နာရီ

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

# --- Time Calculation Functions ---

# Function to convert duration string (e.g., 5h30m) to seconds
parse_duration_to_seconds() {
    local duration="$1"
    local total_seconds=0
    
    # Extract hours
    if [[ "$duration" =~ ([0-9]+)h ]]; then
        total_seconds=$((total_seconds + ${BASH_REMATCH[1]} * 3600))
    fi
    
    # Extract minutes
    if [[ "$duration" =~ ([0-9]+)m ]]; then
        total_seconds=$((total_seconds + ${BASH_REMATCH[1]} * 60))
    fi
    
    echo "$total_seconds"
}

# Calculates expiry time in Myanmar Standard Time (MST = UTC+6:30)
calculate_expiry_time() {
    local duration_seconds="$1"
    
    # Get current UTC time in seconds since epoch
    local current_utc_epoch=$(date +%s)
    
    # Calculate expiry time in UTC epoch
    local expiry_utc_epoch=$((current_utc_epoch + duration_seconds))
    
    # Convert expiry UTC epoch time to MST (UTC+6:30 = 390 minutes * 60 seconds = 23400 seconds offset)
    local mst_offset_seconds=23400 # 6 hours 30 minutes
    local expiry_mst_epoch=$((expiry_utc_epoch + mst_offset_seconds))
    
    # Format the expiry MST time to a human-readable format (e.g., 05:30 AM)
    local expiry_mst_time=$(date -d "@$expiry_mst_epoch" +'%I:%M %p' 2>/dev/null || date -r "$expiry_mst_epoch" +'%I:%M %p')
    
    # Check if time calculation failed (e.g., unsupported 'date' options)
    if [[ -z "$expiry_mst_time" ]]; then
        echo "Time calculation failed. Displaying default duration."
    else
        echo "$expiry_mst_time (MST)"
    fi
}

# --- Validation Functions ---

# Function to validate UUID format
validate_uuid() {
    local uuid_pattern='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    if [[ ! $1 =~ $uuid_pattern ]]; then
        error "Invalid UUID format: $1"
        return 1
    fi
    return 0
}

# Function to validate Telegram Bot Token
validate_bot_token() {
    local token_pattern='^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$'
    if [[ ! $1 =~ $token_pattern ]]; then
        error "Invalid Telegram Bot Token format"
        return 1
    fi
    return 0
}

# Function to validate Channel ID (Supports multiple IDs separated by commas)
validate_channel_id() {
    local ids_string="$1"
    # Split by comma and iterate
    IFS=',' read -r -a ids_array <<< "$ids_string"
    
    for id in "${ids_array[@]}"; do
        # Trim leading/trailing spaces
        local trimmed_id=$(echo "$id" | xargs)
        if [[ -z "$trimmed_id" ]]; then
            continue # Skip empty string resulting from split
        fi
        if [[ ! "$trimmed_id" =~ ^-?[0-9]+$ ]]; then
            error "Invalid Channel ID format detected: $trimmed_id"
            error "Channel IDs must start with -100... or be positive numbers."
            return 1
        fi
    done
    return 0
}

# Function to validate Chat ID (Supports multiple IDs separated by commas)
validate_chat_id() {
    local ids_string="$1"
    # Split by comma and iterate
    IFS=',' read -r -a ids_array <<< "$ids_string"
    
    for id in "${ids_array[@]}"; do
        # Trim leading/trailing spaces
        local trimmed_id=$(echo "$id" | xargs)
        if [[ -z "$trimmed_id" ]]; then
            continue # Skip empty string resulting from split
        fi
        if [[ ! "$trimmed_id" =~ ^-?[0-9]+$ ]]; then
            error "Invalid Chat ID format detected: $trimmed_id"
            return 1
        fi
    done
    return 0
}

# Function to validate URL format
validate_url() {
    local url="$1"
    
    # Basic URL pattern for Telegram and other common URLs
    local url_pattern='^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/[a-zA-Z0-9._~:/?#[\]@!$&'"'"'()*+,;=-]*)?$'
    
    # Special pattern for Telegram t.me URLs
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


# --- Configuration Functions ---

# CPU selection function
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

# Memory selection function
select_memory() {
    echo
    info "=== Memory Configuration ==="
    
    # Show recommended memory based on CPU selection
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
    
    # Validate memory configuration
    validate_memory_config
    
    info "Selected Memory: $MEMORY"
}

# Validate memory configuration based on CPU
validate_memory_config() {
    local cpu_num=$CPU
    local memory_num=$(echo $MEMORY | sed 's/[^0-9]*//g')
    local memory_unit=$(echo $MEMORY | sed 's/[0-9]*//g')
    
    # Convert everything to Mi for comparison
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

# Region selection function (Expanded to 13 regions)
select_region() {
    echo
    info "=== Region Selection (13 Regions) ==="
    echo "1. us-central1 (Iowa, USA) - Default"
    echo "2. us-west1 (Oregon, USA)" 
    echo "3. us-east1 (South Carolina, USA)"
    echo "4. southamerica-east1 (São Paulo, Brazil)"
    echo "5. europe-west1 (Belgium)"
    echo "6. europe-west4 (Netherlands)"
    echo "7. asia-southeast1 (Singapore)"
    echo "8. asia-southeast2 (Jakarta, Indonesia)"
    echo "9. asia-northeast1 (Tokyo, Japan)"
    echo "10. asia-east1 (Taiwan)"
    echo "11. australia-southeast1 (Sydney, Australia)"
    echo "12. me-west1 (Tel Aviv, Israel)"
    echo "13. africa-south1 (Johannesburg, South Africa)"
    echo
    
    while true; do
        read -p "Select region (1-13): " region_choice
        case $region_choice in
            1) REGION="us-central1"; break ;;
            2) REGION="us-west1"; break ;;
            3) REGION="us-east1"; break ;;
            4) REGION="southamerica-east1"; break ;;
            5) REGION="europe-west1"; break ;;
            6) REGION="europe-west4"; break ;;
            7) REGION="asia-southeast1"; break ;;
            8) REGION="asia-southeast2"; break ;;
            9) REGION="asia-northeast1"; break ;;
            10) REGION="asia-east1"; break ;;
            11) REGION="australia-southeast1"; break ;;
            12) REGION="me-west1"; break ;;
            13) REGION="africa-south1"; break ;;
            *) echo "Invalid selection. Please enter a number between 1-13." ;;
        esac
    done
    
    info "Selected region: $REGION"
}

# Telegram destination selection
select_telegram_destination() {
    echo
    info "=== Telegram Notification Destination ==="
    echo "1. Channel သို့သာ ပို့မည် (Multi-Channel Support)"
    echo "2. Bot Private Message သို့သာ ပို့မည်" 
    echo "3. Channel နှင့် Bot နှစ်ခုလုံးသို့ ပို့မည်"
    echo "4. Telegram ကို မပို့ပဲ Deploy လုပ်မည်"
    echo
    
    # Initialize these variables before the loop to prevent "unbound variable" error
    TELEGRAM_CHANNEL_ID=""
    TELEGRAM_CHAT_ID=""
    
    while true; do
        read -p "Select destination (1-4): " telegram_choice
        case $telegram_choice in
            1) 
                TELEGRAM_DESTINATION="channel"
                while true; do
                    read -p "Enter Telegram Channel ID(s) (comma-separated if multiple, eg: -100...,-100...): " TELEGRAM_CHANNEL_ID
                    if validate_channel_id "$TELEGRAM_CHANNEL_ID"; then
                        break
                    fi
                done
                break 
                ;;
            2) 
                TELEGRAM_DESTINATION="bot"
                while true; do
                    read -p "Enter your Chat ID(s) (comma-separated if multiple, for bot private message): " TELEGRAM_CHAT_ID
                    if validate_chat_id "$TELEGRAM_CHAT_ID"; then
                        break
                    fi
                done
                break 
                ;;
            3) 
                TELEGRAM_DESTINATION="both"
                while true; do
                    read -p "Enter Telegram Channel ID(s) (comma-separated if multiple, eg: -100...,-100...): " TELEGRAM_CHANNEL_ID
                    if validate_channel_id "$TELEGRAM_CHANNEL_ID"; then
                        break
                    fi
                done
                while true; do
                    read -p "Enter your Chat ID(s) (comma-separated if multiple, for bot private message): " TELEGRAM_CHAT_ID
                    if validate_chat_id "$TELEGRAM_CHAT_ID"; then
                        break
                    fi
                done
                break 
                ;;
            4) 
                TELEGRAM_DESTINATION="none"
                TELEGRAM_CHANNEL_ID=""
                TELEGRAM_CHAT_ID=""
                break 
                ;;
            *) echo "Invalid selection. Please enter a number between 1-4." ;;
        esac
    done
}

# Channel URL input function
get_channel_url() {
    echo
    info "=== Channel URL Configuration (For Telegram Button) ==="
    echo "Default URL: https://t.me/zero_1101_tg"
    echo "You can use the default URL or enter your own custom URL."
    echo
    
    while true; do
        read -p "Enter Channel URL [default: https://t.me/zero_1101_tg]: " CHANNEL_URL
        CHANNEL_URL=${CHANNEL_URL:-"https://t.me/zero_1101_tg"}
        
        # Remove any trailing slashes
        CHANNEL_URL=$(echo "$CHANNEL_URL" | sed 's|/*$||')
        
        if validate_url "$CHANNEL_URL"; then
            break
        else
            warn "Please enter a valid URL"
        fi
    done
    
    # Extract channel name for button text
    if [[ "$CHANNEL_URL" == *"t.me/"* ]]; then
        CHANNEL_NAME=$(echo "$CHANNEL_URL" | sed 's|.*t.me/||' | sed 's|/*$||')
    else
        # For non-telegram URLs, use the domain name
        CHANNEL_NAME=$(echo "$CHANNEL_URL" | sed 's|.*://||' | sed 's|/.*||' | sed 's|www\.||')
    fi
    
    # If channel name is empty, use default (Burmese name)
    if [[ -z "$CHANNEL_NAME" ]]; then
        CHANNEL_NAME="1101 Channel"
    fi
    
    # Truncate long names for button text
    if [[ ${#CHANNEL_NAME} -gt 20 ]]; then
        CHANNEL_NAME="${CHANNEL_NAME:0:17}..."
    fi
    
    info "Channel URL: $CHANNEL_URL"
    info "Channel Name: $CHANNEL_NAME"
}

# User input function
get_user_input() {
    echo
    info "=== Service Configuration ==="
    
    # Service Name
    while true; do
        read -p "Enter service name: " SERVICE_NAME
        if [[ -n "$SERVICE_NAME" ]]; then
            break
        else
            error "Service name cannot be empty"
        fi
    done
    
    # UUID
    while true; do
        read -p "Enter UUID: " UUID
        UUID=${UUID:-"5652a909-a0b4-48dd-ae29-972757489bf0"}
        if validate_uuid "$UUID"; then
            break
        fi
    done
    
    # Telegram Bot Token (required if any Telegram option is selected)
    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        while true; do
            read -p "Enter Telegram Bot Token: " TELEGRAM_BOT_TOKEN
            if validate_bot_token "$TELEGRAM_BOT_TOKEN"; then
                break
            fi
        done
        
        # Get Channel URL if Telegram is enabled
        get_channel_url
    fi

    # Host Domain (optional)
    read -p "Enter host domain [default: m.googleapis.com]: " HOST_DOMAIN
    HOST_DOMAIN=${HOST_DOMAIN:-"m.googleapis.com"}
    
}

# Display configuration summary
show_config_summary() {
    
    # Calculate expiry time based on the fixed default duration
    local duration_seconds=$(parse_duration_to_seconds "$DEFAULT_DEPLOY_DURATION")
    local expiry_time=$(calculate_expiry_time "$duration_seconds")
    
    echo
    info "=== Configuration Summary ==="
    echo "Project ID:    $(gcloud config get-value project)"
    echo "Region:        $REGION"
    echo "Service Name:  $SERVICE_NAME"
    echo "Host Domain:   $HOST_DOMAIN"
    echo "UUID:          $UUID"
    echo "CPU:           $CPU core(s)"
    echo "Memory:        $MEMORY"
    echo "Duration:      $DEFAULT_DEPLOY_DURATION"
    echo "Expires At:    $expiry_time"
    
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


# --- Deployment & Notification Functions ---

# Validation functions
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

# Send a single message to a single chat ID with the dynamic button
send_to_telegram() {
    local chat_id="$1"
    local message="$2"
    local response
    
    # Create inline keyboard with dynamic button
    local keyboard=$(cat << EOF
{
    "inline_keyboard": [[
        {
            "text": "$CHANNEL_NAME",
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
        error "Failed to send to Telegram (HTTP $http_code): $content"
        return 1
    fi
}

# Handles sending messages to all configured IDs (supports multi-channel/chat)
send_deployment_notification() {
    local message="$1"
    local success_count=0
    
    # Split Channel IDs into an array for iteration
    IFS=',' read -r -a channel_ids <<< "$TELEGRAM_CHANNEL_ID"
    # Split Chat IDs into an array for iteration
    IFS=',' read -r -a chat_ids <<< "$TELEGRAM_CHAT_ID"
    
    case $TELEGRAM_DESTINATION in
        "channel")
            log "Sending to Telegram Channel(s)..."
            for id in "${channel_ids[@]}"; do
                local trimmed_id=$(echo "$id" | xargs)
                if [[ -z "$trimmed_id" ]]; then continue; fi
                
                log "Attempting to send to Channel ID: $trimmed_id"
                if send_to_telegram "$trimmed_id" "$message"; then
                    log "✅ Successfully sent to Telegram Channel ($trimmed_id)"
                    success_count=$((success_count + 1))
                else
                    error "❌ Failed to send to Telegram Channel ($trimmed_id)"
                fi
            done
            ;;
            
        "bot")
            log "Sending to Bot private message(s)..."
            for id in "${chat_ids[@]}"; do
                local trimmed_id=$(echo "$id" | xargs)
                if [[ -z "$trimmed_id" ]]; then continue; fi
                
                log "Attempting to send to Chat ID: $trimmed_id"
                if send_to_telegram "$trimmed_id" "$message"; then
                    log "✅ Successfully sent to Bot private message ($trimmed_id)"
                    success_count=$((success_count + 1))
                else
                    error "❌ Failed to send to Bot private message ($trimmed_id)"
                fi
            done
            ;;
            
        "both")
            log "Sending to both Channel(s) and Bot Message(s)..."
            
            # Send to Channel(s)
            for id in "${channel_ids[@]}"; do
                local trimmed_id=$(echo "$id" | xargs)
                if [[ -z "$trimmed_id" ]]; then continue; fi
                
                log "Attempting to send to Channel ID: $trimmed_id"
                if send_to_telegram "$trimmed_id" "$message"; then
                    log "✅ Successfully sent to Telegram Channel ($trimmed_id)"
                    success_count=$((success_count + 1))
                else
                    error "❌ Failed to send to Telegram Channel ($trimmed_id)"
                fi
            done
            
            # Send to Bot Message(s)
            for id in "${chat_ids[@]}"; do
                local trimmed_id=$(echo "$id" | xargs)
                if [[ -z "$trimmed_id" ]]; then continue; fi
                
                log "Attempting to send to Chat ID: $trimmed_id"
                if send_to_telegram "$trimmed_id" "$message"; then
                    log "✅ Successfully sent to Bot private message ($trimmed_id)"
                    success_count=$((success_count + 1))
                else
                    error "❌ Failed to send to Bot private message ($trimmed_id)"
                fi
            done
            ;;
            
        "none")
            log "Skipping Telegram notification as configured"
            return 0
            ;;
    esac
    
    # Check if at least one message was successful
    if [[ $success_count -gt 0 ]]; then
        log "Telegram notification completed ($success_count successful)"
        return 0
    else
        warn "All Telegram notifications failed, but deployment was successful"
        return 1
    fi
}


# --- Main Logic ---

main() {
    info "=== GCP Cloud Run V2Ray Deployment ==="
    
    # Get user input
    select_region
    select_cpu
    select_memory
    select_telegram_destination
    get_user_input
    
    # Calculate expiry time based on the fixed default duration
    local duration_seconds=$(parse_duration_to_seconds "$DEFAULT_DEPLOY_DURATION")
    local expiry_time=$(calculate_expiry_time "$duration_seconds")
    
    # Display summary before deployment
    show_config_summary
    
    PROJECT_ID=$(gcloud config get-value project)
    
    log "Starting Cloud Run deployment..."
    log "Project: $PROJECT_ID"
    log "Region: $REGION"
    log "Service: $SERVICE_NAME"
    log "CPU: $CPU core(s)"
    log "Memory: $MEMORY"
    
    validate_prerequisites
    
    # Set trap for cleanup
    trap cleanup EXIT
    
    log "Enabling required APIs..."
    gcloud services enable \
        cloudbuild.googleapis.com \
        run.googleapis.com \
        iam.googleapis.com \
        --quiet
    
    # Clean up any existing directory
    cleanup
    
    log "Cloning repository..."
    # Cloning relies on the user having made the repository public or having configured credentials.
    if ! git clone https://github.com/KaungSattKyaw/gcp-v2ray.git; then
        error "Failed to clone repository. Ensure the repository is Public."
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
    
    # Get the service URL
    SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} \
        --region ${REGION} \
        --format 'value(status.url)' \
        --quiet)
    
    DOMAIN=$(echo $SERVICE_URL | sed 's|https://||')
    
    # Create Vless share link
    VLESS_LINK="vless://${UUID}@${HOST_DOMAIN}:443?path=%2Ftgkmks26381Mr&security=tls&alpn=none&encryption=none&host=${DOMAIN}&type=ws&sni=${DOMAIN}#${SERVICE_NAME}"
    
    # Create beautiful telegram message with emojis (IN BURMESE) - Aesthetic Version
    MESSAGE="
🚀 *GCP V2Ray Deployment Successful* 🚀
━━━━━━━━━━━━━━━━━━━━
⏳ *ကြာချိန်:* \`${DEFAULT_DEPLOY_DURATION}\`
⏱️ *ကုန်ဆုံးမည့်အချိန်:* \`${expiry_time}\`
━━━━━━━━━━━━━━━━━━━━
✨ *Deployment Details:*
• *Project:* \`${PROJECT_ID}\`
• *Service:* \`${SERVICE_NAME}\`
• *Region:* \`${REGION}\`
• *Resources:* \`${CPU} CPU | ${MEMORY} RAM\`
• *Domain:* \`${DOMAIN}\`

🔗 *V2Ray Configuration Link:*
\`${VLESS_LINK}\`

📝 *အသုံးပြုနည်း လမ်းညွှန်:*
1. 🔗 configuration link ကို copy ကူးပါ။
2. 📱 V2Ray client ကို ဖွင့်ပါ။
3. 📥 clipboard မှ import လုပ်ပါ။
4. ✅ ချိတ်ဆက်ပြီး စတင်အသုံးပြုပါ။ 🎉
━━━━━━━━━━━━━━━━━━━━"

    # Create console message (IN BURMESE)
    CONSOLE_MESSAGE="
🚀 GCP V2Ray Deployment Successful 🚀
⏳ ကြာချိန်: ${DEFAULT_DEPLOY_DURATION}
⏱️ ကုန်ဆုံးမည့်အချိန်: ${expiry_time}
━━━━━━━━━━━━━━━━━━━━
✨ Deployment Details:
• Project: ${PROJECT_ID}
• Service: ${SERVICE_NAME}
• Region: ${REGION}
• Resources: ${CPU} CPU | ${MEMORY} RAM
• Domain: ${DOMAIN}

🔗 V2Ray Configuration Link:
${VLESS_LINK}

📝 အသုံးပြုနည်း လမ်းညွှန်:
1. 🔗 configuration link ကို copy ကူးပါ။
2. 📱 V2Ray client ကို ဖွင့်ပါ။
3. 📥 clipboard မှ import လုပ်ပါ။
4. ✅ ချိတ်ဆက်ပြီး စတင်အသုံးပြုပါ။ 🎉
━━━━━━━━━━━━━━━━━━━━"
    
    # Save to file
    echo "$CONSOLE_MESSAGE" > deployment-info.txt
    log "Deployment info saved to deployment-info.txt"
    
    # Display locally
    echo
    info "=== Deployment Information ==="
    echo "$CONSOLE_MESSAGE"
    echo
    
    # Send to Telegram based on user selection
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

# Run main function
main "$@"
