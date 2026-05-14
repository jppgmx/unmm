#!/bin/bash
#
# UNMM DiskPart Tool
#  - Version: 1.0.0
#  - Description: Ferramenta de particionamento de disco para UNMM.
#
# Sob licença MIT
#

if [[ -n "${UNMM_LIB_DISKPART_LOADED:-}" ]]; then
    return 0
fi
UNMM_LIB_DISKPART_LOADED=true
_diskpart_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#shellcheck source=logging.sh
source "${_diskpart_lib_dir}/logging.sh"
# shellcheck source=uc.sh
source "${_diskpart_lib_dir}/uc.sh"
# shellcheck source=lib/config/lib.diskpart
with_config lib.diskpart
unset _diskpart_lib_dir

# Servirá para listar os dispositivos criados e rastreados para liberação posterior, evitando vazamentos de recursos.
declare -ga TRACKED_DISKPART_DEVICES
if [[ -z "${TRACKED_DISKPART_DEVICES+x}" ]]; then
    TRACKED_DISKPART_DEVICES=()
fi

# Não há definição de typedefs em Shell Script, mas considere os seguintes termos:
#   - DiskImage: Refere-se a uma string no formato "ARQUIVO:BACKEND", onde:
#       - ARQUIVO é o caminho para a imagem de disco (ex: /path/to/disk.qcow2)
#       - BACKEND é o tipo de backend usado para criar a imagem (ex: qcow ou raw).
#   - DiskDevice: Refere-se a uma string no formato "DISPOSITIVO:ARQUIVO:BACKEND", onde:
#       - DISPOSITIVO é o caminho para o dispositivo de disco (ex: /dev/nbd0)
#       - ARQUIVO é o caminho para a imagem de disco (ex: /path/to/disk.qcow2)
#       - BACKEND é o tipo de backend usado para criar a imagem (ex: qcow ou raw).
#
# Para os próximos comentários dessa lib, usaremos esses termos.
#

_diskpart_is_tracked_device() {
    local device="$1"
    if [[ " ${TRACKED_DISKPART_DEVICES[*]} " == *" $device "* ]]; then
        return 0
    fi
    return 1
}

_diskpart_parse_disk_image() {
    local disk_image="$1"
    local image_path backend

    if [[ "$disk_image" == *:* ]]; then
        IFS=':' read -r image_path backend <<< "$disk_image"
    else
        image_path="$disk_image"
        backend=""
    fi

    if [[ -z "$image_path" ]]; then
        log_error "DiskImage invalido: '$disk_image'"
        exit 1
    fi

    echo "$image_path:$backend"
}

_diskpart_parse_disk_device() {
    local disk_device="$1"
    local device image backend

    if [[ "$disk_device" == *:*:* ]]; then
        IFS=':' read -r device image backend <<< "$disk_device"
    else
        device="$disk_device"
        image=""
        backend=""
    fi

    if [[ -z "$device" ]]; then
        log_error "DiskDevice invalido: '$disk_device'"
        exit 1
    fi

    echo "$device:$image:$backend"
}

_diskpart_guess_format_from_path() {
    local path="$1"

    case "$path" in
        *.qcow2)
            echo "qcow2"
            ;;
        *.img)
            echo "raw"
            ;;
        *.vmdk)
            echo "vmdk"
            ;;
        *)
            echo ""
            ;;
    esac
}

_diskpart_infer_backend_from_device() {
    local device="$1"

    if [[ "$device" =~ /dev/nbd[0-9]+ ]]; then
        echo "qcow"
        return
    fi
    if [[ "$device" =~ /dev/loop[0-9]+ ]]; then
        echo "raw"
        return
    fi

    echo ""
}

_diskpart_run_udev_settle() {
    if use_udev_settle; then
        exec_logged "DISKPART" udevadm settle
    fi
}

_diskpart_run_partprobe() {
    local device="$1"
    if use_partprobe; then
        exec_logged "DISKPART" partprobe "$device"
    fi
}

# _validate_size <size>
# Valida um tamanho usando unicalc, aceitando unidades SI/IEC e bits/bytes.
#
# Argumentos:
#   size - O tamanho a ser validado (ex: "500M", "10G", "1GiB")
#
# Retorna:
#   Nada ou erro se o tamanho for inválido.
_validate_size() {
    local size="$1"
    if ! uc_convert "$size" B >/dev/null 2>&1; then
        log_error "Tamanho inválido: $size. Use uma unidade válida (ex: 500M, 10G, 1GiB)."
        exit 1
    fi
}

backend_extension() {
    case "$(backend)" in
        qcow)
            echo "qcow2"
            ;;
        raw)
            echo "img"
            ;;
        *)
            log_error "Backend desconhecido: $(backend)"
            exit 1
            ;;
    esac
}

# diskpart_filename <name>
# Gera um nome de arquivo para a imagem de disco com a extensão correta do backend
#
# Argumentos:
#   name - O nome base para o arquivo de imagem de disco (sem extensão)
#
# Retorna:
#   O nome do arquivo com a extensão apropriada para o backend configurado.
#   Ex.: diskpart_filename "disk" -> "disk.qcow2" para backend qcow, ou "disk.img" para backend raw.
diskpart_filename() {
    local name="$1"
    local ext
    ext=$(backend_extension)
    echo "${name}.${ext}"
}

# diskpart_create_disk <output_path> <size>
# Cria uma imagem de disco usando o backend configurado
#
# Argumentos:
#   output_path - Caminho onde a imagem de disco será criada
#   size        - Tamanho da imagem de disco (ex: 500M, 10G)
#
# Retorna:
#   Um DiskImage se criado com êxito, ou sai com erro se a criação falhar.
#
diskpart_create_disk() {
    local output_path="$1"
    local size="$2"

    case "$(backend)" in
        qcow)
            _diskpart_create_qcow_disk "$output_path" "$size"
            echo "$output_path:qcow"
            ;;
        raw)
            _diskpart_create_raw_disk "$output_path" "$size"
            echo "$output_path:raw"
            ;;
        *)
            log_error "Backend desconhecido: $(backend)"
            exit 1
            ;;
    esac
}

# _diskpart_create_qcow_disk <output_path> <size>
# Cria uma imagem de disco QCOW2
#
# Argumentos:
#   output_path - Caminho onde a imagem de disco será criada
#   size        - Tamanho da imagem de disco (ex: 500M, 10G)
#
# Retorna:
#   0 se a imagem de disco foi criada com êxito, ou sai com erro se a criação falhar.
_diskpart_create_qcow_disk() {
    local output_path="$1"
    local size="$2"

    _validate_size "$size"

    log_info "Criando disco QCOW2 em '$output_path' com tamanho '$size'..."
    mkdir -p "$(dirname "$output_path")"
    exec_logged "DiskPart-qcow" qemu-img create -f qcow2 "$output_path" "$size"
    log_info "Disco criado com sucesso."
}

# _diskpart_create_raw_disk <output_path> <size>
# Cria uma imagem de disco RAW pré-alocada
#
# Argumentos:
#   output_path - Caminho onde a imagem de disco será criada
#   size        - Tamanho da imagem de disco (ex: 500M, 10G)
#
# Retorna:
#   0 se a imagem de disco foi criada com êxito, ou sai com erro se a criação falhar.
_diskpart_create_raw_disk() {
    local output_path="$1"
    local size="$2"

    _validate_size "$size"

    log_info "Criando disco pré-alocado em '$output_path' com tamanho '$size'..."
    mkdir -p "$(dirname "$output_path")"
    exec_logged "DiskPart-raw" qemu-img create -f raw "$output_path" "$size"
    log_info "Disco criado com sucesso."
}

# diskpart_create_device <disk_image> [track_device]
# Cria um dispositivo para a imagem de disco fornecida
#
# Argumentos:
#   disk_image - Um DiskImage para criar o dispositivo.
#   track_device - Flag para rastrear o dispositivo (opcional)
#
# Retorna:
#   Um DiskDevice com o dispositivo criado.
diskpart_create_device() {
    local disk_image="$1"
    local track_device="${2:-false}"

    local parsed image_path backend
    parsed=$(_diskpart_parse_disk_image "$disk_image")
    IFS=':' read -r image_path backend <<< "$parsed"

    if [[ ! -f "$image_path" ]]; then
        log_error "A imagem de disco '$image_path' não existe."
        exit 1
    fi

    log_verbose "Criando dispositivo para a imagem de disco '$image_path' usando o backend '$backend'..."

    local ext
    ext=$(backend_extension)

    if [[ ! "$image_path" = *.$ext ]]; then
        log_warning "A extensão do arquivo '$image_path' não corresponde à extensão esperada '$ext' para o backend '$(backend)'."
        log_warning "Isso pode indicar um erro de configuração ou um arquivo incorreto. Verifique seu unmm.conf e os arquivos de imagem de disco."
    fi

    local disk_device
    case "$backend" in
        qcow)
            log_verbose "Usando backend QCOW para criar dispositivo."
            disk_device=$(_diskpart_create_device_qcow "$image_path")
            ;;
        raw)
            log_verbose "Usando backend RAW para criar dispositivo."
            disk_device=$(_diskpart_create_device_raw "$image_path")
            ;;
        *)
            log_error "Backend desconhecido: $backend"
            exit 1
            ;;
    esac

    log_verbose "Dispositivo criado: $disk_device"
    if [[ -z "$disk_device" ]]; then
        log_error "Falha ao criar dispositivo para a imagem de disco '$image_path' usando o backend '$backend'."
        exit 1
    fi

    if [[ "$track_device" == true ]]; then
        diskpart_track_device "$disk_device"
    fi
    echo "$disk_device"
}

# _diskpart_create_device_qcow <disk_image>
# Cria um dispositivo para uma imagem de disco QCOW2 usando qemu-nbd
#
# Argumentos:
#   disk_image - Um DiskImage para criar o dispositivo.
#
# Retorna:
#   Um DiskDevice com o dispositivo criado, ou sai com erro se a criação falhar.
_diskpart_create_device_qcow() {
    local image_path="$1"

    log_verbose "Ativando módulo nbd para manipulação de disco QCOW2..."
    if ! modprobe nbd nbds_max=16 max_part=16; then
        log_error "Falha ao carregar o módulo nbd. Verifique se você tem permissões adequadas e se o módulo está disponível."
        exit 1
    fi

    local nbds_max part_max
    nbds_max=$(cat /sys/module/nbd/parameters/nbds_max)
    part_max=$(cat /sys/module/nbd/parameters/max_part)
    log_verbose "Configurações do nbd: nbds_max=$nbds_max, max_part=$part_max"

    if [[ "$nbds_max" -lt 1 ]]; then
        log_error "Não há dispositivos nbd disponíveis para uso. nbds_max é $nbds_max."
        exit 1
    fi

    if [[ "$part_max" -lt 3 ]]; then
        log_error "O número máximo de partições por dispositivo nbd é muito baixo para uso. max_part é $part_max."
        log_error "Considere aumentar max_part para pelo menos 3 para garantir funcionalidade adequada."
        exit 1
    fi

    log_verbose "Procurando por dispositivo nbd disponível..."
    local result=""
    for i in $(seq 0 $((nbds_max - 1))); do
        local nbd_device="/dev/nbd$i"
        local sys_nbd_device="/sys/block/nbd$i"

        log_verbose "Verificando dispositivo nbd: $nbd_device..."
        log_verbose "Verificando se '$nbd_device' está em uso via pid..."
        if [[ -s "$sys_nbd_device/pid" ]]; then
            local pid
            pid=$(cat "$sys_nbd_device/pid")
            log_verbose "Dispositivo nbd '$nbd_device' está em uso por PID $pid. Pulando."
            continue
        fi

        log_verbose "Tentando conectar '$image_path' ao dispositivo nbd '$nbd_device'..."
        if exec_logged2 "DiskPart-qcow" qemu-nbd --connect="$nbd_device" --fork "$image_path"; then
            log_info "Imagem de disco '$image_path' conectada com sucesso ao dispositivo nbd '$nbd_device'."
            result="$nbd_device:$image_path:qcow"
            break
        else
            log_warning "Falha ao conectar '$image_path' ao dispositivo nbd '$nbd_device'. Tentando próximo dispositivo nbd..."
        fi
    done

    if [[ -n "$result" ]]; then
        log_verbose "Dispositivo nbd disponível encontrado e conectado: $result"
        echo "$result"
        return 0
    fi

    log_error "Não foi possível conectar a imagem '$image_path' a nenhum dispositivo nbd disponível."
    log_error "Verifique se há dispositivos nbd livres e se você tem permissões adequadas."
    exit 1
}

# _diskpart_create_device_raw <disk_image>
# Cria um dispositivo raw para a imagem de disco fornecida com losetup.
#
# Argumentos:
#   disk_image - Um DiskImage para criar o dispositivo.
#
# Retorna:
#   Um DiskDevice com o dispositivo criado, ou sai com erro se a criação falhar.
_diskpart_create_device_raw() {
    local disk_image="$1"

    log_info "Configurando dispositivo loop para a imagem de disco '$disk_image'..."
    local loop_device
    loop_device=$(losetup --show -fP "$disk_image")
    log_info "Dispositivo loop configurado: $loop_device"
    echo "$loop_device:$disk_image:raw"
}

# diskpart_track_device <disk_device>
# Rastreia um dispositivo do diskpart para liberação posterior
#
# Argumentos:
#   disk_device - Um DiskDevice para ser rastreado.
diskpart_track_device() {
    local disk_device="$1"

    local parsed device image backend
    parsed=$(_diskpart_parse_disk_device "$disk_device")
    IFS=':' read -r device image backend <<< "$parsed"

    if [[ ! "$device" =~ /dev/(loop|nbd)[0-9]+ ]]; then
        log_error "Isso não parece ser um dispositivo do diskpart: $disk_device"
        exit 1
    fi

    if _diskpart_is_tracked_device "$device"; then
        log_verbose "Dispositivo '$device' já está sendo rastreado."
        return
    fi

    TRACKED_DISKPART_DEVICES+=("$device")
    log_verbose "Dispositivo adicionado ao rastreamento: $device"
}

# diskpart_untrack_device <disk_device>
# Para de rastrear um dispositivo do diskpart
#
# Argumentos:
#   disk_device - Um DiskDevice para ser removido do rastreamento
diskpart_untrack_device() {
    local disk_device="$1"

    local parsed device image backend
    parsed=$(_diskpart_parse_disk_device "$disk_device")
    IFS=':' read -r device image backend <<< "$parsed"

    if [[ ! "$device" =~ /dev/(loop|nbd)[0-9]+ ]]; then
        log_error "Isso não parece ser um dispositivo do diskpart: $disk_device"
        exit 1
    fi

    if ! _diskpart_is_tracked_device "$device"; then
        log_verbose "Dispositivo '$device' não está sendo rastreado."
        return
    fi

    TRACKED_DISKPART_DEVICES=("${TRACKED_DISKPART_DEVICES[@]/$device}")
    log_verbose "Dispositivo removido do rastreamento: $device"
}

# diskpart_free_device <disk_device>
# Libera um dispositivo do diskpart específico
#
# Argumentos:
#   disk_device - Um DiskDevice para ser liberado
diskpart_free_device() {
    local disk_device="$1"

    local parsed device image backend
    parsed=$(_diskpart_parse_disk_device "$disk_device")
    IFS=':' read -r device image backend <<< "$parsed"

    if [[ -z "$backend" ]]; then
        backend=$(_diskpart_infer_backend_from_device "$device")
    fi

    log_verbose "Liberando dispositivo '$device' para a imagem '$image'..."
    case "$backend" in
        qcow)
            log_verbose "Usando backend QCOW para liberar dispositivo."
            exec_logged "DiskPart-qcow" qemu-nbd --disconnect "$device"

            local device_name
            device_name=$(basename "$device")
            while [[ -s "/sys/block/$device_name/pid" ]]; do
                log_verbose "Aguardando o dispositivo nbd '$device' ser liberado..."
                sleep 1
            done
            log_verbose "Dispositivo nbd '$device' liberado com sucesso."
            ;;
        raw)
            log_verbose "Usando backend RAW para liberar dispositivo."
            exec_logged "DiskPart-raw" losetup -d "$device"
            ;;
        *)
            log_error "Backend desconhecido: $backend"
            exit 1
            ;;
    esac

    if _diskpart_is_tracked_device "$device"; then
        log_verbose "Removendo dispositivo '$device' do rastreamento após liberação."
        diskpart_untrack_device "$device"
        return
    fi
    log_info "Dispositivo '$device' liberado com sucesso."
}

# diskpart_free_all_disk_devices
# Libera todos os dispositivos do diskpart rastreados
diskpart_free_all_devices() {
    if [[ ${#TRACKED_DISKPART_DEVICES[@]} -eq 0 ]]; then
        log_verbose "Nenhum dispositivo do diskpart rastreado para liberar."
        return
    fi

    log_verbose "Liberando dispositivos do diskpart rastreados..."
    log_verbose "Dispositivos rastreados: ${TRACKED_DISKPART_DEVICES[*]}"
    for disk_device in "${TRACKED_DISKPART_DEVICES[@]}"; do
        log_verbose "Verificando dispositivo do diskpart: $disk_device"
        diskpart_free_device "$disk_device"
    done
    TRACKED_DISKPART_DEVICES=()
    log_verbose "Todos os dispositivos do diskpart rastreados foram liberados."
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

    log_verbose "Sincronizando dados antes de particionar..."
    _diskpart_run_udev_settle
    sync

    log_info "Deletando tudo em '$device' antes de criar a tabela de partições..."
    if ! exec_logged "DiskPart" wipefs -fa "$device"; then
        log_error "Falha ao limpar assinaturas de sistema de arquivos em '$device'."
        exit 1
    fi

    log_info "Criando tabela de partições '$part_schema' em '$device'..."
    case "$part_schema" in
        gpt)
            log_verbose "Usando comando parted para criar tabela de partições GPT."
            ;;
        msdos)
            log_verbose "Usando comando parted para criar tabela de partições MSDOS (MBR)."
            ;;
        *)
            log_error "Esquema de partição desconhecido: $part_schema"
            exit 1
            ;;
    esac
    if ! exec_logged "DiskPart" parted -s "$device" mklabel "$part_schema"; then
        log_error "Falha ao criar tabela de partições '$part_schema' em '$device'."
        exit 1
    fi

    _diskpart_run_partprobe "$device"
    _diskpart_run_udev_settle
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
            exec_logged "DiskPart" bash -c "mkfs.ext4 -F \"$partition_device\" 2>&1"
            ;;
        fat32)
            exec_logged "DiskPart" bash -c "mkfs.fat -F32 \"$partition_device\" 2>&1"
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
#   fs_type       - Tipo de sistema de arquivos (ex: ext4, fat32). Se vazio, a partição não será formatada,
#                       isso é comum em partições especiais como BIOS GRUB.
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
    exec_logged "DiskPart" parted -s "$device" $parted_command

    _diskpart_run_partprobe "$device"
    _diskpart_run_udev_settle

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
    exec_logged "DiskPart" parted -s "$device" set "$partition_number" "$flag_name" "$flag_value"
    log_verbose "Flag '$flag_name' definida como '$flag_value' na partição '$part_device'."
}

# diskpart_create_image_mbr_layout <device>
# Atalho para criar layout MBR completo em uma imagem de disco
# Argumentos:
#   device - Dispositivo onde o layout será criado
#
# Notas:
#   O layout MBR é o mais simples, com uma única partição que é a do sistema.
diskpart_create_image_mbr_layout() {
    local device="$1"
    log_info "Criando layout MBR na imagem de disco '$device'..."

    diskpart_create_partition_table "$device" "msdos"

    local system_partition
    log_info "Criando partição do sistema..."
    system_partition=$(diskpart_create_partition "$device" "primary" "ext4" "1MiB" "100%" true)
    log_verbose "A partição do sistema é $system_partition"

    log_info "Layout MBR criado com sucesso na imagem de disco."
}

# diskpart_create_image_gpt_layout <device> <ishybrid>
# Atalho para criar layout GPT completo em uma imagem de disco
# Argumentos:
#   device   - Dispositivo onde o layout será criado
#   ishybrid - Se true, cria uma partição BIOS GRUB adicional para suporte híbrido
#
# Notas:
#  O layout GPT é para os dispositivos mais modernos que usam UEFI e inclui a partição EFI + Sistema.
#  Esse layout também pode ser usado para suporte híbrido, onde uma partição BIOS GRUB é criada para 
# permitir boot em sistemas UEFI e BIOS.
diskpart_create_image_gpt_layout() {
    local device="$1"
    local ishybrid="$2"
    log_info "Criando layout GPT na imagem de disco '$device'..."

    diskpart_create_partition_table "$device" "gpt"
    
    local start_efi_partition="1MiB"
    local end_efi_partition="200MiB"

    local mbr_partition efi_partition system_partition
    
    if [[ "$ishybrid" == true ]]; then
        log_info "Criando partição BIOS GRUB para suporte híbrido..."
        mbr_partition=$(diskpart_create_partition "$device" "primary" "" "1MiB" "2MiB" false)
        diskpart_set_flag "$mbr_partition" "bios_grub" on
        log_verbose "A partição BIOS GRUB é $mbr_partition"

        log_verbose "Ajustando início e fim da partição EFI..."
        start_efi_partition=$(uc_add "$start_efi_partition" "1MiB")
        end_efi_partition=$(uc_add "$end_efi_partition" "1MiB")
    fi

    log_info "Criando partição EFI..."
    log_verbose "início: $start_efi_partition, fim: $end_efi_partition"
    efi_partition=$(diskpart_create_partition "$device" "primary" "fat32" "$start_efi_partition" "$end_efi_partition" true)
    diskpart_set_flag "$efi_partition" "boot" on
    diskpart_set_flag "$efi_partition" "esp" on
    log_verbose "A partição EFI é $efi_partition"

    log_info "Criando partição do sistema..."
    system_partition=$(diskpart_create_partition "$device" "primary" "ext4" "$end_efi_partition" "100%" true)
    log_verbose "A partição do sistema é $system_partition"

    log_info "Layout GPT criado com sucesso na imagem de disco."
}

# diskpart_disk_convert <disk_image> <output_format>
# Converte uma imagem de disco para um formato diferente usando qemu-img
# Argumentos:
#   disk_image    - Um DiskImage para ser convertido
#   output_format - O formato de saída desejado suportado pelo qemu-img e diskpart.
diskpart_disk_convert() {
    local disk_image="$1"
    local output_format="$2"

    log_info "Convertendo imagem '$disk_image' para '$output_format'..."

    local parsed image_path backend
    parsed=$(_diskpart_parse_disk_image "$disk_image")
    IFS=':' read -r image_path backend <<< "$parsed"

    local dest_image_path
    local extra_args=""
    local output_qemu_format
    case "$output_format" in
        qcow2)
            log_verbose "Formato de saída é QCOW2."
            dest_image_path="${image_path%.*}.qcow2"
            output_qemu_format="qcow2"
            ;;
        img)
            log_verbose "Formato de saída é RAW."
            dest_image_path="${image_path%.*}.img"
            output_qemu_format="raw"
            ;;
        vmdk)
            log_verbose "Formato de saída é VMDK."
            dest_image_path="${image_path%.*}.vmdk"
            extra_args="-o subformat=streamOptimized"
            output_qemu_format="vmdk"
            ;;
        *)
            log_error "Formato de saída desconhecido: $output_format"
            exit 1
            ;;
    esac

    local source_format
    source_format=$(_diskpart_guess_format_from_path "$image_path")
    if [[ -z "$source_format" && -n "$backend" ]]; then
        if [[ "$backend" == "qcow" ]]; then
            source_format="qcow2"
        elif [[ "$backend" == "raw" ]]; then
            source_format="raw"
        fi
    fi

    if [[ -n "$source_format" ]]; then
        exec_logged "DiskPart" qemu-img convert -f "$source_format" -O "$output_qemu_format" $extra_args "$image_path" "$dest_image_path"
    else
        exec_logged "DiskPart" qemu-img convert -O "$output_qemu_format" $extra_args "$image_path" "$dest_image_path"
    fi
    log_info "Conversão para $output_format concluída com sucesso."
    echo "$dest_image_path"
}

# diskpart_cleanup
# Libera todos os dispositivos do diskpart rastreados e, se o backend for qcow, 
# tenta descarregar o módulo nbd se não estiver mais em uso.
diskpart_cleanup() {
    log_verbose "Executando limpeza do diskpart..."
    diskpart_free_all_devices

    if [[ "$(backend)" == "qcow" && -d "/sys/module/nbd" ]]; then
        log_verbose "Verificando se há dispositivos nbd ainda em uso após a limpeza..."

        local nbd_refcnt
        nbd_refcnt=$(cat /sys/module/nbd/refcnt)

        if [[ "$nbd_refcnt" -ne 0 ]]; then
            log_warning "O módulo nbd está sendo usado, não será descarregado. Refcnt atual: $nbd_refcnt"
            log_warning "Note que um bug pode existir e impedir do disco resultante ser liberado."
            log_warning "Portanto, verifique e desconecte manualmente quaisquer dispositivos nbd restantes se necessário."
        else
            log_verbose "Nenhum dispositivo nbd em uso, descarregando módulo nbd..."
            if ! modprobe -r nbd; then
                log_warning "Falha ao descarregar o módulo nbd. Verifique se há processos usando nbd ou se o módulo está travado."
                log_warning "Refcnt atual: $(cat /sys/module/nbd/refcnt)"
            else
                log_verbose "Módulo nbd descarregado com sucesso."
            fi
        fi
    fi
    log_verbose "Limpeza do diskpart concluída."
}