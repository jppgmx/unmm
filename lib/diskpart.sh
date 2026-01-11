#!/bin/bash
#
# UNMM DiskPart Tool
#  - Version: 1.0.0
#  - Description: Ferramenta de particionamento de disco para UNMM.
#

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

declare -ga TRACKED_LOSETUP_DEVICES
if [[ -z "${TRACKED_LOSETUP_DEVICES+x}" ]]; then
    TRACKED_LOSETUP_DEVICES=()
fi

_validate_unit() {
    local size_regex='^[0-9]+[MG]$'
    if ! [[ $1 =~ $size_regex ]]; then
        log_error "Tamanho inválido: $1. Use o formato <número><M|G> (ex: 500M, 10G)."
        exit 1
    fi
}

_mb_to_mib() {
    local size_in_mb="${1%MB}"
    local size_in_mib=$((size_in_mb * 1024 * 1024 / 1048576))
    echo "${size_in_mib}MiB"
}

_mib_to_mb() {
    local size_in_mib="${1%MiB}"
    local size_in_mb=$((size_in_mib * 1048576 / 1024 / 1024))
    echo "${size_in_mb}MB"
}

_unit_to_mib() {
    local size="$1"
    local number=$(echo "$size" | sed -E 's/[a-zA-Z]+//g')
    local unit=$(echo "$size" | sed -E 's/[0-9]+//g' | tr '[:lower:]' '[:upper:]')

    case "$unit" in
        K*)
            local size_in_mib=$((number / 1024))
            echo "${size_in_mib}MiB"
            ;;
        M*)
            echo "${number}MiB"
            ;;
        G*)
            local size_in_mib=$((number * 1024))
            echo "${size_in_mib}MiB"
            ;;
        *)
            log_error "Unidade desconhecida: $unit. Use K, M ou G."
            exit 1
            ;;
    esac
}

# diskpart_create_raw_disk <output_path> <size>
diskpart_create_raw_disk() {
    local output_path="$1"
    local size="$2"

    _validate_unit "$size"

    log_info "Criando disco pré-alocado em '$output_path' com tamanho '$size'..."
    mkdir -p "$(dirname "$output_path")"
    exec_logged "QEMU_IMAGE" qemu-img create -f raw "$output_path" "$size"
    log_info "Disco criado com sucesso."
}

# diskpart_setup_loop_device <disk_image>
diskpart_setup_loop_device() {
    local disk_image="$1"

    log_info "Configurando dispositivo loop para a imagem de disco '$disk_image'..."
    local loop_device
    loop_device=$(losetup --show -fP "$disk_image")
    log_info "Dispositivo loop configurado: $loop_device"
    echo "$loop_device"
}

diskpart_track_loop_device() {
    local loop_device="$1"

    if [[ ! "$loop_device" == /dev/loop* ]]; then
        log_error "Isso não parece ser um dispositivo loop válido: $loop_device"
        exit 1
    fi

    if [[ " ${TRACKED_LOSETUP_DEVICES[*]} " == *" $loop_device "* ]]; then
        log_verbose "Dispositivo loop '$loop_device' já está sendo rastreado."
        return
    fi

    TRACKED_LOSETUP_DEVICES+=("$loop_device")
    log_verbose "Dispositivo loop rastreado: $loop_device"
}

diskpart_untrack_loop_device() {
    local loop_device="$1"

    if [[ ! "$loop_device" == /dev/loop* ]]; then
        log_error "Isso não parece ser um dispositivo loop válido: $loop_device"
        exit 1
    fi

    if [[ ! " ${TRACKED_LOSETUP_DEVICES[*]} " == *" $loop_device "* ]]; then
        log_verbose "Dispositivo loop '$loop_device' não está sendo rastreado."
        return
    fi

    TRACKED_LOSETUP_DEVICES=("${TRACKED_LOSETUP_DEVICES[@]/$loop_device}")
    log_verbose "Dispositivo loop não rastreado: $loop_device"
}

# diskpart_free_loop_device <loop_device>
diskpart_free_loop_device() {
    local loop_device="$1"
    log_info "Liberando dispositivo loop: $loop_device"
    exec_logged "DISKPART" losetup -d "$loop_device"
    TRACKED_LOSETUP_DEVICES=("${TRACKED_LOSETUP_DEVICES[@]/$loop_device}")
    log_info "Dispositivo loop '$loop_device' liberado com sucesso."
}

# diskpart_free_all_loop_devices
diskpart_free_all_loop_devices() {
    log_verbose "Liberando dispositivos loop rastreados..."
    log_verbose "Dispositivos rastreados: ${TRACKED_LOSETUP_DEVICES[*]}"
    for loop_dev in "${TRACKED_LOSETUP_DEVICES[@]}"; do
        log_verbose "Verificando dispositivo loop: $loop_dev"
        if losetup "$loop_dev" &> /dev/null; then
            log_verbose "Liberando dispositivo loop: $loop_dev"
            exec_logged "DISKPART" losetup -d "$loop_dev"
        else
            log_warning "Dispositivo loop '$loop_dev' já está liberado."
        fi
    done
    TRACKED_LOSETUP_DEVICES=()
    log_verbose "Todos os dispositivos loop rastreados foram liberados."
}

# diskpart_create_partition_table <device> <part_schema>
diskpart_create_partition_table() {
    local device="$1"
    local part_schema="$2"

    log_verbose "Desativando udev e sincronizando dados antes de particionar..."
    exec_logged "DISKPART" udevadm settle
    sync

    log_info "Deletando tudo em '$device' antes de criar a tabela de partições..."
    if ! exec_logged "DISKPART" wipefs -fa "$device"; then
        log_error "Falha ao limpar assinaturas de sistema de arquivos em '$device'."
        exit 1
    fi

    log_info "Criando tabela de partições '$part_schema' em '$device'..."
    case "$part_schema" in
        gpt)
            log_verbose "Usando comando parted para criar tabela de partições GPT."
            ;;
        msdos)
            log_verbose "Usando comando parted para criar tabela de partições MSDOS."
            ;;
        *)
            log_error "Esquema de partição desconhecido: $part_schema"
            exit 1
            ;;
    esac
    if ! exec_logged "DISKPART" parted -s "$device" mklabel "$part_schema"; then
        log_error "Falha ao criar tabela de partições '$part_schema' em '$device'."
        exit 1
    fi
    log_info "Tabela de partições criada com sucesso."
}

# diskpart_get_disk_info <device>
diskpart_get_disk_info() {
    local device="$1"
    log_verbose "Obtendo informações do disco para '$device'..."
    info=$(parted -sm "$device" print)

    while IFS= read -r line; do
        log_verbose "Info Disco: $line"
        echo "$line"
    done <<< "$info"
}

# diskpart_get_disk_partition_schema <device>
diskpart_get_disk_partition_schema() {
    local device="$1"
    log_verbose "Obtendo esquema de partição do disco para '$device'..."
    local part_schema=$(diskpart_get_disk_info "$device" | head -n2 | tail -n1 | cut -d: -f6)
    log_verbose "Esquema de partição é: $part_schema"
    echo "$part_schema"
}

diskpart_get_partitions() {
    local device="$1"
    log_verbose "Obtendo partições do disco para '$device'..."
    
    local info=$(diskpart_get_disk_info "$device")
    local partlist=$(echo "$info" | sed '1,2d')
    local partlist_count=$(echo "$partlist" | wc -l)

    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            partlist_count=$((partlist_count - 1))
            continue
        fi
        log_verbose "Partição: $line"
    done <<< "$partlist"
    log_verbose "Número de partições encontradas: $partlist_count"

    local fields=("Number" "Start" "End" "Size" "FileSystem" "Name" "Flags")
    local fields_count=${#fields[@]}

    log_verbose "Processando partições..."
    for ((i=1; i<=partlist_count; i++)); do
        local line=$(echo "$partlist" | head -n "$i" | tail -n1 | sed 's/;//g')
        local result=""
        for ((j=0; j<fields_count; j++)); do
            local value=$(echo "$line" | cut -d: -f$((j+1)))
            result+="${fields[$j]}=${value};"
        done

        log_verbose "Partição processada: $result"
        echo "$result"
    done
}

# diskpart_create_mbr_partition <device>
diskpart_create_mbr_partition() {
    local device="$1"
    log_info "Criando partição MBR em '$device'..."

    local schema_type=$(diskpart_get_disk_partition_schema "$device")
    if [[ "$schema_type" != "gpt" ]]; then
        log_error "Criar uma partição BIOS MBR requer uma tabela de partições GPT."
        exit 1
    fi

    local start_sector=1MiB
    local end_sector=2MiB
    exec_logged "DISKPART" parted -s "$device" mkpart primary "$start_sector" "$end_sector"
    
    local bios_grub_partition_number=$(diskpart_get_partitions "$device" | grep "primary" | tail -n1 | cut -d';' -f1 | cut -d'=' -f2)
    log_verbose "Número da partição BIOS MBR criada: $bios_grub_partition_number"
    exec_logged "DISKPART" parted -s "$device" set "$bios_grub_partition_number" bios_grub on
    log_info "Partição MBR criada com sucesso."
}

# dislpart_create_swap_partition <device> <size>
diskpart_create_efi_partition() {
    local device="$1"
    log_info "Criando partição EFI em '$device'..."

    local schema_type=$(diskpart_get_disk_partition_schema "$device")
    if [[ "$schema_type" != "gpt" ]]; then
        log_error "Criar uma partição EFI requer uma tabela de partições GPT."
        exit 1
    fi

    local last_partition=$(diskpart_get_partitions "$device" | tail -n1)
    local start_sector=$(echo "$last_partition" | cut -d';' -f3 | cut -d'=' -f2)
    if [[ -z "$start_sector" ]]; then
        start_sector="1MiB"
    fi

    log_verbose "Início da nova partição EFI em: $start_sector"
    local start_value=$(_unit_to_mib "$start_sector")
    local esp_size="200MiB"

    local sum=$(( $(echo "${start_value%MiB}") + $(echo "${esp_size%MiB}") ))
    local end_sector="${sum}MiB"

    log_verbose "Fim da nova partição EFI após cálculo: $end_sector"
    
    exec_logged "DISKPART" parted -s "$device" mkpart primary fat32 "$start_sector" "$end_sector"
    local last_partition_number=$(diskpart_get_partitions "$device" | tail -n1 | cut -d';' -f1 | cut -d'=' -f2)
    log_verbose "Número da partição EFI criada: $last_partition_number"

    log_verbose "Formatando partição EFI como FAT32..."
    local esp_partition="${device}p${last_partition_number}"
    exec_logged "DISKPART" mkfs.fat -F32 "$esp_partition"

    exec_logged "DISKPART" parted -s "$device" set "$last_partition_number" esp on

    log_info "Partição EFI criada com sucesso."
}

# diskpart_create_system_partition <device>
diskpart_create_system_partition() {
    local device="$1"
    log_info "Criando partição do sistema em '$device'..."

    local schema_type=$(diskpart_get_disk_partition_schema "$device")
        
    # Obter informações sobre a última partição existente
    local last_partition=$(diskpart_get_partitions "$device" | tail -n1)
    local end_of_last_partition=$(echo "$last_partition" | cut -d';' -f3 | cut -d'=' -f2)

    if [[ -z "$end_of_last_partition" ]]; then
        end_of_last_partition="1MiB"
    fi

    # Criar partição ext4 do fim da última partição até o fim do disco
    log_verbose "Última partição termina em: $end_of_last_partition"
    exec_logged "DISKPART" parted -s "$device" mkpart primary ext4 "$end_of_last_partition" 100%
    local last_partition_number=$(diskpart_get_partitions "$device" | tail -n1 | cut -d';' -f1 | cut -d'=' -f2)

    log_verbose "Número da partição do sistema criada: $last_partition_number"
    log_verbose "Formatando partição do sistema como ext4..."
    local system_partition="${device}p${last_partition_number}"
    exec_logged "DISKPART" mkfs.ext4 -F "$system_partition"

    log_info "Partição do sistema criada com sucesso."
}

# diskpart_create_image_mbr_layout <device>
diskpart_create_image_mbr_layout() {
    local device="$1"
    log_info "Criando layout MBR na imagem de disco '$device'..."

    diskpart_create_partition_table "$device" "msdos"
    diskpart_create_system_partition "$device"

    log_info "Layout MBR criado com sucesso na imagem de disco."
}

# diskpart_create_image_gpt_layout <device> <ishybrid>
diskpart_create_image_gpt_layout() {
    local device="$1"
    local ishybrid="$2"
    log_info "Criando layout GPT na imagem de disco '$device'..."

    diskpart_create_partition_table "$device" "gpt"
    
    if [[ "$ishybrid" == true ]]; then
        log_info "Criando partição MBR para suporte híbrido..."
        diskpart_create_mbr_partition "$device"
    fi

    diskpart_create_efi_partition "$device"
    diskpart_create_system_partition "$device"

    log_info "Layout GPT criado com sucesso na imagem de disco."
}

diskpart_img_to_vmdk() {
    local input_img="$1"
    local output_vmdk="$2"

    log_info "Convertendo imagem RAW '$input_img' para VMDK em '$output_vmdk'..."
    exec_logged "DISKPART" qemu-img convert -f raw -O vmdk -o subformat=streamOptimized "$input_img" "$output_vmdk"
    log_info "Conversão para VMDK concluída com sucesso."
}