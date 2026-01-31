#!/bin/bash
source "$(dirname "$0")/lib/log.sh" || source "$(dirname "$0")/../lib/log.sh"
: ${SCRIPT_NAME:=$(basename "$0")}

log_info "========================================="
log_info "Дерево установленных пакетов"
log_info "========================================="
log_info ""

# Функция для получения прямых зависимостей пакета
get_dependencies() {
    local package=$1
    pacman -Qi "$package" 2>/dev/null | grep "^Depends On" | sed 's/^Depends On\s*:\s*//' | tr ' ' '\n' | grep -v "^None$" | sed 's/[>=<].*$//' | grep -v "^$"
}

declare -A PRINTED_PACKAGES=()

# Рекурсивный вывод зависимостей
print_dependency_tree() {
    local package=$1
    local prefix=$2
    local lineage=$3

    local deps_raw
    deps_raw=$(get_dependencies "$package")

    if [ -z "$deps_raw" ]; then
        return
    fi

    mapfile -t deps <<< "$deps_raw"

    local count=${#deps[@]}
    local index=0

    for dep in "${deps[@]}"; do
        ((index++))

        local connector="├"
        local child_prefix="${prefix}│  "
        if [ $index -eq $count ]; then
            connector="└"
            child_prefix="${prefix}   "
        fi

        if [[ "$lineage" == *"|$dep|"* ]]; then
            echo "${prefix}${connector}─ $dep [циклическая зависимость обнаружена]"
            continue
        fi

        local dep_version
        dep_version=$(pacman -Q "$dep" 2>/dev/null | awk '{print $2}')
        if [ -z "$dep_version" ]; then
            dep_version="не установлен"
        fi

        if [[ -n "${PRINTED_PACKAGES[$dep]}" ]]; then
            echo "${prefix}${connector}─ $dep ($dep_version) [уже показан]"
            continue
        fi

        PRINTED_PACKAGES[$dep]=1
        echo "${prefix}${connector}─ $dep ($dep_version)"
        print_dependency_tree "$dep" "$child_prefix" "$lineage|$dep|"
    done
}

# Получаем список явно установленных пакетов
PACKAGES=$(pacman -Qe | awk '{print $1}')

echo "Показываем явно установленные пакеты и их прямые зависимости:"
echo ""

for package in $PACKAGES; do
    version=$(pacman -Q "$package" 2>/dev/null | awk '{print $2}')
    echo "┌─ $package ($version)"
    PRINTED_PACKAGES[$package]=1
    
    # Показываем зависимости первого уровня
    deps=$(get_dependencies "$package")
    
    if [ -n "$deps" ]; then
        print_dependency_tree "$package" "│  " "|$package|"
    else
        echo "│  └─ (нет зависимостей)"
    fi
    echo ""
done

echo "========================================="
echo "Всего явно установленных пакетов: $(pacman -Qe | wc -l)"
echo "Всего пакетов в системе: $(pacman -Q | wc -l)"
echo "========================================"

