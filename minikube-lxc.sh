Проблема в том, что ты используешь функции вроде `header_info`, `select_storage`, `msg_error`, `msg_ok`, которые определены в `functions.sh` из community-scripts, но этот файл не был загружен — потому и идёт ошибка.

В community-scripts правильная структура следующая:

```bash
#!/usr/bin/env bash

YWV_CHECK="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/functions.sh"
source <(curl -fsSL ${YWV_CHECK}) || { echo "[ERROR] Failed to load functions"; exit 1; }

header_info "Installing Minikube LXC / Установка Minikube в LXC"

# Получаем ID контейнера
CTID=$(pvesh get /cluster/nextid)

# Выбираем хранилища
STORAGE=$(select_storage "rootdir")
TEMPLATE_STORAGE=$(select_storage "vztmpl")

# Загружаем Debian 12 шаблон
TEMPLATE=$(pveam available -section system | grep debian-12 | tail -n 1 | awk '{print $1}')
if [ -z "$TEMPLATE" ]; then
    msg_error "No Debian 12 template found / Шаблон Debian 12 не найден"
fi
pveam download "$TEMPLATE_STORAGE" "$TEMPLATE" || msg_error "Failed to download template / Не удалось загрузить шаблон"

# Создаем контейнер
pct create $CTID "$TEMPLATE_STORAGE:vztmpl/$TEMPLATE" \
    -hostname minikube \
    -cores 2 \
    -memory 4096 \
    -net0 name=eth0,bridge=vmbr0,ip=dhcp \
    -features nesting=1 \
    -rootfs "$STORAGE:8" \
    -password rootPass123 \
    -onboot 1 || msg_error "Failed to create LXC / Не удалось создать LXC контейнер"

# Запускаем контейнер
pct start $CTID || msg_error "Failed to start LXC / Не удалось запустить LXC контейнер"

# Устанавливаем Minikube и зависимости
pct exec $CTID -- bash -c "apt-get update && apt-get install -y curl apt-transport-https ca-certificates gnupg lsb-release"
pct exec $CTID -- bash -c "curl -fsSL https://get.docker.com | sh"
pct exec $CTID -- bash -c "curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x kubectl && mv kubectl /usr/local/bin/"
pct exec $CTID -- bash -c "curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 && install minikube-linux-amd64 /usr/local/bin/minikube"

# Запускаем Minikube
pct exec $CTID -- bash -c "minikube start --driver=docker"

msg_ok "LXC container with Minikube created successfully! / LXC контейнер с Minikube успешно создан!"
```

В этой версии `functions.sh` точно подключается, а пароль у контейнера сделан валидным (минимум 5 символов), чтобы избежать ошибок.
