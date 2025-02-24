#!/bin/sh
# Скрипт для OpenWRT: модификация JSON из подписки с добавлением российского подключения

# Определяем цвета (жирный текст)
BLUE="\033[1;34m"
GREEN="\033[1;32m"
RED="\033[1;31m"
RESET="\033[0m"

# 1. Запрос ссылки у пользователя (читаем с терминала, без цвета и с вводом на той же строке)
printf "Вставьте ссылку на вашу подписку: " >&2
read SUB_URL < /dev/tty
if [ -z "$SUB_URL" ]; then
    printf "${RED}Ошибка: ссылка не введена!${RESET}\n" >&2
    exit 1
fi

# 2. Формируем URL для загрузки основного JSON (добавляем /sing-box)
DOWNLOAD_URL="${SUB_URL}/sing-box"
printf "${BLUE}– Загружаем JSON из: ${DOWNLOAD_URL} ...${RESET}\n"

# 3. Загружаем основной JSON-файл (используем wget)
TMP_FILE="/tmp/subscription.json"
wget -q -O "${TMP_FILE}" "${DOWNLOAD_URL}"
if [ $? -ne 0 ]; then
    printf "${RED}Ошибка при загрузке основного файла!${RESET}\n"
    exit 1
fi
printf "${BLUE}– Конфигурация успешно загружена${RESET}\n"

# 4. Модификация основного JSON:
# 4.1 Заменяем "stack": "mixed" на "stack": "system"
sed -i 's/"stack": "mixed"/"stack": "system"/' "${TMP_FILE}"
if [ $? -eq 0 ]; then
    printf "${BLUE}– Значение stack изменено на system${RESET}\n"
else
    printf "${RED}Ошибка при изменении stack!${RESET}\n"
fi

# 4.2 Вставляем "auto_redirect": true, после "auto_route": true,
sed -i '/"auto_route": true,/a\    "auto_redirect": true,' "${TMP_FILE}"
if [ $? -eq 0 ]; then
    printf "${BLUE}– Параметр auto_redirect добавлен${RESET}\n"
else
    printf "${RED}Ошибка при добавлении auto_redirect!${RESET}\n"
fi

# 4.3 Добавляем блок experimental перед последней закрывающей скобкой
sed -i '$ s/}/,\n  "experimental": {\n    "clash_api": {\n      "external_ui": "zashboard",\n      "external_controller": "0.0.0.0:9090",\n      "external_ui_download_url": "https:\/\/github.com\/Zephyruso\/zashboard\/archive\/gh-pages.zip",\n      "external_ui_download_detour": "↔️ Direct"\n    },\n    "cache_file": {\n      "enabled": true,\n      "store_rdrc": true\n    }\n  }\n}/' "${TMP_FILE}"
if [ $? -eq 0 ]; then
    printf "${BLUE}– Блок experimental добавлен${RESET}\n"
else
    printf "${RED}Ошибка при добавлении блока experimental!${RESET}\n"
fi

# 5. Установка полученной основной конфигурации
if [ ! -d /etc/sing-box ]; then
    mkdir -p /etc/sing-box
fi
if [ -f /etc/sing-box/config.json ]; then
    rm -f /etc/sing-box/config.json
fi
mv "${TMP_FILE}" /etc/sing-box/config.json
if [ $? -eq 0 ]; then
    printf "${BLUE}– Конфигурация установлена в /etc/sing-box/config.json${RESET}\n"
else
    printf "${RED}Ошибка при установке конфигурации!${RESET}\n"
fi

# 6. Обновление пакетов OpenWRT и установка jq...
printf "${BLUE}– Обновление пакетов OpenWRT и установка jq...${RESET}\n"
opkg update && opkg install jq

# 7. Загрузка дополнительного JSON для российского подключения (sing-box-ru)
TMP_RU="/tmp/sing-box-ru.json"
DOWNLOAD_URL_RU="${SUB_URL}/sing-box-ru"
wget -q -O "${TMP_RU}" "${DOWNLOAD_URL_RU}"
if [ $? -ne 0 ]; then
    printf "${RED}Ошибка при загрузке файла sing-box-ru!${RESET}\n"
else
    printf "${BLUE}– JSON-файл с подключением к России успешно загружен${RESET}\n"
    # Извлекаем outbound, где tag содержит "Russia"
    RUS_OUTBOUND=$(jq -c '(.outbounds[] | select(.tag | contains("Russia"))) | select(.)' "${TMP_RU}")
    if [ -n "$RUS_OUTBOUND" ]; then
         printf "${BLUE}– Найдено подключение к РФ серверу${RESET}\n"
         # Добавляем в основной конфиг: сначала outbound direct, затем российский outbound
         UPDATED_CONFIG=$(jq --argjson rus "$RUS_OUTBOUND" '.outbounds += [ {"type": "direct", "tag": "↔️ Direct"}, $rus ]' /etc/sing-box/config.json)
         if [ $? -eq 0 ]; then
              printf "${BLUE}– РФ сервер успешно добавлен${RESET}\n"
              echo "$UPDATED_CONFIG" > /etc/sing-box/config.json
         else
              printf "${RED}Ошибка при добавлении российского outbound!${RESET}\n"
         fi
    else
         printf "${RED}Не найден outbound с тегом Russia в sing-box-ru JSON.${RESET}\n"
    fi
fi

# 8. Обновляем selector, добавляя в его outbounds "🇷🇺 Russia [VLESS]"
UPDATED_CONFIG=$(jq '(.outbounds[] | select(.type=="selector" and .tag=="🌐 Proxy").outbounds) += ["🇷🇺 Russia [VLESS]"]' /etc/sing-box/config.json)
if [ $? -eq 0 ]; then
    printf "${BLUE}– Селектор обновлён добавлением российского подключения${RESET}\n"
    echo "$UPDATED_CONFIG" > /etc/sing-box/config.json
else
    printf "${RED}Ошибка при обновлении селектора!${RESET}\n"
fi

# 9. Форматирование (beautify) и проверка итогового JSON
jq . /etc/sing-box/config.json > /tmp/config_beauty.json && mv /tmp/config_beauty.json /etc/sing-box/config.json
if [ $? -eq 0 ]; then
    # Проверка конфигурации через sing-box check (если доступна)
    sing-box check -c /etc/sing-box/config.json >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        printf "${BLUE}– Конфигурация отформатирована и проверена${RESET}\n"
    else
        printf "${RED}Ошибка при проверке конфигурации!${RESET}\n"
    fi
else
    printf "${RED}Ошибка при форматировании конфигурации!${RESET}\n"
fi

# 10. Перезагрузка сервиса sing-box без разрыва соединения
service sing-box reload
if [ $? -eq 0 ]; then
    printf "${BLUE}– Сервис sing-box перезапущен без разрыва соединения.${RESET}\n"
else
    printf "${RED}Ошибка при перезагрузке sing-box!${RESET}\n"
fi

# 11. Получаем IP роутера из конфигурации OpenWRT
ROUTER_IP=$(uci get network.lan.ipaddr 2>/dev/null)
if [ -z "$ROUTER_IP" ]; then
    ROUTER_IP="IP_роутера"
fi

# 12. Вывод финального сообщения
printf "${GREEN}Обновление профиля завершено успешно!${RESET}\n"
printf "Панель для управления VPN: http://%s:9090\n" "$ROUTER_IP"