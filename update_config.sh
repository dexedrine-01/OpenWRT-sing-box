#!/bin/sh
# sing-box for OpenWRT

# Constants for paths and settings
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="$CONFIG_DIR/config.json"
BACKUP_DIR="$CONFIG_DIR/backups"
TMP_DIR="/tmp"
LOG_FILE="/tmp/sing-box-updater.log"

# Define colors (bold text)
BLUE="\033[1;34m"
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
RESET="\033[0m"

# Function for logging
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function for displaying colored messages
print_msg() {
    local color="$1"
    local message="$2"
    printf "${color}${message}${RESET}\n" >&2
    log "$message"
}

# Function to check required utilities
check_requirements() {
    print_msg "$BLUE" "– Проверка необходимых утилит..."
    
    # Check for sing-box (critical for operation)
    if ! which sing-box >/dev/null 2>&1; then
        print_msg "$RED" "Ошибка: sing-box не установлен!"
        return 1
    fi
    
    local missing_tools=""
    
    # Check for wget
    if ! which wget >/dev/null 2>&1; then
        missing_tools="$missing_tools wget"
    fi
    
    # Check for jq
    if ! which jq >/dev/null 2>&1; then
        missing_tools="$missing_tools jq"
    fi
    
    # Install missing utilities
    if [ -n "$missing_tools" ]; then
        print_msg "$YELLOW" "– Отсутствуют необходимые утилиты:$missing_tools"
        print_msg "$BLUE" "– Обновление пакетов OpenWRT и установка недостающих утилит..."
        opkg update && opkg install $missing_tools
        
        # Verify successful installation
        for tool in $missing_tools; do
            if ! which $tool >/dev/null 2>&1; then
                print_msg "$RED" "Ошибка: не удалось установить $tool!"
                return 1
            fi
        done
    fi
    
    return 0
}

# Function to create a backup of the current configuration
backup_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # Create backup directory if it doesn't exist
        if [ ! -d "$BACKUP_DIR" ]; then
            mkdir -p "$BACKUP_DIR"
        fi
        
        # Create backup filename with current date and time
        local backup_file="$BACKUP_DIR/config_$(date '+%Y%m%d_%H%M%S').json"
        
        # Copy current configuration
        cp "$CONFIG_FILE" "$backup_file"
        
        if [ $? -eq 0 ]; then
            print_msg "$BLUE" "– Создана резервная копия: $backup_file"
            return 0
        else
            print_msg "$RED" "– Ошибка при создании резервной копии!"
            return 1
        fi
    else
        print_msg "$YELLOW" "– Текущая конфигурация не найдена, резервная копия не создана"
        return 0
    fi
}

# Function to download and modify JSON file
download_and_modify_config() {
    local sub_url="$1"
    local download_url="${sub_url}/sing-box"
    local tmp_file="$TMP_DIR/subscription_$(date '+%s').json"
    
    print_msg "$BLUE" "– Загружаем JSON из: ${download_url} ..."
    
    # Download the main JSON file
    wget -q --no-check-certificate -O "$tmp_file" "$download_url"
    if [ $? -ne 0 ]; then
        print_msg "$RED" "Ошибка при загрузке основного файла!"
        rm -f "$tmp_file"
        return 1
    fi
    
    # Check if the downloaded file is valid JSON
    if ! jq . "$tmp_file" >/dev/null 2>&1; then
        print_msg "$RED" "Ошибка: загруженный файл не является валидным JSON!"
        rm -f "$tmp_file"
        return 1
    fi
    
    print_msg "$BLUE" "– Конфигурация успешно загружена"
    
    # Modify the main JSON using sed (more compatible with OpenWRT)
    # 1. Replace "stack": "mixed" with "stack": "system"
    sed -i 's/"stack": "mixed"/"stack": "system"/' "$tmp_file"
    if [ $? -eq 0 ]; then
        print_msg "$BLUE" "– Значение stack изменено на system"
    else
        print_msg "$RED" "Ошибка при изменении stack!"
    fi
    
    # 2. Insert "auto_redirect": true, after "auto_route": true,
    sed -i '/"auto_route": true,/a\    "auto_redirect": true,' "$tmp_file"
    if [ $? -eq 0 ]; then
        print_msg "$BLUE" "– Параметр auto_redirect добавлен"
    else
        print_msg "$RED" "Ошибка при добавлении auto_redirect!"
    fi
    
    # 3. Add experimental block before the last closing bracket
    sed -i '$ s/}/,\n  "experimental": {\n    "clash_api": {\n      "external_ui": "zashboard",\n      "external_controller": "0.0.0.0:9090",\n      "external_ui_download_url": "https:\/\/github.com\/Zephyruso\/zashboard\/archive\/gh-pages.zip",\n      "external_ui_download_detour": "↔️ Direct"\n    },\n    "cache_file": {\n      "enabled": true,\n      "store_rdrc": true\n    }\n  }\n}/' "$tmp_file"
    
    if [ $? -eq 0 ]; then
        print_msg "$BLUE" "– Блок experimental добавлен"
    else
        print_msg "$RED" "Ошибка при добавлении блока experimental!"
    fi
    
    # Create configuration directory if it doesn't exist
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
    fi
    
    # Move temporary file to target location
    mv "$tmp_file" "$CONFIG_FILE"
    if [ $? -eq 0 ]; then
        print_msg "$BLUE" "– Конфигурация установлена в $CONFIG_FILE"
        return 0
    else
        print_msg "$RED" "Ошибка при установке конфигурации!"
        rm -f "$tmp_file"
        return 1
    fi
}

# Function to validate and format the configuration
validate_and_format_config() {
    # Format JSON
    if [ -x "$(which jq)" ]; then
        jq . "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        if [ $? -eq 0 ]; then
            print_msg "$BLUE" "– Конфигурация отформатирована"
        else
            print_msg "$RED" "Ошибка при форматировании конфигурации!"
            return 1
        fi
    else
        print_msg "$YELLOW" "– jq не найден, форматирование пропущено"
    fi
    
    # Check configuration using sing-box check (if available)
    if which sing-box >/dev/null 2>&1; then
        sing-box check -c "$CONFIG_FILE" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            print_msg "$BLUE" "– Конфигурация проверена"
            return 0
        else
            print_msg "$RED" "Ошибка при проверке конфигурации!"
            return 1
        fi
    else
        print_msg "$YELLOW" "– sing-box не найден, проверка конфигурации пропущена"
        return 0
    fi
}

# Function to set up daily update
setup_cron_job() {
    local choice="$1"
    local script_url="https://raw.githubusercontent.com/dexedrine-01/PurrNet/main/update_config.sh"
    
    if [ "$choice" = "y" ] || [ "$choice" = "Y" ]; then
        # Remove existing tasks for updating the script (if any)
        sed -i "/wget.*$script_url/d" /etc/crontabs/root 2>/dev/null
        
        # Add new task
        echo "0 0 * * * wget -qO- $script_url | sh" >> /etc/crontabs/root
        
        # Restart cron service in OpenWRT
        /etc/init.d/cron restart >/dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            print_msg "$BLUE" "– Ежедневное обновление настроено на полночь."
            return 0
        else
            print_msg "$RED" "Ошибка при настройке ежедневного обновления!"
            return 1
        fi
    else
        print_msg "$BLUE" "– Ежедневное обновление не настроено."
        return 0
    fi
}

# Function to get router IP address
get_router_ip() {
    local ip=$(uci get network.lan.ipaddr 2>/dev/null)
    if [ -z "$ip" ]; then
        ip="IP_роутера"
    fi
    echo "$ip"
}

# Function to reload sing-box service
reload_service() {
    # Use standard OpenWRT method to restart the service
    /etc/init.d/sing-box reload >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        print_msg "$BLUE" "– Сервис sing-box перезапущен без разрыва соединения."
        return 0
    else
        # Alternative method using service command
        service sing-box reload >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            print_msg "$BLUE" "– Сервис sing-box перезапущен без разрыва соединения."
            return 0
        else
            print_msg "$RED" "Ошибка при перезагрузке sing-box!"
            return 1
        fi
    fi
}

# Function to parse command line arguments
parse_args() {
    # Initialize variables
    SUB_URL=""
    CRON_CHOICE="n"
    NON_INTERACTIVE=0
    
    # Check first argument as URL (for backward compatibility)
    if [ $# -gt 0 ] && [ "${1#http}" != "$1" ]; then
        SUB_URL="$1"
        shift
    fi
    
    # Process remaining parameters
    while [ $# -gt 0 ]; do
        case "$1" in
            -c|--cron)
                CRON_CHOICE="y"
                shift
                ;;
            -n|--non-interactive)
                NON_INTERACTIVE=1
                shift
                ;;
            -h|--help)
                echo "Использование: $0 [URL] [опции]"
                echo "Опции:"
                echo "  URL                  Указать URL подписки напрямую"
                echo "  -c, --cron           Настроить ежедневное обновление"
                echo "  -n, --non-interactive Запуск без интерактивного режима"
                echo "  -h, --help           Показать эту справку"
                exit 0
                ;;
            *)
                echo "Неизвестный параметр: $1"
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    # Process command line arguments
    parse_args "$@"
    
    # Check requirements
    check_requirements
    if [ $? -ne 0 ]; then
        print_msg "$RED" "Ошибка: не все требования выполнены!"
        exit 1
    fi
    
    # Request subscription URL if not specified in parameters
    if [ -z "$SUB_URL" ] && [ $NON_INTERACTIVE -eq 0 ]; then
        printf "Вставьте ссылку на вашу подписку: " >&2
        read SUB_URL < /dev/tty
    fi
    
    if [ -z "$SUB_URL" ]; then
        print_msg "$RED" "Ошибка: ссылка не введена!"
        exit 1
    fi
    
    # Create backup of current configuration
    backup_config
    
    # Download and modify configuration
    download_and_modify_config "$SUB_URL"
    if [ $? -ne 0 ]; then
        print_msg "$RED" "Ошибка при обработке конфигурации!"
        exit 1
    fi
    
    # Check and format configuration
    validate_and_format_config
    
    # Reload service
    reload_service
    
    # Get router IP
    ROUTER_IP=$(get_router_ip)
    
    # Display final message
    print_msg "$GREEN" "Обновление профиля завершено успешно!"
    printf "Панель для управления VPN: http://%s:9090\n" "$ROUTER_IP"
    
    # Ask about daily update if not specified in parameters
    if [ $NON_INTERACTIVE -eq 0 ]; then
        printf "${BLUE}– Запускать ли обновление раз в сутки в полночь? (Если конфигурация изменена вручную под личные нужды, то изменения не сохранятся) [y/N]: ${RESET}"
        read CRON_CHOICE < /dev/tty
    fi
    
    # Set up daily update
    setup_cron_job "$CRON_CHOICE"
    
    exit 0
}

# Run main function with all command line arguments
main "$@"