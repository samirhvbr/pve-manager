# Laboratório `blue3-lab` — ambiente e como foi montado

**Montado em:** 13/08/2026 · **Estado:** operacional, com o fork rodando

Cluster de 2 nós usado para validar o fork antes da produção. Snapshots existem
nos dois — rollback disponível.

| | b3pve1 | b3pve2 |
|---|---|---|
| IP | 100.64.100.254 | 100.64.100.253 |
| FQDN | `b3pve1.blue3.cloud` | `b3pve2.blue3.cloud` |
| RAM · vCPU | 8 GB · 4 | 4 GB · 4 |
| `/` · `/var` | 20 G · 22 G | 20 G · 22 G |
| PVE | 9.2.10 · kernel 7.0.14-11-pve | idem |
| Fork | **9.2.10+blue3.1** | **9.2.10+blue3.1** |

Cluster `blue3-lab`, quorado, link único no `ens18` (rede de gerência).

---

## Preparação do SO — o que o template não entregava pronto

Os dois nasceram de um template Debian 13 que precisou de quatro correções.
**Repita todas ao provisionar um nó novo**:

### 1. `/etc/hosts` — a causa nº 1 de PVE que não sobe

`hostname -i` devolvia `127.0.1.1` no b3pve1; no b3pve2 o `/etc/hosts` ainda
dizia `blue3` (nome do template) e `hostname -f` falhava por completo. O
`pve-cluster` resolve o próprio nome para achar o IP de gerência — com loopback
ele não sobe, e a formação de cluster falha depois.

```
100.64.100.254	b3pve1.blue3.cloud b3pve1
```

> O nome do nó PVE é derivado do hostname **na instalação** e é muito difícil de
> mudar depois. O hostname do b3pve1 mudou de `b3pve` para `b3pve1` entre boots
> e só foi notado por acaso — **confira `hostname -f` antes de instalar**.

### 2. Disco — o template entrega `/` com 7,6 GB

Pequeno demais para PVE + build. Havia 30,7 GB não alocados no `vg0`:

```bash
lvextend -L +12G /dev/vg0/root && xfs_growfs /
lvextend -L +14G /dev/vg0/var  && btrfs filesystem resize max /var
```

### 3. `machine-id` idêntico nos dois

Herdado do template (`3b6eb0e7…`). Pegadinha: **`systemd-machine-id-setup`
recupera o valor de `/var/lib/dbus/machine-id`** — apagar só o `/etc/machine-id`
não adianta.

```bash
rm -f /etc/machine-id /var/lib/dbus/machine-id
systemd-machine-id-setup            # deriva do UUID do SMBIOS/DMI
cp -f /etc/machine-id /var/lib/dbus/machine-id
```

### 4. Chave de host SSH idêntica nos dois

Quebra a proteção contra MITM entre eles.

```bash
rm -f /etc/ssh/ssh_host_*
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure openssh-server
```

---

## Instalação do PVE

O firewall bloqueava **todo** egresso TCP das VMs (portas 80, 443, 22, 53, 123 —
nenhuma passava; só ICMP e DNS/UDP). Enquanto isso durou, o b3pve1 foi instalado
por transporte offline: `apt-get --download-only` numa máquina com saída, usando
o **`/var/lib/dpkg/status` da VM** para resolver exatamente o que faltava lá,
depois `dpkg-scanpackages` e um repo `file://` na VM.

Depois que o egresso foi liberado (13/08), o b3pve2 foi instalado direto pela
rede — muito mais simples. O caminho offline fica registrado em
[`../blue3-deploy/lab-install.sh`](../blue3-deploy/lab-install.sh) caso volte a
ser preciso.

**Detalhes que importam:**

- A instalação **remove `ifupdown` e `vlan`**, substituídos por `ifupdown2`. É o
  momento em que o SSH pode cair — rodamos com `setsid nohup` para o processo
  sobreviver à queda. Na prática a rede aguentou nos dois.
- `postfix` é interativo; sem `debconf-set-selections` a instalação trava.
- O repo **enterprise vem habilitado por padrão** e dá 401 sem assinatura. No
  PVE 9 ele está em formato deb822 (`pve-enterprise.sources`), não `.list` —
  desativa-se com `Enabled: no`.
- Precisa de **reboot** para carregar o kernel PVE.

---

## Build do fork

`proxmox-biome` (build-dep) **não está no `pve-no-subscription`** — vive no repo
`devel`. Foi adicionado, usado, e **desativado em seguida**: repo de
desenvolvimento aberto num nó puxaria pacotes instáveis sem querer.

```bash
apt install devscripts equivs
mk-build-deps -ir -t "apt-get -y --no-install-recommends" debian/control
make check && make deb
dpkg -i ../pve-manager_9.2.10+blue3.1_all.deb
```

O `.deb` sai em `/root/pve-manager/`, não em `/root` — o Makefile compila num
subdiretório e escreve no pai. O `git rev-parse` do Makefile exige o `.git`
presente e `git config --global --add safe.directory` quando o dono difere.

---

## Validado no ambiente real

| O que | Resultado |
|---|---|
| `make check` (lint) | **375 arquivos, 0 erro, 0 warning** (`--error-on-warnings`) |
| Testes Perl | todos passaram |
| `lintian` | só avisos de macro groff das man pages do upstream |
| Título servido | `<title>b3pve1 - Blue3 Cloud</title>` nos dois nós |
| Assets Blue3 | logo, CSS e favicon respondendo HTTP 200 |
| Nag de subscription | 1 chamada legítima restante (botão "Check"), 2 removidas |
| `preflight.sh` | detectou os 2 nós do `corosync.conf` e montou o `ALLOW_FROM` correto |

O caminho de cluster do `preflight.sh` era código escrito às cegas — este
laboratório foi a primeira vez que rodou contra um cluster de verdade.
