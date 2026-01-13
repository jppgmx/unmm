#!/bin/bash
#
#   UNMM Chroot Module
#   - Version: 1.0.0
#   - Description: Módulo de manipulação de chroot para UNMM.
#
#   Sob licença MIT
#

declare -ag SYSTEM_MOUNTPOINTS
if [[ -z "${SYSTEM_MOUNTPOINTS+x}" ]]; then
    SYSTEM_MOUNTPOINTS=()
fi

# chroot_mount_partitions <device> <mountpoint>
# Monta as partições necessárias da imagem no ponto de montagem especificado.
#
# Argumentos:
#   device - Dispositivo de bloco da imagem (ex: /dev/loop0)
#   mountpoint - Ponto de montagem base (ex: /mnt/chroot)
chroot_mount_system() {
    local device="$1"
    local mountpoint="$2"

    log_info "Montando partições da imagem..."

    local schema base_mountpoint partitions system_partition
    schema="$(diskpart_get_disk_partition_schema "$device")"
    base_mountpoint="$mountpoint"
    partitions="$(diskpart_get_partitions "$device")"
    system_partition="${device}p$(echo "$partitions" | grep ext4 | cut -d';' -f1 | cut -d'=' -f2)"

    log_verbose "Montando partição do sistema: $system_partition em $base_mountpoint"
    mkdir -p "$base_mountpoint"
    if ! mount "$system_partition" "$base_mountpoint"; then
        log_error "Falha ao montar a partição do sistema $system_partition em $base_mountpoint"
        exit 1
    fi

    SYSTEM_MOUNTPOINTS+=("$base_mountpoint")

    if [[ $schema == "gpt" ]]; then
        local efi_partition
        efi_partition="${device}p$(echo "$partitions" | grep fat32 | cut -d';' -f1 | cut -d'=' -f2)"
        mkdir -p "$base_mountpoint/boot/efi"

        log_verbose "Montando partição EFI: $efi_partition em $base_mountpoint/boot/efi"
        if ! mount "$efi_partition" "$base_mountpoint/boot/efi"; then
            log_error "Falha ao montar a partição EFI $efi_partition em $base_mountpoint/boot/efi"
            exit 1
        fi
        SYSTEM_MOUNTPOINTS+=("$base_mountpoint/boot/efi")
    fi

    log_info "Partições montadas com sucesso."
    log_info "Montagens atuais: ${SYSTEM_MOUNTPOINTS[*]}"
}

# Dicionário de sistemas de arquivos virtuais a serem montados no chroot
readonly VIRTUAL_FILESYSTEMS=(
    "/dev:devtmpfs:dev"
    "/dev/pts:devpts:devpts"
    "/proc:proc:proc"
    "/sys:sysfs:sys"
    "/run:tmpfs:tmpfs"
    "/tmp:tmpfs:tmpfs"
)

# chroot_prepare_environment <mountpoint>
# Prepara o ambiente chroot montando os sistemas de arquivos virtuais necessários.
#
# Argumentos:
#   mountpoint - Ponto de montagem base do chroot (ex: /mnt/chroot)
chroot_prepare_environment() {
    local base_mountpoint="$1"

    log_info "Montando sistemas virtuais no chroot..."

    for vfs in "${VIRTUAL_FILESYSTEMS[@]}"; do
        IFS=':' read -r mount_dir fs_type fs_source <<< "$vfs"
        local full_mount_point="$base_mountpoint$mount_dir"

        log_verbose "Montando $fs_type em $full_mount_point..."
        if ! mount -t "$fs_type" "$fs_source" "$full_mount_point"; then
            log_error "Falha ao montar $fs_type em $full_mount_point"
            exit 1
        fi
        SYSTEM_MOUNTPOINTS+=("$full_mount_point")
    done

    log_verbose "Copiando resolv.conf mantendo um backup..."
    cp "$base_mountpoint/etc/resolv.conf" "$base_mountpoint/etc/resolv.conf.bak" || true
    cp /etc/resolv.conf "$base_mountpoint/etc/resolv.conf"
}

# chroot_call <mountpoint> <command...>
# Executa um comando dentro do ambiente chroot. 
# É necessário tenha sido chamado "chroot_mount_system" e "chroot_prepare_environment" antes.
#
# Argumentos:
#   mountpoint - Ponto de montagem base do chroot (ex: /mnt/chroot)
#   command - Comando a ser executado dentro do chroot
#
# Retorna:
#   Código de saída do comando executado.
chroot_call() {
    local mountpoint="$1"
    shift
    local command=("$@")

    log_verbose "Executando comando no chroot: ${command[*]}"
    chroot "$mountpoint" "${command[@]}"

    local exit_code=$?
    log_verbose "Comando no chroot finalizado com código de saída: $exit_code"
    return $exit_code
}

# chroot_call_logged <mountpoint> <command...>
# Executa um comando dentro do ambiente chroot com logging detalhado. 
# É necessário tenha sido chamado "chroot_mount_system" e "chroot_prepare_environment" antes.
chroot_call_logged() {
    local mountpoint="$1"
    shift
    local command=("$@")

    log_verbose "Executando comando no chroot com log: ${command[*]}"
    exec_logged "chroot $mountpoint" chroot "$mountpoint" "${command[@]}"
    local exit_code=$?
    log_verbose "Comando no chroot finalizado com código de saída: $exit_code"
    return $exit_code
}

# chroot_cleanup
# Realiza a limpeza do sistema dentro do chroot e desmonta todas as partições montadas.
chroot_cleanup() {
    if [[ ${#SYSTEM_MOUNTPOINTS[@]} -eq 0 ]]; then
        log_warning "Não há nada para limpar."
        return 0
    fi

    local mountpoint="${SYSTEM_MOUNTPOINTS[0]}"

    log_info "Fazendo limpeza do sistema..."
    log_verbose "Limpando caches do apt..."
    chroot_call_logged "$mountpoint" apt-get clean || log_warning "Falha ao limpar caches do apt."

    log_verbose "Removendo listas do apt..."
    rm -rf "$mountpoint/var/lib/apt/lists/*" || log_warning "Falha ao remover listas do apt."

    log_verbose "Autoremovendo pacotes órfãos..."
    chroot_call_logged "$mountpoint" apt-get autoremove -y || log_warning "Falha ao autoremover pacotes órfãos."

    log_verbose "Removendo identidade da máquina..."
    chroot_call_logged "$mountpoint" truncate -s 0 /etc/machine-id || log_warning "Falha ao truncar /etc/machine-id."
    chroot_call_logged "$mountpoint" rm -f /var/lib/dbus/machine-id || log_warning "Falha ao remover /var/lib/dbus/machine-id."
    chroot_call_logged "$mountpoint" ln -s /etc/machine-id /var/lib/dbus/machine-id || log_warning "Falha ao criar link simbólico para machine-id."
    
    log_verbose "Removendo chaves SSH do host..."
    chroot_call_logged "$mountpoint" rm -f /etc/ssh/ssh_host_* || log_warning "Falha ao remover chaves SSH do host."

    log_verbose "Limpando leases de DHCP antigos..."
    chroot_call_logged "$mountpoint" rm -f /var/lib/dhcp/* || log_warning "Falha ao remover leases de DHCP."

    log_verbose "Esvaziando arquivos de log sem deletá-los..."
    chroot_call_logged "$mountpoint" find /var/log -type f -exec truncate -s 0 {} \; || log_warning "Falha ao esvaziar arquivos de log."
    
    log_verbose "Removendo arquivos de log rotacionados..."
    chroot_call_logged "$mountpoint" rm -rf /var/log/*.gz /var/log/*.[0-9] /var/log/*.old || log_warning "Falha ao remover arquivos de log rotacionados."
    
    log_verbose "Limpando journal do systemd..."
    chroot_call_logged "$mountpoint" journalctl --vacuum-time=1s || log_warning "Falha ao limpar journal do systemd."

    log_verbose "Limpando histórico e arquivos temporários..."
    chroot_call_logged "$mountpoint" rm -rf /tmp/* || log_warning "Falha ao limpar /tmp."
    chroot_call_logged "$mountpoint" rm -rf /var/tmp/* || log_warning "Falha ao limpar /var/tmp."
    chroot_call_logged "$mountpoint" rm -f /root/.bash_history || log_warning "Falha ao remover histórico do root."
    chroot_call_logged "$mountpoint" rm -f /home/*/.bash_history || log_warning "Falha ao remover histórico dos usuários."
    chroot_call_logged "$mountpoint" rm -rf /home/*/.cache/thumbnails || log_warning "Falha ao limpar thumbnails dos usuários."
    chroot_call_logged "$mountpoint" rm -rf /home/*/.cache/mozilla || log_warning "Falha ao limpar cache do Mozilla dos usuários."

    log_verbose "Desligando swap..."
    chroot_call_logged "$mountpoint" swapoff -a || log_warning "Falha ao desligar swap."
    log_verbose "Preenchendo swapfile com zeros..."
    chroot_call_logged "$mountpoint" dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress || log_warning "Falha ao preencher swapfile com zeros."
    chroot_call_logged "$mountpoint" mkswap /swapfile || log_warning "Falha ao recriar swapfile."

    log_info "Desmontando sistema..."

    local count=${#SYSTEM_MOUNTPOINTS[@]}
    for (( i=count-1; i>=0; i-- )); do
        local mountpoint="${SYSTEM_MOUNTPOINTS[$i]}"
        log_verbose "Desmontando $mountpoint..."
        exec_logged "CHROOT" umount "$mountpoint" || log_warning "Falha ao desmontar $mountpoint"
    done
    SYSTEM_MOUNTPOINTS=()
    if [[ -f "$mountpoint/etc/resolv.conf.bak" ]]; then
        log_verbose "Restaurando backup de resolv.conf..."
        mv "$mountpoint/etc/resolv.conf.bak" "$mountpoint/etc/resolv.conf" || log_warning "Falha ao restaurar resolv.conf"
    fi
    log_info "Desmontagem concluída."
}
