#!/bin/sh
# Script for updating sing-box to the latest version with architecture detection

# Configuration
log_file="/var/log/sing-box-update.log"
install_dir="/usr/bin"
temp_dir="/opt/bin"
github_repo="SagerNet/sing-box"
backup_file="${install_dir}/sing-box.old"

# ANSI color codes
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
RESET="\033[0m"

# Function for logging and displaying messages
log_msg() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${RESET}" | tee -a "$log_file"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to create required directories
create_dirs() {
    [ ! -d "$temp_dir" ] && mkdir -p "$temp_dir"
    [ ! -d "$(dirname "$log_file")" ] && mkdir -p "$(dirname "$log_file")"
}

# Function to detect system architecture
detect_architecture() {
    arch=$(uname -m)
    case "$arch" in
        "x86_64")
            file="linux-amd64.tar.gz"
            ;;
        "armv7l")
            file="linux-armv7.tar.gz"
            ;;
        "armv6l")
            file="linux-armv6.tar.gz"
            ;;
        "aarch64")
            file="linux-arm64.tar.gz"
            ;;
        "i386"|"i686")
            file="linux-386.tar.gz"
            ;;
        "mips")
            file="linux-mips.tar.gz"
            ;;
        *)
            log_msg "$RED" "[✗] Ошибка: Архитектура $arch не поддерживается"
            exit 1
            ;;
    esac
    
    log_msg "$GREEN" "[✓] Архитектура поддерживается: $arch"
    return 0
}

# Function to rollback to the previous version
rollback() {
    log_msg "$YELLOW" "Откатываемся на предыдущую версию..."
    
    if [ -f "$backup_file" ]; then
        mv "$backup_file" "${install_dir}/sing-box"
        chmod +x "${install_dir}/sing-box"
        
        if service sing-box restart 2>>"$log_file"; then
            log_msg "$GREEN" "[✓] Откат выполнен успешно"
        else
            log_msg "$RED" "[✗] Ошибка при откате и перезапуске sing-box"
            exit 1
        fi
    else
        log_msg "$RED" "[✗] Предыдущая версия не найдена!"
        exit 1
    fi
}

# Function to get current sing-box version
get_current_version() {
    if command_exists sing-box; then
        current_version=$(sing-box version 2>/dev/null | head -n 1 | awk '{print $3}')
        if [ -z "$current_version" ]; then
            log_msg "$YELLOW" "[!] Не удалось определить текущую версию sing-box"
            current_version="unknown"
        fi
    else
        log_msg "$YELLOW" "[!] sing-box не установлен"
        current_version="not installed"
    fi
    
    echo "$current_version"
}

# Function to get the latest version based on release type
get_latest_version() {
    local version_type="$1"
    local version_url="https://api.github.com/repos/${github_repo}/releases"
    local latest_version=""
    
    case "$version_type" in
        "stable")
            version_url="${version_url}/latest"
            latest_version=$(curl -s "$version_url" | grep '"tag_name":' | cut -d '"' -f 4 | sed 's/v//')
            ;;
        "alpha")
            latest_version=$(curl -s "$version_url" | grep '"tag_name":' | grep -v "beta" | head -n 1 | cut -d '"' -f 4 | sed 's/v//')
            ;;
        "beta")
            latest_version=$(curl -s "$version_url" | grep '"tag_name":' | grep "beta" | head -n 1 | cut -d '"' -f 4 | sed 's/v//')
            ;;
    esac
    
    if [ -z "$latest_version" ]; then
        log_msg "$RED" "[✗] Ошибка: Не удалось получить информацию о последней версии"
        exit 1
    fi
    
    echo "$latest_version"
}

# Function to download and install sing-box
download_and_install() {
    local version_type="$1"
    local version_url="https://api.github.com/repos/${github_repo}/releases"
    local download_url=""
    
    case "$version_type" in
        "stable")
            version_url="${version_url}/latest"
            ;;
    esac
    
    # Get download URL for the required architecture
    download_url=$(curl -s "$version_url" | grep "browser_download_url.*$file" | cut -d '"' -f 4 | head -n 1)
    
    if [ -z "$download_url" ]; then
        log_msg "$RED" "[✗] Ошибка: Не удалось найти ссылку для скачивания для архитектуры $arch"
        exit 1
    fi
    
    # Download the file
    local filename=$(basename "$download_url")
    log_msg "$BLUE" "Загрузка файла: $filename"
    
    if ! wget -O "${temp_dir}/${filename}" "$download_url" 2>>"$log_file"; then
        log_msg "$RED" "[✗] Ошибка: не удалось загрузить файл $filename"
        exit 1
    fi
    
    log_msg "$GREEN" "[✓] Файл $filename успешно загружен"
    
    # Extract and install
    folder_name=$(tar -tzf "${temp_dir}/${filename}" | head -1 | cut -f1 -d"/")
    
    if ! tar -xzf "${temp_dir}/${filename}" -C "$temp_dir" 2>>"$log_file"; then
        log_msg "$RED" "[✗] Ошибка при распаковке архива"
        exit 1
    fi
    
    # Backup existing installation
    if [ -f "${install_dir}/sing-box" ]; then
        mv "${install_dir}/sing-box" "$backup_file"
    fi
    
    # Install new version
    cp "${temp_dir}/${folder_name}/sing-box" "${install_dir}/"
    chmod +x "${install_dir}/sing-box"
    
    # Clean up
    rm -rf "${temp_dir:?}/${folder_name}" "${temp_dir}/${filename}"
    
    return 0
}

# Function to restart services
restart_services() {
    log_msg "$BLUE" "Перезапуск сервисов..."
    
    if ! service sing-box restart 2>>"$log_file"; then
        log_msg "$RED" "[✗] Ошибка при перезапуске сервиса sing-box"
        return 1
    fi
    
    log_msg "$GREEN" "[✓] Сервис sing-box успешно перезапущен"
    
    if ! service network restart 2>>"$log_file"; then
        log_msg "$YELLOW" "[!] Предупреждение: Ошибка при перезапуске сети"
        log_msg "$YELLOW" "[!] Рекомендуется перезапустить сеть вручную"
        return 0
    fi
    
    log_msg "$GREEN" "[✓] Сеть успешно перезапущена"
    return 0
}

# Main function
main() {
    create_dirs
    
    # Handle rollback argument
    if [ "$1" = "rollback" ]; then
        rollback
        exit 0
    fi
    
    # Detect architecture
    detect_architecture
    
    # Menu for version selection
    echo "Выберите тип версии:"
    echo "1. Релизная (stable)"
    echo "2. Альфа (alpha)"
    echo "3. Бета (beta)"
    read -p "Введите ваш выбор (1, 2, 3): " choice < /dev/tty
    
    case "$choice" in
        1)
            version_type="stable"
            log_msg "$BLUE" "Вы выбрали релизную версию"
            ;;
        2)
            version_type="alpha"
            log_msg "$BLUE" "Вы выбрали альфа-версию"
            ;;
        3)
            version_type="beta"
            log_msg "$BLUE" "Вы выбрали бета-версию"
            ;;
        *)
            log_msg "$RED" "[✗] Ошибка: Некорректный выбор. Пожалуйста, выберите 1, 2 или 3."
            exit 1
            ;;
    esac
    
    # Get current and latest versions
    current_version=$(get_current_version)
    latest_version=$(get_latest_version "$version_type")
    
    # Check if update is needed
    if [ "$current_version" = "$latest_version" ]; then
        log_msg "$GREEN" "[✓] Уже установлена последняя версия: $current_version"
        exit 0
    fi
    
    log_msg "$BLUE" "Обновляем с версии $current_version до $latest_version"
    
    # Download and install
    download_and_install "$version_type"
    
    # Restart services
    if ! restart_services; then
        log_msg "$RED" "[✗] Ошибка при обновлении. Выполняется откат..."
        rollback
        exit 1
    fi
    
    log_msg "$GREEN" "[✓] Обновление завершено успешно до версии $latest_version"
    exit 0
}

# Run the main function
main "$@"