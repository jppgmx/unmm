UNMM - Ubuntu Noble Minimal Maker
=================================

O que é
-------
UNMM é um script para criar imagens mínimas do Ubuntu Noble, usando catálogos e add-ons para compor o sistema final.

Objetivo
--------
Automatizar a montagem de imagens mínimas com configuração simples e reproduzível, mantendo o foco em um fluxo direto.

Contexto acadêmico (preencher)
------------------------------
Essa ideia começou na faculdade, especialmente no IFPB (Instituto Federal da Paraíba), melhor ainda, no novo IFSPB (Instituto Federal do Sertão Paraibano). Quando estive cursando a disciplina de Redes de Computadores, o professor meio que tinha VMs do Ubuntu 14, sendo uma com LXC e outra com Docker. Então surgiu uma ideia de recriar elas, só que usando a edição Noble. Foi feito manualmente, e tive a ideia de criar esse sistema de automação.

Requisitos
----------
- Distribuição Linux baseada em Debian ou Arch.
- Python 3.11+.
- Dependências principais (ver [lib/depends.sh](lib/depends.sh)):
  - Disco/imagem: util-linux (wipefs, losetup, blkid), parted, e2fsprogs (mkfs.ext4), dosfstools (mkfs.vfat).
  - Construção: debootstrap, coreutils (chroot, sha256sum).
  - Utilitários: wget, tar, gawk, grep, sed.
  - QEMU: qemu-utils (Debian) ou qemu-img (Arch).

Configuração
------------
- O arquivo base é [unmm.conf](unmm.conf). A CLI sobrescreve os valores desse arquivo.
- Seções principais: [General], [Lib.Logging], [Lib.DiskPart], [System], [System.Swap], [Export], [Export.OVA].
- As libs em [lib](lib) concentram utilitários de logging, dependências, orquestração e configuração.

Passo a passo (uso)
-------------------
1) Execute como root e com as dependências instaladas.
2) Liste os catálogos e add-ons disponíveis.
3) Rode o script com o catálogo e add-ons desejados.

```bash
sudo ./unmm.sh --list
sudo ./unmm.sh
sudo ./unmm.sh base lxqt
```

Catálogos e add-ons customizados
--------------------------------
- Estrutura base em [catalog](catalog) e [addons](addons).
- Templates prontos em [assets/catalog-template](assets/catalog-template) e [assets/addon-template](assets/addon-template).
- Instruções detalhadas em [docs/DocumentingAddonsCatalogs.md](docs/DocumentingAddonsCatalogs.md).

Copyright (c) 2025- Jppgmx. MIT.
