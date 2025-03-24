# sing-box для OpenWRT

🛜 Инструкция по установке и обновлению sing-box на роутеры с прошивкой OpenWRT.

------------

#### 📥 Установка sing-box

- Выполняется загрузка необходимых пакетов
- Выполняется автоматическая настройка firewall

```bash
sh <(wget -O - https://raw.githubusercontent.com/itdoginfo/domain-routing-openwrt/master/getdomains-install.sh)
```

1. Туннель: **sing-box**
2. Установка DNSCrypt2 или Stubby: **No**
3. Выбор страны: **Skip script creation**

------------

#### 📦 Обновление версии sing-box

- Выполняется загрузка последней версии sing-box с репозитория SagerNet
- Пользователю предоставляется возможность выбрать версию (альфа, бета, релиз)

```bash
wget -qO- https://raw.githubusercontent.com/dexedrine-01/PurrNet/main/update_sing-box.sh | sh
```
**Рекомендуется выбирать стабильную релизную версию!**

------------

#### 🔄 Обновление профиля

- Выполняется загрузка JSON-конфигурации по ссылке от пользователя

```bash
wget -qO- https://raw.githubusercontent.com/dexedrine-01/PurrNet/main/update_config.sh | sh
```
