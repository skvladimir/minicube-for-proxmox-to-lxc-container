#!/usr/bin/env bash
set -e
# Проверка зависимостей
command -v pct >/dev/null || { echo "pct not found"; exit 1; }

# Меню параметров
exec 3>&1
CTID=$(dialog --title "Создание Minikube LXC" --inputbox "ID контейнера (например: 200):" 8 40 "200" 2>&1 1>&3)
RAM=$(dialog --title "Минимум ОЗУ" --inputbox "Введите RAM в MiB (напр., 2048):" 8 40 "2048" 2>&1 1>&3)
DISK=$(dialog --title "Размер диска" --inputbox "Введите диск в GB (напр., 16):" 8 40 "16" 2>&1 1>&3)
exec 3>&-

# Создание LXC
pct create $CTID local:vztmpl/debian-12-standard_12.0-1_amd64.tar.gz --memory $RAM --rootfs local-lvm:${DISK}G --net0 name=eth0,bridge=vmbr0,ip=dhcp

pct start $CTID

# Установка Minikube внутри контейнера
pct exec $CTID -- bash -c "
  apt update
  apt install -y curl apt-transport-https conntrack socat
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  install minikube-linux-amd64 /usr/local/bin/minikube
  apt install -y docker.io
  usermod -aG docker $USER
  minikube start --driver=docker
"

echo "Minikube установлен и запущен в контейнере $CTID"
