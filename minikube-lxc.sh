#!/usr/bin/env bash

YWV_CHECK="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/functions.sh"

# Load common functions / Загрузка общих функций
if ! source <(curl -fsSL ${YWV_CHECK}); then
    echo "[ERROR] Failed to load community-scripts functions / Не удалось загрузить функции community-scripts"
    exit 1
fi

header_info "Installing Minikube LXC / Установка Minikube в LXC"

# Get next container ID / Получение следующего ID контейнера
CTID=$(pvesh get /cluster/nextid)

# Select storage for container / Выбор хранилища для контейнера
STORAGE=$(select_storage "rootdir")
TEMPLATE_STORAGE=$(select_storage "vztmpl")

# Download Debian 12 template / Загрузка шаблона Debian 12
TEMPLATE=$(pveam available -section system | grep debian-12 | tail -n 1 | awk '{print $1}')
if [ -z "$TEMPLATE" ]; then
    msg_error "No Debian 12 template found / Шаблон Debian 12 не найден"
fi
pveam download $TEMPLATE_STORAGE $TEMPLATE || msg_error "Failed to download template / Не удалось загрузить шаблон"

# Create LXC container / Создание LXC контейнера
pct create $CTID $TEMPLATE_STORAGE:vztmpl/$TEMPLATE \
    -hostname minikube \
    -cores 2 \
    -memory 4096 \
    -net0 name=eth0,bridge=vmbr0,ip=dhcp \
    -features nesting=1 \
    -rootfs $STORAGE:8 \
    -password root \
    -onboot 1 || msg_error "Failed to create LXC / Не удалось создать LXC контейнер"

# Start container / Запуск контейнера
pct start $CTID || msg_error "Failed to start LXC / Не удалось запустить LXC контейнер"

# Install Docker, kubectl, Minikube inside container / Установка Docker, kubectl, Minikube в контейнере
pct exec $CTID -- bash -c "apt-get update && apt-get install -y curl apt-transport-https ca-certificates gnupg lsb-release"

pct exec $CTID -- bash -c "curl -fsSL https://get.docker.com | sh"

pct exec $CTID -- bash -c "curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x kubectl && mv kubectl /usr/local/bin/"

pct exec $CTID -- bash -c "curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 && install minikube-linux-amd64 /usr/local/bin/minikube"

# Start Minikube / Запуск Minikube
pct exec $CTID -- bash -c "minikube start --driver=docker"

msg_ok "LXC container with Minikube created successfully! / LXC контейнер с Minikube успешно создан!"
