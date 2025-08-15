#!/usr/bin/env bash

# Function to display a message and exit / Функция для отображения сообщения и выхода
function msg_error_exit {
    echo -e "\n[ERROR] $1" >&2
    exit 1
}

# Function to prompt for storage selection / Функция для запроса выбора хранилища
function select_storage {
    local STORAGE_TYPE=$1
    local STORAGE_LIST=$(pvesm status -content $STORAGE_TYPE | awk 'NR>1 {print $1}')
    [ -z "$STORAGE_LIST" ] && msg_error_exit "No storage found for type: $STORAGE_TYPE / Не найдено хранилище для типа: $STORAGE_TYPE"
    echo "Select $STORAGE_TYPE storage: / Выберите хранилище $STORAGE_TYPE:"
    select storage in $STORAGE_LIST; do
        echo $storage
        return
    done
}

# Variables / Переменные
CTID=$(pvesh get /cluster/nextid)
ROOTFS_STORAGE=$(select_storage rootdir)
TEMPLATE_STORAGE=$(select_storage vztmpl)

# Download Debian 12 template / Загрузка шаблона Debian 12
pveam update || msg_error_exit "Failed to update templates / Не удалось обновить список шаблонов"
pveam available -section system | grep debian-12 | tail -n 1 | awk '{print $1}' | \
while read TEMPLATE; do
    pveam download $TEMPLATE_STORAGE $TEMPLATE || msg_error_exit "Failed to download template / Не удалось загрузить шаблон"
done

# Create the LXC container / Создание LXC контейнера
pct create $CTID $TEMPLATE_STORAGE:vztmpl/$(pveam available -section system | grep debian-12 | tail -n 1 | awk '{print $1}') \
    -hostname minikube \
    -storage $ROOTFS_STORAGE \
    -cores 2 \
    -memory 4096 \
    -net0 name=eth0,bridge=vmbr0,ip=dhcp \
    -features nesting=1 \
    -rootfs $ROOTFS_STORAGE:8 \
    -password root \
    -onboot 1 \
    || msg_error_exit "Failed to create LXC / Не удалось создать LXC контейнер"

# Start the container / Запуск контейнера
pct start $CTID || msg_error_exit "Failed to start LXC / Не удалось запустить LXC контейнер"

# Install Docker, kubectl, and Minikube inside the container / Установка Docker, kubectl и Minikube внутри контейнера
pct exec $CTID -- bash -c "apt-get update && apt-get install -y curl apt-transport-https ca-certificates gnupg lsb-release"

# Install Docker / Установка Docker
pct exec $CTID -- bash -c "curl -fsSL https://get.docker.com | sh"

# Install kubectl / Установка kubectl
pct exec $CTID -- bash -c "curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x kubectl && mv kubectl /usr/local/bin/"

# Install Minikube / Установка Minikube
pct exec $CTID -- bash -c "curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 && install minikube-linux-amd64 /usr/local/bin/minikube"

# Start Minikube with Docker driver / Запуск Minikube с драйвером Docker
pct exec $CTID -- bash -c "minikube start --driver=docker"

echo -e "\n[INFO] LXC container with Minikube created successfully! / LXC контейнер с Minikube успешно создан!"
