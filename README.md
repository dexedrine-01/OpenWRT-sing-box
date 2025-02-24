# PurrNet
Инструкция по установке VPN от команды PurrNet на роутеры с прошивкой OpenWRT. Пожалуйста, выполните действия по порядку.

#### Установка sing-box

- Выполняется загрузка необходимых пакетов
- Выполняется автоматическая настройка firewall

```bash
sh <(wget -O - https://raw.githubusercontent.com/itdoginfo/domain-routing-openwrt/master/getdomains-install.sh)
```

**Туннель: **sing-box
**Установка DNSCrypt2 или Stubby:** No
**Выбор страны:** Skip script creation

------------

#### Обновление версии sing-box

- Выполняется загрузка последней версии sing-box с репозитория SagerNet
- Пользователь может выбрать версию (альфа, бета, релиз)

```bash
wget -qO- https://raw.githubusercontent.com/dexedrine-01/PurrNet/main/update_sing-box.sh | sh
```
**⚠️ Рекомендуется выбирать стабильную релизную версию (stable)!**

------------

#### Обновление профиля

- Выполняется JSON-конфигурации профиля по ссылке пользователя
- Выполняется модификация конфигурации для роутера
- Пользователь может выбрать добавлять ли обновление подписки в автозапуск (если вы не планируете менять конфигурацию, рекомендуется включить)

```bash
wget -qO- https://raw.githubusercontent.com/dexedrine-01/PurrNet/main/update_config.sh | sh
```
