#!/usr/bin/bash

# UNMM Runner Module
# Orquestra a listagem de catálogos e add-ons sem executar instalação.

if [[ -n "${UNMM_LIB_RUNNER_LOADED:-}" ]]; then
    return 0
fi
UNMM_LIB_RUNNER_LOADED=true

runner_list_available() {
    local catalog_dir="$1"
    local addons_dir="$2"

    log_info "Catálogos disponíveis:"
    for catalog_path in "$catalog_dir"/*/; do
        if [[ -f "$catalog_path/install" ]]; then
            # shellcheck disable=SC1090
            source "$catalog_path/install" >/dev/null 2>&1
            log_info " - $(catalog_name): $(catalog_display_name) (Versão: $(catalog_version))"
            log_info "   $(catalog_description)"
            log_info
        fi
    done

    log_info "Add-ons disponíveis:"
    for addon_path in "$addons_dir"/*/; do
        if [[ -f "$addon_path/install" ]]; then
            # shellcheck disable=SC1090
            source "$addon_path/install" >/dev/null 2>&1
            log_info " - $(addon_name): $(addon_display_name) (Versão: $(addon_version))"
            log_info "   $(addon_description)"
            log_info
        fi
    done
}