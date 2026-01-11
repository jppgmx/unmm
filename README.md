# UNMM - Ubuntu Noble Minimal Maker

**UNMM** é uma ferramenta automatizada de linha de comando projetada para criar imagens personalizadas e mínimas do **Ubuntu 24.04 LTS (Noble Numbat)**. Ele utiliza uma abordagem modular baseada em **CatáLogos** e **Add-ons**, permitindo que você construa desde sistemas servidores ultra-leves até ambientes desktop funcionais, exportando tanto para imagens de disco bruto (RAW) quanto para Virtual Appliances (OVA) compatíveis com VMware e VirtualBox.

## 🚀 Funcionalidades

- **Base Mínima**: Utiliza `debootstrap` para construir um sistema limpo e sem bloatware.
- **Modularidade Total**:
  - **Catálogos**: Definem a base do sistema (ex: `base`).
  - **Add-ons**: Camadas adicionais de software e configuração (ex: `lxqt`, `updates`).
- **Versatilidade de Boot**: Suporte nativo para **BIOS** (Legacy), **UEFI** e **Híbrido**.
- **Exportação OVA**: Gera pacotes `.ova` prontos para importação em hipervisores, com suporte a metadados OVF e licenças embutidas.
- **Configuração Automática**: Define particionamento, GRUB, usuários, rede (Netplan) e hostname automaticamente.
- **First Boot Manager**: Sistema inteligente que executa scripts de configuração na primeira inicialização da VM e se autodestrói depois.

## 📋 Pré-requisitos

O UNMM foi projetado para rodar em distribuições baseadas em Debian (Ubuntu, Debian, Mint, Kali).

Dependências necessárias:
- `qemu-utils` (qemu-img)
- `debootstrap`
- `parted`
- `gawk`, `sed`, `grep`, `tar`, `wget`
- `dosfstools` (para UEFI)

O script verificará e oferecerá a instalação automática das dependências caso estejam faltando.

## 🛠️ Uso

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

## 📂 Estrutura do Projeto

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

## 🧩 Estendendo o UNMM

### Criando um Novo Catálogo
Crie um arquivo em `catalog/` definindo as variáveis `CATALOG_NAME`, `_SYSTEM_PACKAGES_ESSENTIALS` e a função `catalog_install`.

### Criando um Novo Add-on
Crie um arquivo em `addons/` definindo `ADDON_NAME` e a função `addon_install`. Você pode usar `chroot_call_logged` para executar comandos dentro da imagem sendo criada.

## 📄 Licença

Este projeto é distribuído sob a licença MIT. Consulte o arquivo `LICENSE` para mais detalhes.

Copyright © 2026 João Paulo (Jppgmx)
