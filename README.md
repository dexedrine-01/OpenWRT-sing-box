## Установка и обновление sing-box на роутерах с прошивкой OpenWRT

#### 📥 Установка sing-box

- Загрузка необходимых пакетов
- Автоматическая настройка зон фаерволла

```bash
sh <(wget -O - https://raw.githubusercontent.com/itdoginfo/domain-routing-openwrt/master/getdomains-install.sh)
```

1. Туннель: **sing-box**
2. Установка DNSCrypt2 или Stubby: **No**
3. Выбор страны: **Skip script creation**

------------

#### 📦 Обновление версии sing-box для OpenWRT

- Проверка архитектуры и выбор подходящего пакета
- Загрузка последней версии sing-box с GitHub
- Автоматическая установка и перезапуск сервиса

```bash
wget -qO- https://raw.githubusercontent.com/dexedrine-01/OpenWRT-sing-box/main/update_sing-box.sh | sh
```
**Рекомендуется выбирать стабильную релизную версию!**

------------

#### 📦 Обновление версии sing-box на сервере

```bash
wget -qO- https://raw.githubusercontent.com/dexedrine-01/OpenWRT-sing-box/main/update_sing-box_server.sh | sh
```

------------

#### 🔄 Обновление профиля

- Загрузка JSON-конфигурации по ссылке пользователя

```bash
wget -qO- https://raw.githubusercontent.com/dexedrine-01/OpenWRT-sing-box/main/update_config.sh | sh
```

------------

#### 🔄 Обновление панели Zashboard

```bash
wget -qO- https://raw.githubusercontent.com/dexedrine-01/OpenWRT-sing-box/main/update_zashboard.sh | sh
```
