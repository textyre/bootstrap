#!/bin/bash
source "$(dirname "$0")/lib/log.sh" || source "$(dirname "$0")/../lib/log.sh"
: ${SCRIPT_NAME:=$(basename "$0")}

log_info "========================================="
log_info "Полное дерево зависимостей пакетов"
log_info "========================================="
log_info ""

# Ассоциативный массив для отслеживания уже обработанных пакетов
declare -A visited

# Функция для получения прямых зависимостей пакета
get_dependencies() {
    local package=$1
    pacman -Qi "$package" 2>/dev/null | grep "^Depends On" | sed 's/^Depends On\s*:\s*//' | tr ' ' '\n' | grep -v "^None$" | sed 's/[>=<].*$//' | grep -v "^$"
}

# Рекурсивная функция для вывода дерева зависимостей
show_tree() {
    local package=$1
    local prefix=$2
    local is_last=$3
    
    # Проверяем, установлен ли пакет
    if ! pacman -Q "$package" &>/dev/null; then
        return
    fi
    
    local version=$(pacman -Q "$package" 2>/dev/null | awk '{print $2}')
    
    # Определяем символы для дерева
    if [ "$prefix" = "" ]; then
        echo "$package ($version)"
    else
        if [ "$is_last" = "1" ]; then
            echo "${prefix}└─ $package ($version)"
            new_prefix="${prefix}   "
        else
            echo "${prefix}├─ $package ($version)"
            new_prefix="${prefix}│  "
        fi
    fi
    
    # Проверяем, не обрабатывали ли мы уже этот пакет (предотвращение циклов)
    if [ "${visited[$package]}" = "1" ]; then
        return
    fi
    visited[$package]=1
    
    # Получаем зависимости
    local deps=$(get_dependencies "$package")
    
    if [ -n "$deps" ]; then
        local deps_array=()
        while IFS= read -r dep; do
            deps_array+=("$dep")
        done <<< "$deps"
        
        local deps_count=${#deps_array[@]}
        local counter=0
        
        for dep in "${deps_array[@]}"; do
            counter=$((counter + 1))
            if [ $counter -eq $deps_count ]; then
                show_tree "$dep" "$new_prefix" "1"
            else
                show_tree "$dep" "$new_prefix" "0"
            fi
        done
    fi
}

# Получаем список явно установленных пакетов
PACKAGES=$(pacman -Qe | awk '{print $1}')

log_info "Показываем явно установленные пакеты со ВСЕМИ зависимостями (рекурсивно):"
log_info ""

for package in $PACKAGES; do
    log_info "════════════════════════════════════════"
    log_info "Пакет: $package"
    log_info "════════════════════════════════════════"
    
    # Очищаем массив посещенных пакетов для каждого нового дерева
    visited=()
    
    # Показываем полное дерево зависимостей
    show_tree "$package" "" "0"
    log_info ""
done

log_info "========================================="
log_info "Статистика:"
log_info "========================================="
log_info "Явно установленных пакетов: $(pacman -Qe | wc -l)"
log_info "Всего пакетов (включая зависимости): $(pacman -Q | wc -l)"
log_info "Зависимостей: $(($(pacman -Q | wc -l) - $(pacman -Qe | wc -l)))"
log_info "========================================="
