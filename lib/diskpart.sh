#!/bin/bash
#
# UNMM DiskPart Tool
#  - Version: 1.0.0
#  - Description: Ferramenta de particionamento de disco para UNMM.
#
# Sob licença MIT
#

declare -ga TRACKED_LOSETUP_DEVICES
if [[ -z "${TRACKED_LOSETUP_DEVICES+x}" ]]; then
    TRACKED_LOSETUP_DEVICES=()
fi

# Valida o formato da unidade de tamanho comuns na maioria das ferramentas de disco (Ex: 500M, 10G)
_validate_unit() {
    local size_regex='^[0-9]+[MG]$'
    if ! [[ $1 =~ $size_regex ]]; then
        log_error "Tamanho inválido: $1. Use o formato <número><M|G> (ex: 500M, 10G)."
        exit 1
    fi
}

# Converte MB para MiB
_mb_to_mib() {
    local size_in_mb="${1%MB}"
    local size_in_mib=$((size_in_mb * 1024 * 1024 / 1048576))
    echo "${size_in_mib}MiB"
}

# Converte MiB para MB
_mib_to_mb() {
    local size_in_mib="${1%MiB}"
    local size_in_mb=$((size_in_mib * 1048576 / 1024 / 1024))
    echo "${size_in_mb}MB"
}

# Converte unidades K, M, G para MiB
_unit_to_mib() {
    local size="$1"
    local number unit
    number=$(echo "$size" | sed -E 's/[a-zA-Z]+//g')
    unit=$(echo "$size" | sed -E 's/[0-9]+//g' | tr '[:lower:]' '[:upper:]')

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
# Cria uma imagem de disco RAW pré-alocada
#
# Argumentos:
#   output_path - Caminho onde a imagem de disco será criada
#   size        - Tamanho da imagem de disco (ex: 500M, 10G)
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
# Configura um dispositivo loop para a imagem de disco fornecida
#
# Argumentos:
#   disk_image - Caminho para a imagem de disco
#
# Retorna:
#   O caminho do dispositivo loop configurado
diskpart_setup_loop_device() {
    local disk_image="$1"

    log_info "Configurando dispositivo loop para a imagem de disco '$disk_image'..."
    local loop_device
    loop_device=$(losetup --show -fP "$disk_image")
    log_info "Dispositivo loop configurado: $loop_device"
    echo "$loop_device"
}

# diskpart_track_loop_device <loop_device>
# Rastreia um dispositivo loop para liberação posterior
#
# Argumentos:
#   loop_device - Caminho do dispositivo loop a ser rastreado
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

# diskpart_untrack_loop_device <loop_device>
# Para de rastrear um dispositivo loop
#
# Argumentos:
#   loop_device - Caminho do dispositivo loop a ser desrastreado
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
# Libera um dispositivo loop específico
#
# Argumentos:
#   loop_device - Caminho do dispositivo loop a ser liberado
diskpart_free_loop_device() {
    local loop_device="$1"
    log_info "Liberando dispositivo loop: $loop_device"
    exec_logged "DISKPART" losetup -d "$loop_device"
    TRACKED_LOSETUP_DEVICES=("${TRACKED_LOSETUP_DEVICES[@]/$loop_device}")
    log_info "Dispositivo loop '$loop_device' liberado com sucesso."
}

# diskpart_free_all_loop_devices
# Libera todos os dispositivos loop rastreados
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
# Cria uma tabela de partições no dispositivo fornecido
#
# Argumentos:
#   device      - Dispositivo onde a tabela de partições será criada
#   part_schema - Esquema de partição a ser criado (gpt ou msdos)
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
# Obtém informações detalhadas do disco usando parted
#
# Argumentos:
#   device - Dispositivo do qual obter informações
#
# Retorna:
#   Informações detalhadas do disco no formato de máquina que o parted fornece.
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
# Obtém o esquema de partição do disco
#
# Argumentos:
#   device - Dispositivo do qual obter o esquema de partição
#
# Retorna:
#   O esquema de partição (gpt ou msdos)
diskpart_get_disk_partition_schema() {
    local device="$1"
    log_verbose "Obtendo esquema de partição do disco para '$device'..."
    local part_schema
    part_schema=$(diskpart_get_disk_info "$device" | head -n2 | tail -n1 | cut -d: -f6)
    log_verbose "Esquema de partição é: $part_schema"
    echo "$part_schema"
}

# diskpart_get_partitions <device>
# Obtém a lista de partições do disco
#
# Argumentos:
#   device - Dispositivo do qual obter a lista de partições
#
# Retorna:
#   A lista de partições no formato chave=valor separado por ponto e vírgula
diskpart_get_partitions() {
    local device="$1"
    log_verbose "Obtendo partições do disco para '$device'..."
    
    local info partlist partlist_count
    info=$(diskpart_get_disk_info "$device")
    partlist=$(echo "$info" | sed '1,2d')
    partlist_count=$(echo "$partlist" | wc -l)

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
        local line
        line=$(echo "$partlist" | head -n "$i" | tail -n1 | sed 's/;//g')
        local result=""
        for ((j=0; j<fields_count; j++)); do
            local value
            value=$(echo "$line" | cut -d: -f$((j+1)))
            result+="${fields[$j]}=${value};"
        done

        log_verbose "Partição processada: $result"
        echo "$result"
    done
}

# diskpart_get_last_partition <device>
# Obtém a última partição do disco
#
# Argumentos:
#   device - Dispositivo do qual obter a última partição
#
# Retorna:
#   A última partição no formato chave=valor separado por ponto e vírgula
diskpart_get_last_partition() {
    local device="$1"

    diskpart_get_partitions "$device" | tail -n1
}

# diskpart_format_partition <partition_device> <filesystem_type>
# Formata a partição fornecida com o sistema de arquivos especificado
#
# Argumentos:
#   partition_device - Dispositivo da partição a ser formatada
#   filesystem_type  - Tipo de sistema de arquivos (ext4 ou fat32)
diskpart_format_partition() {
    local partition_device="$1"
    local filesystem_type="$2"

    log_info "Formatando partição '$partition_device' como '$filesystem_type'..."

    case "$filesystem_type" in
        ext4)
            exec_logged "DISKPART" mkfs.ext4 -F "$partition_device"
            ;;
        fat32)
            exec_logged "DISKPART" mkfs.fat -F32 "$partition_device"
            ;;
        *)
            log_error "Tipo de sistema de arquivos desconhecido: $filesystem_type"
            exit 1
            ;;
    esac

    log_info "Partição '$partition_device' formatada com sucesso como '$filesystem_type'."
}

# diskpart_create_partition <device> <part_type> <fs_type> <start_sector> <end_sector> <format>
# Cria uma partição no dispositivo fornecido
#
# Argumentos:
#   device        - Dispositivo onde a partição será criada
#   part_type     - Tipo de partição (ex: primary)
#   fs_type       - Tipo de sistema de arquivos (ex: ext4, fat32)
#   start_sector  - Setor inicial da partição (ex: 1MiB)
#   end_sector    - Setor final da partição (ex: 100%)
#   format        - Se true, formata a partição após a criação
#
# Retorna:
#   O dispositivo da partição criada
diskpart_create_partition() {
    local device="$1"
    local part_type="$2"
    local fs_type="$3"
    local start_sector="$4"
    local end_sector="$5"
    local format="$6"

    log_info "Criando partição '$part_type' em '$device' de '$start_sector' a '$end_sector'..."

    local parted_command
    if [[ -n "$fs_type" ]]; then
        log_verbose "Tipo de sistema de arquivos especificado: $fs_type"
        parted_command="mkpart primary $fs_type $start_sector $end_sector"
    else
        log_verbose "Nenhum tipo de sistema de arquivos especificado; a partição não será formatada."
        parted_command="mkpart primary $start_sector $end_sector"
    fi

    #shellcheck disable=SC2086
    exec_logged "DISKPART" parted -s "$device" $parted_command

    local last_partition_number
    last_partition_number=$(diskpart_get_last_partition "$device" | cut -d';' -f1 | cut -d'=' -f2)
    log_verbose "Número da partição criada: $last_partition_number"

    local partition_device="${device}p${last_partition_number}"
    if [[ "$format" == true && -n "$fs_type" ]]; then
        diskpart_format_partition "$partition_device" "$fs_type"
        log_info "Partição '$part_type' criada e formatada com sucesso."
    else
        log_info "Partição '$part_type' criada com sucesso."
    fi
    echo "$partition_device"
}

# diskpart_set_flag <part_device> <flag_name> <flag_value>
# Define uma flag específica em uma partição
#
# Argumentos:
#   part_device - Partição onde a flag será definida
#   flag_name   - Nome da flag a ser definida (ex: boot, esp, bios_grub)
#   flag_value  - Valor da flag (on ou off)
diskpart_set_flag() {
    local part_device="$1"
    local flag_name="$2"
    local flag_value="$3"

    local device partition_number
    partition_number=$(echo "$part_device" | grep -oE '[0-9]+$')
    device="${part_device%"p$partition_number"}"

    log_verbose "Definindo flag '$flag_name' como '$flag_value' na partição '$part_device' (disco '$device', partição '$partition_number')..."
    exec_logged "DISKPART" parted -s "$device" set "$partition_number" "$flag_name" "$flag_value"
    log_verbose "Flag '$flag_name' definida como '$flag_value' na partição '$part_device'."
}

# diskpart_create_image_mbr_layout <device>
# Atalho para criar layout MBR completo em uma imagem de disco
# Argumentos:
#   device - Dispositivo onde o layout será criado
diskpart_create_image_mbr_layout() {
    local device="$1"
    log_info "Criando layout MBR na imagem de disco '$device'..."

    diskpart_create_partition_table "$device" "msdos"
    diskpart_create_partition "$device" "primary" "ext4" "1MiB" "100%" true

    log_info "Layout MBR criado com sucesso na imagem de disco."
}

# diskpart_create_image_gpt_layout <device> <ishybrid>
# Atalho para criar layout GPT completo em uma imagem de disco
# Argumentos:
#   device   - Dispositivo onde o layout será criado
#   ishybrid - Se true, cria uma partição MBR adicional para suporte híbrido
diskpart_create_image_gpt_layout() {
    local device="$1"
    local ishybrid="$2"
    log_info "Criando layout GPT na imagem de disco '$device'..."

    diskpart_create_partition_table "$device" "gpt"
    
    local start_efi_partition="1MiB"
    local end_efi_partition="200MiB"

    local mbr_partition efi_partition system_partition
    
    if [[ "$ishybrid" == true ]]; then
        log_info "Criando partição MBR para suporte híbrido..."
        mbr_partition=$(diskpart_create_partition "$device" "primary" "" "1MiB" "2MiB" false)
        log_verbose "A partição MBR é $mbr_partition"
        diskpart_set_flag "$mbr_partition" "bios_grub" on

        start_efi_partition="2MiB"
        end_efi_partition="201MiB"
    fi

    log_info "Criando partição EFI..."
    efi_partition=$(diskpart_create_partition "$device" "primary" "fat32" "$start_efi_partition" "$end_efi_partition" true)
    log_verbose "A partição EFI é $efi_partition"
    diskpart_set_flag "$efi_partition" "boot" on
    diskpart_set_flag "$efi_partition" "esp" on

    log_info "Criando partição do sistema..."
    system_partition=$(diskpart_create_partition "$device" "primary" "ext4" "$end_efi_partition" "100%" true)
    log_verbose "A partição do sistema é $system_partition"

    log_info "Layout GPT criado com sucesso na imagem de disco."
}

# diskpart_img_to_vmdk <input_img> <output_vmdk>
# Converte uma imagem RAW para o formato VMDK
# Argumentos:
#   input_img   - Caminho para a imagem RAW de entrada
#   output_vmdk - Caminho para a imagem VMDK de saída
diskpart_img_to_vmdk() {
    local input_img="$1"
    local output_vmdk="$2"

    log_info "Convertendo imagem RAW '$input_img' para VMDK em '$output_vmdk'..."
    exec_logged "DISKPART" qemu-img convert -f raw -O vmdk -o subformat=streamOptimized "$input_img" "$output_vmdk"
    log_info "Conversão para VMDK concluída com sucesso."
}
