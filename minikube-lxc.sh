#!/bin/bash
# Скрипт для создания и настройки LXC-контейнера с Minikube на Proxmox VE с меню

# Прерывание при любой ошибке
set -e

# Проверка установки dialog
if ! command -v dialog &> /dev/null; then
    echo "Установка пакета dialog..."
    apt-get update
    apt-get install -y dialog
fi

# Настройки по умолчанию
CT_ID=100
CT_HOSTNAME="minikube-ct"
CT_PASSWORD="changeme"
CT_STORAGE="local-lvm"
CT_DISK_SIZE=20
CT_MEMORY=4096
CT_CORES=2
CT_OS="debian-12-standard"
CT_TEMPLATE="local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
CT_IP="dhcp"
CT_GATEWAY=""
PVE_HOST="localhost"
PVE_USER="root@pam"
SSH_KEY=""
VERBOSE=0

# Функция отображения меню
show_menu() {
    local choice=$(dialog --clear --title "SETTINGS" \
        --menu "Выберите опцию:" 15 50 6 \
        1 "Настройки по умолчанию" \
        2 "Настройки по умолчанию (с подробным выводом)" \
        3 "Расширенные настройки" \
        4 "Использовать конфигурационный файл" \
        5 "Диагностические настройки" \
        6 "Выход" \
        2>&1 >/dev/tty)

    clear
    echo "$choice"
    return $choice
}

# Функция создания контейнера
create_container() {
    # Проверка существования контейнера
    if pct status $CT_ID 2>/dev/null; then
        echo "Ошибка: Контейнер с ID $CT_ID уже существует"
        exit 1
    fi

    # Создание LXC-контейнера
    echo "Создание LXC-контейнера $CT_ID..."
    pct create $CT_ID $CT_TEMPLATE \
        -arch amd64 \
        -hostname $CT_HOSTNAME \
        -password $CT_PASSWORD \
        -storage $CT_STORAGE \
        -rootfs $CT_DISK_SIZE \
        -memory $CT_MEMORY \
        -cores $CT_CORES \
        -net0 name=eth0,bridge=vmbr0,ip=$CT_IP${CT_GATEWAY:+,gw=$CT_GATEWAY} \
        -features nesting=1 \
        -unprivileged 0

    # Настройка контейнера для вложенной виртуализации
    echo "Настройка контейнера для вложенной виртуализации..."
    pct set $CT_ID -features nesting=1,keyctl=1
    echo "lxc.apparmor.profile: unconfined" >> /etc/pve/lxc/$CT_ID.conf
    echo "lxc.cgroup2.devices.allow: a" >> /etc/pve/lxc/$CT_ID.conf
    echo "lxc.cap.drop:" >> /etc/pve/lxc/$CT_ID.conf

    # Запуск контейнера
    echo "Запуск контейнера $CT_ID..."
    pct start $CT_ID

    # Ожидание запуска контейнера
    sleep 5

    # Установка зависимостей и Minikube
    echo "Установка зависимостей и Minikube в контейнере..."
    pct exec $CT_ID -- bash -c "
        set -e
        # Обновление списков пакетов
        apt-get update
        # Установка зависимостей
        apt-get install -y curl apt-transport-https ca-certificates gnupg lsb-release conntrack
        # Установка Docker
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io
        systemctl start docker
        systemctl enable docker
        # Установка Minikube (стабильная версия для x86-64, Debian-пакет)
        curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube_latest_amd64.deb
        dpkg -i minikube_latest_amd64.deb || apt-get install -f -y
        rm minikube_latest_amd64.deb
        # Установка kubectl
        curl -LO \"https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\"
        chmod +x kubectl
        mv kubectl /usr/local/bin/
        # Настройка пользователя для Minikube
        useradd -m -s /bin/bash minikube-user || true
        usermod -aG docker minikube-user
        # Запуск Minikube
        su - minikube-user -c 'minikube start --driver=docker'
        # Проверка статуса кластера
        su - minikube-user -c 'minikube status'
        # Включение панели управления Minikube
        su - minikube-user -c 'minikube dashboard --url &'
    "

    # Добавление SSH-ключа, если он указан
    if [ -n "$SSH_KEY" ]; then
        echo "Добавление публичного SSH-ключа в контейнер..."
        pct exec $CT_ID -- bash -c "mkdir -p /root/.ssh && echo \"$SSH_KEY\" >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys"
    fi

    # Вывод сообщения о завершении
    echo "Контейнер Minikube $CT_ID успешно создан и настроен!"
    echo "Имя хоста: $CT_HOSTNAME"
    echo "IP: $CT_IP"
    echo "Для доступа к контейнеру: pct exec $CT_ID -- bash"
    echo "Для работы с Minikube переключитесь на пользователя minikube-user: su - minikube-user"
    echo "Проверка статуса кластера: kubectl get po -A"
    echo "Доступ к панели управления: Выполните 'minikube dashboard' от имени minikube-user"
}

# Главный цикл
while true; do
    choice=$(show_menu)
    case $choice in
        1) # Настройки по умолчанию
            create_container
            ;;
        2) # Настройки по умолчанию (с подробным выводом)
            VERBOSE=1
            create_container
            VERBOSE=0
            ;;
        3) # Расширенные настройки
            echo "Расширенные настройки пока не реализованы. Используйте аргументы командной строки для настройки."
            ;;
        4) # Использовать конфигурационный файл
            echo "Функция использования конфигурационного файла пока не реализована. Укажите путь к файлу вручную."
            ;;
        5) # Диагностические настройки
            echo "Диагностика: Проверка вложенной виртуализации..."
            if grep -q "vmx\|svm" /proc/cpuinfo; then
                echo "Вложенная виртуализация поддерживается."
            else
                echo "ВНИМАНИЕ: Вложенная виртуализация не обнаружена. Настройте хост Proxmox."
            fi
            ;;
        6) # Выход
            echo "Выход из программы."
            exit 0
            ;;
        *) # Неверный выбор
            echo "Неверный выбор. Попробуйте снова."
            ;;
    esac
done
