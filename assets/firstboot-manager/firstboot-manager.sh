#!/bin/bash
#
# UNMM First Boot Manager
# /usr/local/bin/firstboot-manager.sh
# Gerente de First Boot com Autodestruição
#
# Sob licença MIT
#

LOG_FILE="/var/log/firstboot.log"
SCRIPT_DIR="/opt/firstboot.d"
SERVICE_FILE="/etc/systemd/system/firstboot.service"
SELF_PATH="$0" # Caminho para este próprio script

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== INICIANDO FIRST BOOT ==="

# 1. Execução dos Payloads
if [ -d "$SCRIPT_DIR" ]; then
    if [[ -z "$(ls "$SCRIPT_DIR")" ]]; then
        log "Diretório de scripts está vazio. Pulando execução."
    else
        log "Executando scripts de first boot em $SCRIPT_DIR..."
    fi
    for script in "$SCRIPT_DIR"/*; do
        if [ -f "$script" ]; then
            log "Executando: $(basename "$script")..."
            chmod +x "$script"
            
            # Executa e captura saída
            if "$script" >> "$LOG_FILE" 2>&1; then
                log "SUCESSO: $(basename "$script")"
            else
                log "ERRO: $(basename "$script") falhou. Verifique o log."
            fi
        fi
    done
else
    log "Diretório de scripts não encontrado. Pulando execução."
fi

# 2. Início da Sequência de Autodestruição
log "=== INICIANDO LIMPEZA E AUTODESTRUIÇÃO ==="

# A. Apagar a pasta de payloads
log "Removendo diretório de scripts..."
rm -rf "$SCRIPT_DIR"

# B. Desabilitar e remover o serviço Systemd
log "Desabilitando e removendo serviço systemd..."
systemctl disable firstboot.service 2>/dev/null
rm -f "$SERVICE_FILE"

# C. Avisar o Systemd que o arquivo sumiu
log "Recarregando daemon do systemd..."
systemctl daemon-reload

# D. Apagar a si mesmo (O Grand Finale)
# O script continua rodando na memória até o 'exit', mesmo sem arquivo no disco
log "Apagando script gerente ($SELF_PATH)..."
rm -f "$SELF_PATH"

log "First Boot concluído. Adeus."
exit 0