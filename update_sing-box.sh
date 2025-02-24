#!/bin/sh

log_file="/var/log/sing-box-update.log"

# Проверяем и создаем директории, если их нет
[ ! -d "/opt/bin" ] && mkdir -p /opt/bin
[ ! -d "/var/log" ] && mkdir -p /var/log

# Определяем архитектуру и выбираем правильный файл
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
  *)
    echo -e "\033[1;31m[✗] Ошибка: Архитектура $arch не поддерживается\033[0m" | tee -a "$log_file"
    exit 1
    ;;
esac

echo -e "\033[1;32m[✓] Архитектура поддерживается: $arch\033[0m" | tee -a "$log_file"

# Функция отката к предыдущей версии
rollback() {
  if [ -f /usr/bin/sing-box.old ]; then
    echo "Откатываемся на предыдущую версию..." | tee -a "$log_file"
    mv /usr/bin/sing-box.old /usr/bin/sing-box
    chmod +x /usr/bin/sing-box
    service sing-box restart 2>>"$log_file"
    if [ $? -eq 0 ]; then
      echo -e "\033[1;32m[✓] Откат выполнен успешно\033[0m" | tee -a "$log_file"
    else
      echo -e "\033[1;31m[✗] Ошибка при откате и перезапуске sing-box\033[0m" | tee -a "$log_file"
      exit 1
    fi
  else
    echo -e "\033[1;31m[✗] Предыдущая версия не найдена!\033[0m" | tee -a "$log_file"
    exit 1
  fi
}

# Проверяем аргумент для отката
if [ "$1" = "rollback" ]; then
  rollback
  exit 0
fi

# Меню выбора версии
echo "Выберите тип версии:"
echo "1. Релизная (stable)"
echo "2. Альфа (alpha)"
echo "3. Бета (beta)"
read -p "Введите ваш выбор (1, 2, 3): " choice

case "$choice" in
  1)
    echo "Вы выбрали релизную версию" | tee -a "$log_file"
    version_url="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
    ;;
  2)
    echo "Вы выбрали альфа-версию" | tee -a "$log_file"
    version_url="https://api.github.com/repos/SagerNet/sing-box/releases"
    ;;
  3)
    echo "Вы выбрали бета-версию" | tee -a "$log_file"
    version_url="https://api.github.com/repos/SagerNet/sing-box/releases"
    ;;
  *)
    echo -e "\033[1;31m[✗] Ошибка: Некорректный выбор. Пожалуйста, выберите 1, 2 или 3.\033[0m" | tee -a "$log_file"
    exit 1
    ;;
esac

# Получаем текущую версию sing-box
current_version=$(sing-box version | head -n 1 | awk '{print $3}')

# Получаем последнюю версию с GitHub
if [ "$choice" = "2" ]; then
  latest_version=$(curl -s "$version_url" | grep '"tag_name":' | head -n 1 | cut -d '"' -f 4 | sed 's/v//')
elif [ "$choice" = "3" ]; then
  latest_version=$(curl -s "$version_url" | grep '"tag_name":' | grep "beta" | head -n 1 | cut -d '"' -f 4 | sed 's/v//')
else
  latest_version=$(curl -s "$version_url" | grep '"tag_name":' | cut -d '"' -f 4 | sed 's/v//')
fi

# Сравниваем версии
if [ "$current_version" = "$latest_version" ]; then
  echo -e "\033[1;32m[✓] Уже установлена последняя версия: $current_version\033[0m" | tee -a "$log_file"
  exit 0
fi

echo "Обновляем с версии $current_version до $latest_version" | tee -a "$log_file"

# Скачиваем и устанавливаем последнюю версию для текущей архитектуры
url=$(curl -s "$version_url" | grep "browser_download_url.*$file" | cut -d '"' -f 4 | head -n 1)
filename=$(basename "$url")
wget -O "/opt/bin/$filename" "$url" 2>>"$log_file"

if [ $? -ne 0 ]; then
  echo -e "\033[1;31m[✗] Ошибка: не удалось загрузить файл $filename\033[0m" | tee -a "$log_file"
  exit 1
else
  echo -e "\033[1;32m[✓] Файл $filename успешно загружен\033[0m" | tee -a "$log_file"
fi

# Распаковываем и копируем бинарник
tar -xvzf "/opt/bin/$filename" -C /opt/ 2>>"$log_file"
folder_name=$(tar -tzf "/opt/bin/$filename" | head -1 | cut -f1 -d"/")

# Перемещаем старую версию, если она существует
if [ -f /usr/bin/sing-box ]; then
  mv /usr/bin/sing-box /usr/bin/sing-box.old
fi

# Копируем новую версию
cp /opt/"$folder_name"/sing-box /usr/bin/
chmod +x /usr/bin/sing-box

# Перезапуск сервисов
service sing-box restart 2>>"$log_file"
if [ $? -eq 0 ]; then
  echo -e "\033[1;32m[✓] Обновление завершено успешно до версии $latest_version\033[0m" | tee -a "$log_file"
  service network restart 2>>"$log_file"
  if [ $? -eq 0 ]; then
    echo -e "\033[1;32m[✓] Сеть успешно перезапущена\033[0m" | tee -a "$log_file"
  else
    echo -e "\033[1;31m[✗] Ошибка при перезапуске сети\033[0m" | tee -a "$log_file"
    exit 1
  fi
else
  echo -e "\033[1;31m[✗] Ошибка при перезапуске сервиса sing-box\033[0m" | tee -a "$log_file"
  rollback
  exit 1
fi
