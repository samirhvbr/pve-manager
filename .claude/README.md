# Configuração Claude Code — Blue3 Cloud (fork pve-manager)

## Modelo

Perfil **Opus-only**: `opus[1m]` com janela de 1M, `effortLevel: xhigh`.
Subagentes também em Opus.

## Permissões críticas

O que este projeto tem de diferente dos outros repos Blue3:

### Bloqueado (deny)

- **Chaves WireGuard** — `keys-*/`, `*.key`, `wg-mgmt.conf`. São as chaves que
  dão acesso ao plano de controle do cluster; agente nenhum precisa lê-las.
- **`/etc/pve/**`** — configuração viva do cluster. Este repo é o *fonte*, não
  o sistema em produção.
- **`systemctl restart/stop pveproxy|pvedaemon`** — derruba a interface web de
  quem estiver usando. Se precisar, o operador faz.
- **`qm destroy` / `pct destroy` / `pvesh delete`** — destroem VMs e recursos.
- **`apt install` / `dpkg -i`** — instalar pacote é decisão do operador.

### Pergunta antes (ask)

- **`make install`** sem `DESTDIR` escreve direto em `/usr/share/pve-manager`.
  Com `DESTDIR=/tmp/...` está liberado, porque é como se testa o build.
- **`pvesh` / `pveum`** — API e gestão de usuários do PVE. Leitura é útil,
  escrita precisa de aval.
- **`wg` / `wg-quick`** — mexem no túnel de gerência.

### Liberado

Validação de sintaxe (`node --check`, `perl -c`, `bash -n`), lint
(`proxmox-biome`), busca, e `make ... install DESTDIR=/tmp/*` para testar
empacotamento sem tocar no sistema.

## Modo padrão

`plan` — este é um fork de um sistema de virtualização em produção. Ver o plano
antes da execução vale o atrito.
