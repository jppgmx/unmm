# Criação de Add-ons e Catálogos no UNMM

Aqui explicamos como criar add-ons e catálogos customizados usando a estrutura atual do repositório. A herança oficial entre add-ons e catálogos será implementada em breve. Até lá, use `source` quando precisar reutilizar lógica.

## Onde ficam

- `addons/<id>/` para add-ons.
- `catalog/<id>/` para catálogos.

## Estrutura mínima de um add-on

```
addons/<id>/
  addon.conf
  install
  config/
    addon
  assets/            (*opcional*)
```

- `addon.conf`: metadados (DisplayName, Description, Version, etc.).
- `install`: script principal; deve carregar `lib/common.sh`, `addon.conf` e `config/addon`.
- `config/addon`: getters de metadados (gerado/seguido pelo padrão atual).
- `assets/`: arquivos extras (templates, configs, temas, etc.).

### Parâmetros disponíveis no `addon_install`

**Nota**: Esses parâmetros eram usados na versão 1.X e a CLI não define mais.
Alguns add-ons e catálogos existentes podem definir isso para manter a compatibilidade sem quebrar o código.

- `ADDON_INSTALL_ARG_DISKIMAGEPATH`
- `ADDON_INSTALL_ARG_DEVICE`
- `ADDON_INSTALL_ARG_MOUNTPOINT`
- `ADDON_INSTALL_ARG_HOSTNAME`
- `ADDON_INSTALL_ARG_USERNAME`
- `ADDON_INSTALL_ARG_PASSWORD`
- `ADDON_INSTALL_ARG_BOOTMODE`
- `ADDON_INSTALL_ARG_SIZE`
- `ADDON_INSTALL_ARG_INSTALLED_CATALOG`

## Estrutura mínima de um catálogo

```
catalog/<id>/
  catalog.conf
  install
  config/
    catalog
```

- `catalog.conf`: metadados (DisplayName, Description, Version, PreferredSize, etc.).
- `install`: script principal; deve carregar `lib/common.sh`, `catalog.conf` e `config/catalog`.
- `config/catalog`: getters de metadados (gerado/seguido pelo padrão atual).

### Parâmetros disponíveis no `catalog_install`

**Nota**: Esses parâmetros eram usados na versão 1.X e a CLI não define mais.
Alguns add-ons e catálogos existentes podem definir isso para manter a compatibilidade sem quebrar o código.

- `CATALOG_INSTALL_ARG_DISKIMAGEPATH`
- `CATALOG_INSTALL_ARG_DEVICE`
- `CATALOG_INSTALL_ARG_MOUNTPOINT`
- `CATALOG_INSTALL_ARG_HOSTNAME`
- `CATALOG_INSTALL_ARG_USERNAME`
- `CATALOG_INSTALL_ARG_PASSWORD`
- `CATALOG_INSTALL_ARG_BOOTMODE`
- `CATALOG_INSTALL_ARG_SIZE`

## Catálogo base e reaproveitamento

- Catálogos customizados devem partir do `base` e chamar `_base_install`.
- Enquanto a herança oficial não chega, use `source "$(dirname "$0")/base"` para reutilizar o comportamento do catálogo base.
- Add-ons podem reutilizar lógica de outros add-ons via `source` quando necessário.

## Templates prontos

- Add-on: `assets/addon-template`
- Catálogo: `assets/catalog-template`

Use esses arquivos como ponto de partida para manter o padrão do repositório.
