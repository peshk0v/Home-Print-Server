#!/bin/bash

# =====================================================
# Универсальный скрипт установки принт-сервера на Raspberry Pi
# Настройка: CUPS + Samba + Avahi
# Версия: 1.0
# =====================================================

set -e  # Прерывать выполнение при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для вывода заголовков
print_step() {
    echo -e "${GREEN}==>${NC} ${YELLOW}$1${NC}"
}

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Ошибка: Этот скрипт должен запускаться с правами root (sudo).${NC}"
   exit 1
fi

# Получаем реальное имя пользователя (не root)
if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
else
    REAL_USER=$(who am i | awk '{print $1}')
    if [ -z "$REAL_USER" ]; then
        REAL_USER="pi"
    fi
fi

print_step "Обновление списка пакетов и системы..."
apt update && apt upgrade -y

print_step "Установка CUPS (сервер печати), Samba (шаринг для Windows) и Avahi (Bonjour/AirPrint)..."
apt install -y cups samba avahi-daemon

print_step "Добавление пользователя $REAL_USER в группу lpadmin для управления принтерами..."
usermod -a -G lpadmin "$REAL_USER"

print_step "Настройка CUPS для удалённого доступа..."
# Разрешить удалённое управление через веб-интерфейс
cupsctl --remote-admin --remote-any --share-printers
systemctl restart cups

print_step "Настройка Samba для общего доступа к принтерам..."
# Создаём резервную копию конфига
cp /etc/samba/smb.conf /etc/samba/smb.conf.bak

# Добавляем настройки для принтера в конец файла (если их ещё нет)
if ! grep -q "\[printers\]" /etc/samba/smb.conf; then
    cat >> /etc/samba/smb.conf << 'EOF'

# ========== НАСТРОЙКИ ПРИНТ-СЕРВЕРА ==========
[printers]
    comment = All Printers
    path = /var/spool/samba
    browseable = yes
    public = yes
    guest ok = yes
    writable = no
    printable = yes
    printer admin = root, pi

[print$]
    comment = Printer Drivers
    path = /var/lib/samba/printers
    browseable = yes
    read only = yes
    guest ok = yes
EOF
fi

# Перезапуск Samba
systemctl restart smbd
systemctl restart nmbd

print_step "Настройка Avahi для автоматического обнаружения (Bonjour)..."
# Avahi обычно уже настроен, но убедимся, что сервис запущен и включен
systemctl enable avahi-daemon
systemctl restart avahi-daemon

print_step "Установка дополнительных драйверов (опционально)..."
# Набор Gutenprint — поддерживает большинство принтеров
apt install -y printer-driver-gutenprint
# Драйверы для HP (HPLIP)
apt install -y hplip
# Драйверы для Brother (если нужно — раскомментировать, но брать из репозитория)
# apt install -y printer-driver-brlaser

print_step "Настройка прав на папку спула"
mkdir -p /var/spool/cups-pdf
chown -R lp:lp /var/spool/cups-pdf

print_step "Перезапуск всех служб для применения изменений..."
systemctl restart cups
systemctl restart smbd
systemctl restart avahi-daemon

# Получаем IP-адрес Raspberry Pi
IP_ADDR=$(hostname -I | awk '{print $1}')

print_step "Установка завершена успешно!"
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Принт-сервер готов к использованию!${NC}"
echo -e "${GREEN}============================================${NC}"
echo -e "1. Веб-интерфейс CUPS доступен по адресу: ${YELLOW}http://$IP_ADDR:631${NC}"
echo -e "2. Для добавления принтера:"
echo -e "   - Зайдите в веб-интерфейс"
echo -e "   - Нажмите Administration → Add Printer"
echo -e "   - Введите логин: ${YELLOW}$REAL_USER${NC} и ваш пароль"
echo -e "   - Выберите ваш USB-принтер из списка"
echo -e "   - Включите опцию ${YELLOW}Share This Printer${NC}"
echo -e "3. После добавления принтер автоматически появится в сети:"
echo -e "   - Windows: в разделе 'Сетевые устройства'"
echo -e "   - macOS: в списке принтеров (Bonjour)"
echo -e "   - Linux: в настройках печати (через CUPS или Avahi)"
echo -e "4. Если принтер не определяется — перезагрузите Pi командой ${YELLOW}sudo reboot${NC}"
echo -e "${GREEN}============================================${NC}"

# Предложение перезагрузиться
read -p "Перезагрузить Raspberry Pi сейчас? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    reboot
fi
