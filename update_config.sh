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
    local download_url="$sub_url"
    local tmp_file="$TMP_DIR/subscription_$(date '+%s').json"
    
    print_msg "$BLUE" "– Загружаем JSON из: ${download_url} ..."
    
    # Download the main JSON file
    wget -q --no-check-certificate -O "$tmp_file" "$download_url"
    if [ $? -ne 0 ]; then
        print_msg "$RED" "Ошибка при загрузке основного файла!"
        rm -f "$tmp_file"
        return 1
    fi
    
    # Basic JSON validation - check if file contains valid JSON structure
    if ! grep -q '{' "$tmp_file" || ! grep -q '}' "$tmp_file"; then
        print_msg "$RED" "Ошибка: загруженный файл не является валидным JSON!"
        rm -f "$tmp_file"
        return 1
    fi
    
    print_msg "$BLUE" "– Конфигурация успешно загружена"
    
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

# Function to validate the configuration
validate_and_format_config() {
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

# Main function
main() {
    # Check requirements
    check_requirements
    if [ $? -ne 0 ]; then
        print_msg "$RED" "Ошибка: не все требования выполнены!"
        exit 1
    fi
    
    # Request subscription URL
    printf "Вставьте ссылку на вашу подписку: " >&2
    read SUB_URL < /dev/tty
    
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
    printf "Для доступа к панели управления откройте в браузере: http://%s:9090\n" "$ROUTER_IP"
    printf "На стартовом экране введите %s в поле адреса и нажмите Submit\n" "$ROUTER_IP"
    
    exit 0
}

# Run main function
main