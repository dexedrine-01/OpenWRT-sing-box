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
    # Используем printf, чтобы избежать проблем с echo -e
    printf "%b\n" "${color}${message}${RESET}" | tee -a "$log_file"
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
    local required_space=30000  # Required space in KB (approx 30MB)
    local install_path="${install_dir}"
    local temp_path="${temp_dir}"
    
    # Check space in installation directory
    local available_space_install
    available_space_install=$(df -k "$(dirname "$install_path")" | awk 'NR==2 {print $4}')
    
    # Check space in temporary directory
    local available_space_temp
    available_space_temp=$(df -k "$(dirname "$temp_path")" | awk 'NR==2 {print $4}')
    
    if [ -z "$available_space_install" ] || [ -z "$available_space_temp" ]; then
        log_msg "$YELLOW" "[!] Предупреждение: Не удалось проверить доступное пространство"
        return 0
    fi
    
    if [ "$available_space_install" -lt "$required_space" ]; then
        log_msg "$RED" "[✗] Ошибка: Недостаточно места в $(dirname "$install_path")"
        log_msg "$RED" "    Доступно: $((available_space_install / 1024)) МБ, требуется минимум: $((required_space / 1024)) МБ"
        return 1
    fi
    
    if [ "$available_space_temp" -lt "$required_space" ]; then
        log_msg "$RED" "[✗] Ошибка: Недостаточно места во временной директории $(dirname "$temp_path")"
        log_msg "$RED" "    Доступно: $((available_space_temp / 1024)) МБ, требуется минимум: $((required_space / 1024)) МБ"
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
        log_msg "$RED" "[✗] Требуется ручная установка sing-box"
        exit 1
    fi
}

# Function to get current sing-box version
get_current_version() {
    local current_version
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

# Function to remove old sing-box version
remove_old_version() {
    log_msg "$BLUE" "Удаление старой версии sing-box..."
    
    # Останавливаем сервис перед удалением
    if service sing-box stop 2>>"$log_file"; then
        log_msg "$GREEN" "[✓] Сервис sing-box остановлен"
    else
        log_msg "$YELLOW" "[!] Предупреждение: Не удалось остановить сервис sing-box"
    fi
    
    # Удаляем старый исполняемый файл
    if [ -f "${install_dir}/sing-box" ]; then
        rm -f "${install_dir}/sing-box"
        log_msg "$GREEN" "[✓] Старая версия sing-box удалена"
    else
        log_msg "$YELLOW" "[!] Предупреждение: Старая версия sing-box не найдена"
    fi
}

# Function to download and install sing-box with detailed logging using curl
download_and_install() {
    local version_type="$1"
    local version_url="https://api.github.com/repos/${github_repo}/releases"
    local download_url=""
    
    # Если выбрали stable, берём ссылку на последний релиз
    case "$version_type" in
        "stable")
            version_url="${version_url}/latest"
            ;;
    esac
    
    # Получаем ссылку на файл для нашей архитектуры
    download_url=$(curl -s "$version_url" | grep "browser_download_url.*$file" | cut -d '"' -f 4 | head -n 1)
    if [ -z "$download_url" ]; then
        log_msg "$RED" "[✗] Ошибка: Не удалось найти ссылку для скачивания для архитектуры $arch"
        exit 1
    fi

    log_msg "$BLUE" "Ссылка для загрузки: $download_url"

    # Получаем размер файла
    file_size=$(curl -sI "$download_url" | grep -i "Content-Length" | awk '{print $2}' | tr -d '\r')
    if [ -n "$file_size" ] && [ "$file_size" -gt 0 ] 2>/dev/null; then
        # Если получили валидный размер, выводим
        file_size_mb=$(echo "scale=2; $file_size/1048576" | bc 2>/dev/null || echo "$((file_size / 1048576))")
        log_msg "$BLUE" "Размер файла для загрузки: ${file_size_mb} МБ"
    else
        # Иначе пропускаем вывод о размере
        file_size=""
    fi

    # Загружаем файл
    local filename
    filename=$(basename "$download_url")
    log_msg "$BLUE" "Начинается загрузка файла: $filename"

    if command_exists curl; then
        if ! curl -L -o "${temp_dir}/${filename}" "$download_url" --progress-bar 2>>"$log_file"; then
            log_msg "$RED" "[✗] Ошибка: не удалось загрузить файл $filename"
            exit 1
        fi
    else
        log_msg "$RED" "[✗] Ошибка: curl не установлен"
        exit 1
    fi
    
    log_msg "$GREEN" "[✓] Файл $filename успешно загружен"

    # Проверяем целостность (по размеру), если Content-Length не нулевой
    if [ -f "${temp_dir}/${filename}" ]; then
        downloaded_size=$(wc -c < "${temp_dir}/${filename}")
        if [ -n "$file_size" ] && [ "$file_size" -gt 0 ]; then
            if [ "$downloaded_size" -ne "$file_size" ]; then
                log_msg "$RED" "[✗] Ошибка: размер загруженного файла не соответствует ожидаемому"
                log_msg "$RED" "    Ожидаемый размер: $file_size байт, фактический: $downloaded_size байт"
                exit 1
            fi
        fi
    else
        log_msg "$RED" "[✗] Ошибка: файл не был загружен"
        exit 1
    fi

    # Распаковка
    log_msg "$BLUE" "Распаковка архива..."
    local folder_name
    folder_name=$(tar -tzf "${temp_dir}/${filename}" 2>>"$log_file" | head -1 | cut -f1 -d"/")
    if [ -z "$folder_name" ]; then
        log_msg "$RED" "[✗] Ошибка: не удалось определить имя папки в архиве"
        exit 1
    fi
    
    if ! tar -xzf "${temp_dir}/${filename}" -C "$temp_dir" 2>>"$log_file"; then
        log_msg "$RED" "[✗] Ошибка при распаковке архива"
        exit 1
    fi

    # Установка новой версии
    log_msg "$BLUE" "Установка новой версии..."
    if [ ! -f "${temp_dir}/${folder_name}/sing-box" ]; then
        log_msg "$RED" "[✗] Ошибка: исполняемый файл sing-box не найден в распакованном архиве"
        exit 1
    fi
    
    cp "${temp_dir}/${folder_name}/sing-box" "${install_dir}/"
    chmod +x "${install_dir}/sing-box"

    # Проверяем, что исполняемый файл на месте
    if [ ! -x "${install_dir}/sing-box" ]; then
        log_msg "$RED" "[✗] Ошибка: не удалось установить новую версию sing-box"
        log_msg "$RED" "[✗] Требуется ручная установка sing-box"
        exit 1
    fi

    # Очистка временных файлов
    log_msg "$BLUE" "Очистка временных файлов..."
    rm -rf "${temp_dir:?}/${folder_name}" "${temp_dir}/${filename}"
    
    return 0
}

# Function to restart services
restart_services() {
    log_msg "$BLUE" "Перезапуск сервисов..."
    
    # Сначала перезапускаем сеть
    if ! service network restart 2>>"$log_file"; then
        log_msg "$YELLOW" "[!] Предупреждение: Ошибка при перезапуске сети"
        log_msg "$YELLOW" "[!] Рекомендуется перезапустить сеть вручную"
    else
        log_msg "$GREEN" "[✓] Сеть успешно перезапущена"
    fi
    
    # Небольшая пауза, чтобы сеть успела подняться
    sleep 2
    
    # Затем перезапускаем sing-box
    if ! service sing-box restart 2>>"$log_file"; then
        log_msg "$RED" "[✗] Ошибка при перезапуске сервиса sing-box"
        return 1
    fi
    
    log_msg "$GREEN" "[✓] Сервис sing-box успешно перезапущен"
    return 0
}

# Function to check available memory
check_memory() {
    local required_memory=20000  # Required memory in KB (approx 20MB)
    local available_memory=0

    if [ -f "/proc/meminfo" ]; then
        available_memory=$(grep -i 'MemAvailable' /proc/meminfo | awk '{print $2}')
        if [ -z "$available_memory" ]; then
            local mem_free
            local buffers
            local cached
            mem_free=$(grep -i 'MemFree' /proc/meminfo | awk '{print $2}')
            buffers=$(grep -i 'Buffers' /proc/meminfo | awk '{print $2}')
            cached=$(grep -i 'Cached' /proc/meminfo | awk '{print $2}' | head -1)
            if [ -n "$mem_free" ] && [ -n "$buffers" ] && [ -n "$cached" ]; then
                available_memory=$((mem_free + buffers + cached))
            fi
        fi
    fi
    
    # Если не получилось узнать через /proc/meminfo, пробуем через free
    if [ -z "$available_memory" ] || [ "$available_memory" -eq 0 ]; then
        if command_exists free; then
            available_memory=$(free | grep -i 'Mem:' | awk '{print $7}')
        fi
    fi
    
    if [ -z "$available_memory" ] || [ "$available_memory" -eq 0 ]; then
        log_msg "$YELLOW" "[!] Предупреждение: Не удалось проверить доступную память"
        return 0
    fi
    
    if [ "$available_memory" -lt "$required_memory" ]; then
        log_msg "$RED" "[✗] Ошибка: Недостаточно оперативной памяти для обновления"
        log_msg "$RED" "    Доступно: $((available_memory / 1024)) МБ, требуется минимум: $((required_memory / 1024)) МБ"
        return 1
    fi
    
    log_msg "$GREEN" "[✓] Достаточно оперативной памяти для обновления"
    return 0
}

# Main function
main() {
    create_dirs
    
    # Если параметр rollback, делаем откат
    if [ "$1" = "rollback" ]; then
        rollback
        exit 0
    fi
    
    # Определяем архитектуру
    detect_architecture
    
    # Меню выбора типа версии
    printf "Выберите тип версии:\n"
    printf "1. Релизная (stable)\n"
    printf "2. Альфа (alpha)\n"
    printf "3. Бета (beta)\n"
    printf "Введите ваш выбор (1, 2, 3): "
    read choice < /dev/tty
    
    local version_type
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
    
    # Текущая и последняя версия
    local current_version
    current_version=$(get_current_version)
    local latest_version
    latest_version=$(get_latest_version "$version_type")
    
    # Проверяем, нужна ли установка
    if [ "$current_version" = "$latest_version" ]; then
        log_msg "$GREEN" "[✓] Уже установлена последняя версия: $current_version"
        exit 0
    fi
    
    log_msg "$BLUE" "Обновляем с версии $current_version до $latest_version"
    
    # Останавливаем сервис перед удалением
    if service sing-box stop 2>>"$log_file"; then
        log_msg "$GREEN" "[✓] Сервис sing-box остановлен"
    else
        log_msg "$YELLOW" "[!] Предупреждение: Не удалось остановить сервис sing-box"
    fi
    
    # Удаляем старую версию
    if [ -f "${install_dir}/sing-box" ]; then
        rm -f "${install_dir}/sing-box"
        log_msg "$GREEN" "[✓] Старая версия sing-box удалена"
    else
        log_msg "$YELLOW" "[!] Предупреждение: Старая версия sing-box не найдена"
    fi
    
    # Проверяем доступное место
    if ! check_disk_space; then
        log_msg "$RED" "[✗] Обновление отменено из-за нехватки дискового пространства"
        exit 1
    fi
    
    # Проверяем память
    if ! check_memory; then
        log_msg "$RED" "[✗] Обновление отменено из-за нехватки памяти"
        exit 1
    fi
    
    # Скачивание и установка
    download_and_install "$version_type"
    
    # Перезапуск сервисов
    if ! restart_services; then
        log_msg "$RED" "[✗] Ошибка при обновлении. Выполняется откат..."
        rollback
        exit 1
    fi
    
    log_msg "$GREEN" "[✓] Обновление завершено успешно до версии $latest_version"
    exit 0
}

# Запускаем основную функцию
main "$@"