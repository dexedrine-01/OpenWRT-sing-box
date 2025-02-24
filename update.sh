#!/bin/sh
# Скрипт для OpenWRT: модификация JSON из подписки
# Определяем цвета (жирный текст)
BLUE="\033[1;34m"
GREEN="\033[1;32m"
RED="\033[1;31m"
RESET="\033[0m"

# 1. Запрос ссылки у пользователя (читаем с терминала)
printf "${BLUE}**Вставьте ссылку на вашу подписку (вы можете её найти в боте, по кнопке \"Доступ к VPN - Поделиться подпиской\"):**${RESET}\n" >&2
read SUB_URL < /dev/tty

if [ -z "$SUB_URL" ]; then
    printf "${RED}**Ошибка: ссылка не введена!**${RESET}\n" >&2
    exit 1
fi

# 2. Формируем URL для загрузки (добавляем /sing-box)
DOWNLOAD_URL="${SUB_URL}/sing-box"
printf "${BLUE}**Загружаем JSON из: ${DOWNLOAD_URL} ...**${RESET}\n"

# 3. Загружаем JSON-файл (используем wget)
TMP_FILE="/tmp/subscription.json"
wget -q -O "${TMP_FILE}" "${DOWNLOAD_URL}"
if [ $? -ne 0 ]; then
    printf "${RED}**Ошибка при загрузке файла!**${RESET}\n"
    exit 1
fi
printf "${GREEN}**Файл успешно загружен.**${RESET}\n"

# 4. Заменяем "stack": "mixed" на "stack": "system"
sed -i 's/"stack": "mixed"/"stack": "system"/' "${TMP_FILE}"
if [ $? -eq 0 ]; then
    printf "${GREEN}**Значение stack изменено на system.**${RESET}\n"
else
    printf "${RED}**Ошибка при изменении stack!**${RESET}\n"
fi

# 5. Вставляем "auto_redirect": true, после "auto_route": true,
sed -i '/"auto_route": true,/a\    "auto_redirect": true,' "${TMP_FILE}"
if [ $? -eq 0 ]; then
    printf "${GREEN}**В inbound добавлен параметр auto_redirect.**${RESET}\n"
else
    printf "${RED}**Ошибка при добавлении auto_redirect!**${RESET}\n"
fi

# 6. Добавляем блок experimental перед последней закрывающей скобкой
sed -i '$ s/}/,\n  "experimental": {\n    "clash_api": {\n      "external_ui": "zashboard",\n      "external_controller": "0.0.0.0:9090",\n      "external_ui_download_url": "https:\/\/github.com\/Zephyruso\/zashboard\/archive\/gh-pages.zip",\n      "external_ui_download_detour": "↔️ Direct"\n    },\n    "cache_file": {\n      "enabled": true,\n      "store_rdrc": true\n    }\n  }\n}/' "${TMP_FILE}"
if [ $? -eq 0 ]; then
    printf "${GREEN}**Блок experimental успешно добавлен.**${RESET}\n"
else
    printf "${RED}**Ошибка при добавлении блока experimental!**${RESET}\n"
fi

# 7. Установка полученной конфигурации
if [ ! -d /etc/sing-box ]; then
    mkdir -p /etc/sing-box
fi

if [ -f /etc/sing-box/config.json ]; then
    rm -f /etc/sing-box/config.json
fi

mv "${TMP_FILE}" /etc/sing-box/config.json
if [ $? -eq 0 ]; then
    printf "${GREEN}**Конфигурация успешно установлена в /etc/sing-box/config.json.**${RESET}\n"
else
    printf "${RED}**Ошибка при установке конфигурации!**${RESET}\n"
fi

service sing-box reload
if [ $? -eq 0 ]; then
    printf "${GREEN}**Сервис sing-box перезагружен.**${RESET}\n"
else
    printf "${RED}**Ошибка при перезагрузке sing-box!**${RESET}\n"
fi

# Получаем IP роутера из конфигурации OpenWRT
ROUTER_IP=$(uci get network.lan.ipaddr 2>/dev/null)
if [ -z "$ROUTER_IP" ]; then
    ROUTER_IP="IP_роутера"
fi

# 8. Вывод финального сообщения
printf "${GREEN}**Обновление профиля завершено успешно!\nПанель для управления VPN: ${ROUTER_IP}:9090**${RESET}\n"