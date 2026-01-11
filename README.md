# UNMM - Ubuntu Noble Minimal Maker

**UNMM** é uma ferramenta automatizada de linha de comando projetada para criar imagens personalizadas e mínimas do **Ubuntu 24.04 LTS (Noble Numbat)**. Ele utiliza uma abordagem modular baseada em **CatáLogos** e **Add-ons**, permitindo que você construa desde sistemas servidores ultra-leves até ambientes desktop funcionais, exportando tanto para imagens de disco bruto (RAW) quanto para Virtual Appliances (OVA) compatíveis com VMware e VirtualBox.

## Funcionalidades

- **Base Mínima**: Utiliza `debootstrap` para construir um sistema limpo e sem bloatware.
- **Modularidade Total**:
  - **Catálogos**: Definem a base do sistema (ex: `base`).
  - **Add-ons**: Camadas adicionais de software e configuração (ex: `lxqt`, `updates`).
- **Versatilidade de Boot**: Suporte nativo para **BIOS** (Legacy), **UEFI** e **Híbrido**.
- **Exportação OVA**: Gera pacotes `.ova` prontos para importação em hipervisores, com suporte a metadados OVF e licenças embutidas.
- **Configuração Automática**: Define particionamento, GRUB, usuários, rede (Netplan) e hostname automaticamente.
- **First Boot Manager**: Sistema inteligente que executa scripts de configuração na primeira inicialização da VM e se autodestrói depois.

## Pré-requisitos

O UNMM foi projetado para rodar somente em distribuições baseadas em Debian (Ubuntu, Debian, Mint, Kali) pelo fato de utilizar `debootstrap`.

Dependências necessárias:
- `debootstrap`
- `qemu-utils`
- `util-linux`
- `parted`
- `e2fsprogs`
- `dosfstools`
- `wget`
- `tar`
- `gawk`
- `grep`
- `sed`
- `coreutils`

O script verificará e oferecerá a instalação automática das dependências caso estejam no modo interativo.

## Uso

O script principal é o `unmm.sh`. Ele deve ser executado como **root** (sudo).

### Sintaxe Básica

```bash
sudo ./unmm.sh [OPÇÕES] [<CATÁLOGO> [ADDON1 ADDON2 ...]]
```

### Exemplos Comuns

**1. Criar uma imagem básica (modo interativo/padrão):**
```bash
sudo ./unmm.sh
```
*Gera uma imagem baseada no catálogo `base` em `./output/unmm-system.img`.*

**2. Criar uma imagem com ambiente gráfico LXQt:**
```bash
sudo ./unmm.sh base lxqt
```

**3. Criar uma VM completa (OVA) para VirtualBox/VMware:**
```bash
sudo ./unmm.sh --create-ova --hostname servidor-web base updates
```

**4. Personalizar tudo (Boot UEFI, Usuário, Tamanho):**
```bash
sudo ./unmm.sh \
  --boot-mode=uefi \
  --maximum-size=10G \
  --hostname=meu-servidor \
  --username=admin \
  --password=senha123 \
  base
```

### Opções Disponíveis

| Opção | Descrição |
|-------|-----------|
| `--create-ova` | Gera um arquivo `.ova` final além da imagem de disco. |
| `-b, --boot-mode` | Define o modo de boot: `bios` (padrão), `uefi` ou `hybrid`. |
| `-n, --hostname` | Define o nome do host da máquina. |
| `-u, --username` | Define o usuário padrão (padrão: `user`). |
| `-p, --password` | Define a senha (padrão: `password`). |
| `--maximum-size` | Tamanho do disco virtual (ex: `10G`, `500M`). |
| `-l, --license` | Opcional: Caminho para um arquivo txt de licença (EULA) para embutir no OVA. |
| `-v, --verbose` | Ativa logs detalhados para debug. |

Use `--list` para ver todos os catálogos e add-ons disponíveis:
```bash
sudo ./unmm.sh --list
```

## Estrutura do Projeto

```
matrix/
├── unmm.sh                 # Script principal (ponto de entrada)
├── lib/                    # Módulos da biblioteca
│   ├── common.sh           # Funções utilitárias
│   ├── depends.sh          # Verificação de dependências
│   ├── diskpart.sh         # Particionamento e formatação
│   ├── chroot.sh           # Manipulação de chroot
│   ├── logging.sh          # Sistema de logs e cores
│   └── ova.sh              # Geração de OVF/OVA
├── catalog/                # Definições de sistemas base
│   └── base                # Catálogo padrão (Ubuntu Minimal)
├── addons/                 # Módulos adicionais
│   ├── lxqt                # Desktop LXQt leve
│   └── updates             # Atualização do sistema no boot
└── assets/                 # Recursos estáticos
    ├── generic_LICENSE     # Licença padrão
    └── firstboot-manager/  # Scripts de inicialização
```

## Estendendo o UNMM

### Criando um Novo Catálogo
Crie um arquivo em `catalog/` sem extensão, definindo as seguintes variáveis:
- `CATALOG_NAME`: Nome do catálogo.
- `CATALOG_DISPLAY_NAME`: Nome amigável.
- `CATALOG_DESCRIPTION`: Descrição do catálogo.
- `CATALOG_VERSION`: Versão do catálogo.
- `CATALOG_PREFFERED_SIZE`: Tamanho recomendado da imagem.
- `catalog_install()`: Função que instala o catálogo.

**AVISO**: Novos catálogos **obrigatoriamente** devem ser baseados no catálogo `base` usando `source $(dirname "$0")/base`. Após isso, chame 
`_base_install` dentro da função `catalog_install` para garantir a instalação correta da base mínima. Isso ocorre porque o catálogo `base` contém todas as funções essenciais para a criação da imagem sem contar que
é ela que monta o disco usando `chroot_mount_system` e `chroot_prepare_environment`. Sem isso, o catálogo precisará fazer isso manualmente de modo que possa usar `chroot_call_logged` para executar comandos dentro do chroot.

#### Argumentos de Catálogo
Dentro da função `catalog_install`, você pode acessar os seguintes argumentos:
- `CATALOG_INSTALL_ARG_DISKIMAGEPATH`: Caminho completo para a imagem de disco.
- `CATALOG_INSTALL_ARG_DEVICE`: Dispositivo do disco (ex: `/dev/sdX`).
- `CATALOG_INSTALL_ARG_MOUNTPOINT`: Ponto de montagem do sistema.
- `CATALOG_INSTALL_ARG_HOSTNAME`: Nome do host.
- `CATALOG_INSTALL_ARG_USERNAME`: Nome do usuário.
- `CATALOG_INSTALL_ARG_PASSWORD`: Senha do usuário.
- `CATALOG_INSTALL_ARG_BOOTMODE`: Modo de boot (`bios`, `uefi`, `hybrid`).
- `CATALOG_INSTALL_ARG_SIZE`: Tamanho em bytes do disco.

#### Exemplo de Catálogo
```bash
# catalog/meucatalogo
source "$(dirname "$0")/base"
CATALOG_NAME="meucatalogo"
CATALOG_DISPLAY_NAME="Meu Catálogo Personalizado"
CATALOG_DESCRIPTION="Um catálogo personalizado baseado no Ubuntu Minimal."
CATALOG_VERSION="1.0"
CATALOG_PREFFERED_SIZE="5G"
catalog_install() {
    _base_install
    # Adicione aqui comandos adicionais para personalizar o catálogo
    chroot_call_logged apt-get install -y pacote-adicional
}
```

### Criando um Novo Add-on
A abordagem é semelhante à dos catálogos. Crie um arquivo em `addons/` sem extensão, definindo as seguintes variáveis:
- `ADDON_NAME`: Nome do add-on.
- `ADDON_DISPLAY_NAME`: Nome amigável.
- `ADDON_DESCRIPTION`: Descrição do add-on.
- `ADDON_VERSION`: Versão do add-on.
- `addon_install()`: Função que instala o add-on.

Addons podem ser derivados de outros addons usando `source $(dirname "$0")/outro_addon`.

Um add-on não precisa montar o sistema, pois isso já é feito pelo catálogo. Portanto, você pode usar diretamente `chroot_call_logged` para executar comandos dentro do chroot.

#### Parâmetros de Add-on
Dentro da função `addon_install`, você pode acessar os seguintes argumentos:
- `ADDON_INSTALL_ARG_DISKIMAGEPATH`: Caminho completo para a imagem de disco.
- `ADDON_INSTALL_ARG_DEVICE`: Dispositivo do disco (ex: `/dev/sdX`).
- `ADDON_INSTALL_ARG_MOUNTPOINT`: Ponto de montagem do sistema.
- `ADDON_INSTALL_ARG_HOSTNAME`: Nome do host.
- `ADDON_INSTALL_ARG_USERNAME`: Nome do usuário.
- `ADDON_INSTALL_ARG_PASSWORD`: Senha do usuário.
- `ADDON_INSTALL_ARG_BOOTMODE`: Modo de boot (`bios`, `uefi`, `hybrid`).
- `ADDON_INSTALL_ARG_SIZE`: Tamanho em bytes do disco.
- `ADDON_INSTALL_ARG_INSTALLED_CATALOG`: Nome do catálogo instalado.

#### Exemplo de Add-on
```bash
# addons/meuaddon
ADDON_NAME="meuaddon"
ADDON_DISPLAY_NAME="Meu Add-on Personalizado"
ADDON_DESCRIPTION="Um add-on personalizado para adicionar funcionalidades extras."
ADDON_VERSION="1.0"
addon_install() {
    # Adicione aqui comandos para instalar o add-on
    echo "Alguma configuração extra" > "${ADDON_INSTALL_ARG_MOUNTPOINT}/etc/meuaddon.conf"
}
```

## Licença

Este projeto é distribuído sob a licença MIT. Consulte o arquivo `LICENSE` para mais detalhes.

Copyright © 2026 João Paulo (Jppgmx)
