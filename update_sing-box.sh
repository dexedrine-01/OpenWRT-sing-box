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

# Function to check available disk space
check_disk_space() {
    local required_space=30000  # Required space in KB (approximately 30MB)
    local install_path="${install_dir}"
    local temp_path="${temp_dir}"
    
    # Check space in installation directory
    local available_space_install=$(df -k "$(dirname "$install_path")" | awk 'NR==2 {print $4}')
    # Check space in temporary directory
    local available_space_temp=$(df -k "$(dirname "$temp_path")" | awk 'NR==2 {print $4}')
    
    if [ -z "$available_space_install" ] || [ -z "$available_space_temp" ]; then
        log_msg "$YELLOW" "[!] Предупреждение: Не удалось проверить доступное пространство"
        return 0
    fi
    
    if [ "$available_space_install" -lt "$required_space" ]; then
        log_msg "$RED" "[✗] Ошибка: Недостаточно места в $(dirname "$install_path")"
        log_msg "$RED" "    Доступно: $(($available_space_install / 1024)) МБ, требуется минимум: $(($required_space / 1024)) МБ"
        return 1
    fi
    
    if [ "$available_space_temp" -lt "$required_space" ]; then
        log_msg "$RED" "[✗] Ошибка: Недостаточно места во временной директории $(dirname "$temp_path")"
        log_msg "$RED" "    Доступно: $(($available_space_temp / 1024)) МБ, требуется минимум: $(($required_space / 1024)) МБ"
        return 1
    fi
    
    log_msg "$GREEN" "[✓] Достаточно свободного места для обновления"
    return 0
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
    
    # Get file size before downloading
    local file_size=$(curl -sI "$download_url" | grep -i "Content-Length" | awk '{print $2}' | tr -d '\r')
    if [ -n "$file_size" ]; then
        local file_size_mb=$(echo "scale=2; $file_size/1048576" | bc 2>/dev/null || echo "$(($file_size / 1048576))")
        log_msg "$BLUE" "Размер файла для загрузки: ${file_size_mb} МБ"
    fi
    
    # Download the file with progress indication
    local filename=$(basename "$download_url")
    log_msg "$BLUE" "Загрузка файла: $filename"
    
    if command_exists wget; then
        if ! wget -O "${temp_dir}/${filename}" "$download_url" --progress=bar:force 2>>"$log_file"; then
            log_msg "$RED" "[✗] Ошибка: не удалось загрузить файл $filename"
            exit 1
        fi
    elif command_exists curl; then
        if ! curl -L -o "${temp_dir}/${filename}" "$download_url" --progress-bar 2>>"$log_file"; then
            log_msg "$RED" "[✗] Ошибка: не удалось загрузить файл $filename"
            exit 1
        fi
    else
        log_msg "$RED" "[✗] Ошибка: не найдены инструменты для загрузки (wget или curl)"
        exit 1
    fi
    
    log_msg "$GREEN" "[✓] Файл $filename успешно загружен"
    
    # Verify file integrity
    if [ -f "${temp_dir}/${filename}" ]; then
        local downloaded_size=$(wc -c < "${temp_dir}/${filename}")
        if [ -n "$file_size" ] && [ "$downloaded_size" -ne "$file_size" ]; then
            log_msg "$RED" "[✗] Ошибка: размер загруженного файла не соответствует ожидаемому"
            log_msg "$RED" "    Ожидаемый размер: $file_size байт, фактический: $downloaded_size байт"
            exit 1
        fi
    else
        log_msg "$RED" "[✗] Ошибка: файл не был загружен"
        exit 1
    fi
    
    # Extract and install
    log_msg "$BLUE" "Распаковка архива..."
    folder_name=$(tar -tzf "${temp_dir}/${filename}" 2>>"$log_file" | head -1 | cut -f1 -d"/")
    
    if [ -z "$folder_name" ]; then
        log_msg "$RED" "[✗] Ошибка: не удалось определить имя папки в архиве"
        exit 1
    fi
    
    if ! tar -xzf "${temp_dir}/${filename}" -C "$temp_dir" 2>>"$log_file"; then
        log_msg "$RED" "[✗] Ошибка при распаковке архива"
        exit 1
    fi
    
    # Backup existing installation
    if [ -f "${install_dir}/sing-box" ]; then
        log_msg "$BLUE" "Создание резервной копии текущей версии..."
        mv "${install_dir}/sing-box" "$backup_file"
    fi
    
    # Install new version
    log_msg "$BLUE" "Установка новой версии..."
    if [ ! -f "${temp_dir}/${folder_name}/sing-box" ]; then
        log_msg "$RED" "[✗] Ошибка: исполняемый файл sing-box не найден в распакованном архиве"
        exit 1
    fi
    
    cp "${temp_dir}/${folder_name}/sing-box" "${install_dir}/"
    chmod +x "${install_dir}/sing-box"
    
    # Verify installation
    if [ ! -x "${install_dir}/sing-box" ]; then
        log_msg "$RED" "[✗] Ошибка: не удалось установить новую версию sing-box"
        rollback
        exit 1
    fi
    
    # Clean up
    log_msg "$BLUE" "Очистка временных файлов..."
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

# Function to check available memory
check_memory() {
    local required_memory=20000  # Required memory in KB (approximately 20MB)
    
    # Get available memory (try different methods)
    local available_memory=0
    
    if [ -f "/proc/meminfo" ]; then
        available_memory=$(grep -i 'MemAvailable' /proc/meminfo | awk '{print $2}')
        
        # If MemAvailable is not found, calculate from MemFree + Buffers + Cached
        if [ -z "$available_memory" ]; then
            local mem_free=$(grep -i 'MemFree' /proc/meminfo | awk '{print $2}')
            local buffers=$(grep -i 'Buffers' /proc/meminfo | awk '{print $2}')
            local cached=$(grep -i 'Cached' /proc/meminfo | awk '{print $2}' | head -1)
            
            if [ -n "$mem_free" ] && [ -n "$buffers" ] && [ -n "$cached" ]; then
                available_memory=$((mem_free + buffers + cached))
            fi
        fi
    fi
    
    # If still no valid value, try free command
    if [ -z "$available_memory" ] || [ "$available_memory" -eq 0 ]; then
        if command_exists free; then
            available_memory=$(free | grep -i 'Mem:' | awk '{print $7}')
        fi
    fi
    
    # If we still can't determine memory, warn but continue
    if [ -z "$available_memory" ] || [ "$available_memory" -eq 0 ]; then
        log_msg "$YELLOW" "[!] Предупреждение: Не удалось проверить доступную память"
        return 0
    fi
    
    if [ "$available_memory" -lt "$required_memory" ]; then
        log_msg "$RED" "[✗] Ошибка: Недостаточно оперативной памяти для обновления"
        log_msg "$RED" "    Доступно: $(($available_memory / 1024)) МБ, требуется минимум: $(($required_memory / 1024)) МБ"
        return 1
    fi
    
    log_msg "$GREEN" "[✓] Достаточно оперативной памяти для обновления"
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
    
    # Check for available disk space and memory
    if ! check_disk_space; then
        log_msg "$RED" "[✗] Обновление отменено из-за нехватки дискового пространства"
        exit 1
    fi
    
    if ! check_memory; then
        log_msg "$RED" "[✗] Обновление отменено из-за нехватки памяти"
        exit 1
    }
    
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