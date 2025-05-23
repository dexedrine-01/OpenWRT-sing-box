#!/bin/sh
# Script for updating sing-box to the latest version with architecture detection

# --- Автоматическая настройка локали для поддержки русского языка ---
# Проверяем доступные локали и выставляем подходящую
if command -v locale >/dev/null 2>&1; then
    if locale -a | grep -qi '^ru_RU\.utf-8$'; then
        export LANG=ru_RU.UTF-8
        export LC_ALL=ru_RU.UTF-8
        export LC_CTYPE=ru_RU.UTF-8
    elif locale -a | grep -qi '^C\.utf-8$'; then
        export LANG=C.UTF-8
        export LC_ALL=C.UTF-8
        export LC_CTYPE=C.UTF-8
    elif locale -a | grep -qi '^en_US\.utf-8$'; then
        export LANG=en_US.UTF-8
        export LC_ALL=en_US.UTF-8
        export LC_CTYPE=en_US.UTF-8
    else
        export LANG=C
        export LC_ALL=C
        export LC_CTYPE=C
    fi
else
    export LANG=C.UTF-8
    export LC_ALL=C.UTF-8
    export LC_CTYPE=C.UTF-8
fi
# --- конец блока локалей ---

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

    # Все сообщения только в stderr!
    log_msg "$BLUE" "Получение последней версии для $version_type..." >&2

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
            if [ -z "$latest_version" ]; then
                log_msg "$YELLOW" "[!] Не удалось получить последнюю бета-версию через API, используем фиксированную версию" >&2
                latest_version="1.12.0-beta.13"
            fi
            ;;
    esac

    log_msg "$BLUE" "Полученная версия: $latest_version" >&2

    if [ -z "$latest_version" ]; then
        log_msg "$RED" "[✗] Ошибка: Не удалось получить информацию о последней версии" >&2
        exit 1
    fi

    # Только номер версии в stdout!
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

# Function to check if the system is OpenWRT 24+
is_openwrt_24plus() {
    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release
        if [ -n "$DISTRIB_RELEASE" ]; then
            major=$(echo "$DISTRIB_RELEASE" | cut -d. -f1)
            if [ "$major" -ge 24 ]; then
                return 0
            fi
        fi
    fi
    return 1
}

# Function to get the name of the .ipk file for OpenWRT 24.10 based on architecture and CPU
get_openwrt_ipk_filename() {
    local arch=$(uname -m)
    local cpuinfo
    cpuinfo=$(cat /proc/cpuinfo 2>/dev/null)
    local arch_list
    arch_list=$(opkg print-architecture 2>/dev/null | awk '{print $2}')
    local latest="$latest_version"
    local found=0
    
    # log_msg "$BLUE" "Поиск .ipk файла для архитектуры $arch и версии $latest_version" >&2
    
    if [ -z "$latest" ] || [[ "$latest" == *"Ошибка"* ]]; then
        log_msg "$RED" "[✗] Некорректная версия: $latest" >&2
        exit 1
    fi

    # log_msg "$BLUE" "Список поддерживаемых архитектур: $arch_list" >&2
    
    if [ "$arch" = "aarch64" ]; then
        for candidate in aarch64_cortex-a53 aarch64_cortex-a72 aarch64_cortex-a76 aarch64_generic; do
            if echo "$arch_list" | grep -q "$candidate"; then
                # log_msg "$GREEN" "[✓] Найдена поддерживаемая архитектура: $candidate" >&2
                echo "sing-box_${latest}_openwrt_${candidate}.ipk"
                return 0
            fi
        done
        # log_msg "$YELLOW" "[!] Архитектура не найдена в списке, используем aarch64_cortex-a53 по умолчанию" >&2
        echo "sing-box_${latest}_openwrt_aarch64_cortex-a53.ipk"
        return 0
    elif [ "$arch" = "x86_64" ]; then
        echo "sing-box_${latest}_openwrt_x86_64.ipk"
        return 0
    elif [ "$arch" = "i386" ] || [ "$arch" = "i686" ]; then
        echo "sing-box_${latest}_openwrt_i386_pentium4.ipk"
        return 0
    elif [ "$arch" = "armv7l" ] || [ "$arch" = "armv6l" ] || [ "$arch" = "arm" ]; then
        echo "sing-box_${latest}_openwrt_arm_cortex-a7.ipk"
        return 0
    elif [ "$arch" = "mips" ]; then
        echo "sing-box_${latest}_openwrt_mips_24kc.ipk"
        return 0
    fi
    
    log_msg "$RED" "[✗] Не удалось определить .ipk файл для вашей архитектуры: $arch" >&2
    exit 1
}

# Function to download and install sing-box with detailed logging using curl
download_and_install() {
    local version_type="$1"
    local version_url="https://api.github.com/repos/${github_repo}/releases"
    local download_url=""

    if is_openwrt_24plus; then
        local ipk_filename
        ipk_filename=$(get_openwrt_ipk_filename)
        
        # log_msg "$BLUE" "Получение ссылки для скачивания файла $ipk_filename..."
        
        if [[ "$latest_version" == *"beta"* ]]; then
            download_url="https://github.com/SagerNet/sing-box/releases/download/v${latest_version}/${ipk_filename}"
            # log_msg "$BLUE" "Сформирован URL для бета-версии: $download_url"
        else
            download_url=$(curl -s "$version_url" | grep -o "\"browser_download_url\":\"[^\"]*${ipk_filename}\"" | cut -d '"' -f 4 | head -n 1)
            if [ -z "$download_url" ]; then
                download_url="https://github.com/SagerNet/sing-box/releases/download/v${latest_version}/${ipk_filename}"
                # log_msg "$YELLOW" "[!] URL не найден через API, сформирован напрямую: $download_url"
            fi
        fi
        
        # log_msg "$BLUE" "Проверка доступности файла: $download_url"
        local http_code
        http_code=$(curl -sI "$download_url" | grep -i "HTTP/" | awk '{print $2}')
        
        if [ "$http_code" != "200" ] && [ "$http_code" != "302" ]; then
            log_msg "$RED" "[✗] Ошибка: файл не найден по URL (HTTP код: $http_code)"
            log_msg "$RED" "[✗] URL: $download_url"
            exit 1
        fi
        
        log_msg "$GREEN" "[✓] Файл найден."
        log_msg "$BLUE" "Ссылка для загрузки: $download_url"
        
        [ ! -d "$temp_dir" ] && mkdir -p "$temp_dir"
        
        log_msg "$BLUE" "Загрузка файла $ipk_filename..."
        if ! curl -L -o "${temp_dir}/${ipk_filename}" "$download_url" --progress-bar 2>>"$log_file"; then
            log_msg "$RED" "[✗] Ошибка: не удалось загрузить файл $ipk_filename"
            exit 1
        fi
        log_msg "$GREEN" "[✓] Файл $ipk_filename успешно загружен"
        
        if [ -f "${temp_dir}/${ipk_filename}" ] && [ -s "${temp_dir}/${ipk_filename}" ]; then
            local file_size
            file_size=$(du -h "${temp_dir}/${ipk_filename}" | cut -f1)
            # log_msg "$BLUE" "Размер загруженного файла: $file_size"
            
            log_msg "$BLUE" "Установка sing-box..."
            opkg_output=$(opkg install --force-reinstall "${temp_dir}/${ipk_filename}" 2>&1)
            echo "$opkg_output" | while IFS= read -r line; do
                case "$line" in
                    "Package * has no valid architecture, ignoring.")
                        log_msg "$YELLOW" "[!] Пакет не поддерживает архитектуру, пропускаем."
                        ;;
                    "No packages removed.")
                        log_msg "$YELLOW" "[!] Пакеты не были удалены."
                        ;;
                    "Installing sing-box "*"to root..."*)
                        log_msg "$BLUE" "[→] Установка sing-box ($ipk_filename) в систему..."
                        ;;
                    "Configuring sing-box.")
                        log_msg "$BLUE" "[→] Конфигурирование sing-box."
                        ;;
                    *)
                        # log_msg "$BLUE" "[i] $line"
                        ;;
                esac
            done
            
            if command -v sing-box > /dev/null 2>&1; then
                log_msg "$GREEN" "[✓] sing-box успешно установлен"
                local installed_version
                installed_version=$(sing-box version 2>/dev/null | head -n 1 | awk '{print $3}')
                if [ -n "$installed_version" ]; then
                    log_msg "$GREEN" "[✓] Установлена версия sing-box: $installed_version"
                fi
            else
                log_msg "$RED" "[✗] Ошибка: sing-box не был установлен или не добавлен в PATH"
                exit 1
            fi
        else
            log_msg "$RED" "[✗] Ошибка: .ipk файл не найден или имеет нулевой размер по пути ${temp_dir}/${ipk_filename}"
            exit 1
        fi
        return 0
    fi

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