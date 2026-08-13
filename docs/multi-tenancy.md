# Multi-tenancy no PVE — o que dá e o que não dá

**Análise:** 13/08/2026 · **Base:** pve-manager 9.2.10
**Método:** verificado no código deste repositório, não de memória.

---

## Requisitos avaliados

1. Admin derrubar/cancelar acesso de um usuário **rapidamente**
2. Liberar uma **fração do cluster** para uma empresa, que gerencia os próprios
   usuários
3. Admin travar a **empresa inteira** ou um **usuário específico** dela
4. Liberar mais **memória, disco e vCPU** para uma empresa

**Resultado: 1, 2 e 3 são nativos. O 4 não existe no PVE.**

---

## 1. Revogação rápida — nativo, e mais rápido do que se espera

`PVE/HTTPServer.pm:98` chama `check_user_enabled` em **toda requisição
autenticada**, dentro da verificação de ticket:

```perl
($username, $age, $tfa_info) = PVE::AccessControl::verify_ticket($ticket);
$rpcenv->check_user_enabled($username);
```

**Consequência:** desmarcar "Enabled" no usuário vale na próxima chamada de API
— segundos. Não espera o ticket expirar (2h), não precisa reiniciar serviço.

Existe também o campo `expire` no usuário, para acesso com validade.

**Ressalva:** console noVNC/SPICE **já aberto** é websocket estabelecido.
Desabilitar barra novas requisições, mas não necessariamente derruba a conexão
em curso.

---

## 2. Delegação por empresa — nativo

### Paths de ACL disponíveis

Confirmados em `www/manager6/data/PermPathStore.js:6-23`:

```
/                    /mapping/*           /sdn/fabrics
/access              /nodes               /sdn/zones
/access/groups       /pool                /storage
/access/realm                             /vms
```

Mais os paths específicos gerados a partir dos recursos (`/pool/<id>`,
`/vms/<vmid>`, `/storage/<id>`, `/nodes/<node>`).

**`/access/realm/<id>` é a chave da delegação** — é o que permite dar
`User.Modify` limitado a um realm, para a empresa gerenciar só a própria gente.

`www/manager6/form/PermPathSelector.js` é um ComboBox **sem `forceSelection`**,
então aceita path digitado livremente — `/access/realm/empresa-a` funciona.

### Pools aninhados existem

`PVE/API2/Pool.pm` valida explicitamente pai/filho na criação:

```perl
if ($pool =~ m!^(.*)/([^/]+)$!) {
    my ($parent, $leaf) = ($1, $2);
    die "parent '$parent' of pool '$pool' does not exist\n"
        if !defined($usercfg->{pools}->{$parent});
    ...
}
```

Ou seja:

```
/pool/empresa-a
/pool/empresa-a/producao
/pool/empresa-a/homologacao
```

### Roles customizadas são suportadas

`www/manager6/dc/RoleEdit.js:16` → `POST /access/roles` com lista de privilégios
arbitrária. O `pvePrivilegesSelector` carrega a lista real da API.

> Os **nomes** dos privilégios vêm do `pve-access-control`, fora deste repo —
> não foi possível enumerá-los aqui. Veja na tela de criação de role.

### Desenho proposto

- Um **realm** por empresa (PVE interno ou LDAP do cliente)
- Um **pool** por empresa, com sub-pools se quiser separar ambientes
- Admin da empresa recebe:
  - role de operação em `/pool/empresa-a`, com propagate
  - `User.Modify` em `/access/realm/empresa-a`
- Você mantém `/`

Como a ACL do PVE é **deny-by-default**, cada empresa enxerga só o que tem
permissão. Não vaza inventário entre tenants.

---

## 3. Bloqueio granular — nativo

| Alvo | Ação | Efeito |
|------|------|--------|
| Usuário | `enable=0` | Imediato (mecanismo do item 1) |
| Empresa inteira | Remover a ACL do grupo em `/pool/<empresa>` | Imediato, uma ação |

---

## 4. Quota de recursos — **não existe**

`PVE/API2/Pool.pm`, criação de pool:

```perl
properties => {
    poolid  => { type => 'string', format => 'pve-poolid' },
    comment => { type => 'string', optional => 1 },
},
```

**Apenas `poolid` e `comment`. Zero campos de quota.** O PVE não tem quota de
recurso por pool ou por tenant.

### O que dá para fazer

**Disco — quota real.** Storage dedicado por empresa (dataset ZFS, thin pool
LVM, pool Ceph) + ACL em `/storage/<id>`. O limite é imposto pelo storage, não
pelo PVE. Isso funciona de verdade.

**RAM e vCPU — só ponto de controle.** Negar os privilégios de
redimensionamento na role do tenant admin: ele opera as VMs mas não consegue
aumentar recursos, e quem dimensiona é você.

> A diferença importa: **não existe um número que o sistema recuse ultrapassar.
> Existe um pedido que passa por você.**

### Implicação comercial

Se o modelo for vender "empresa X tem 64 GB de RAM", o PVE não faz isso cumprir
sozinho. Dois caminhos:

1. **Controle manual do dimensionamento** — o tenant pede, vocês provisionam.
   Custo zero de desenvolvimento, custo operacional recorrente.
2. **Contabilidade construída no fork** — somar recursos por pool via API e
   mostrar consumido/contratado na própria UI. É viável, e cai bem no fork que
   já está sendo customizado.

O caminho 2 dá visibilidade e alerta, mas **ainda não é enforcement** a menos
que se adicione validação no caminho de criação/edição de VM.

---

## Referências no código

| Achado | Arquivo |
|--------|---------|
| `check_user_enabled` por requisição | `PVE/HTTPServer.pm:98` |
| Pools aninhados | `PVE/API2/Pool.pm` (validação pai/filho) |
| Ausência de quota | `PVE/API2/Pool.pm` (parâmetros de criação) |
| Paths de ACL | `www/manager6/data/PermPathStore.js:6-23` |
| Path livre no seletor | `www/manager6/form/PermPathSelector.js` |
| Roles customizadas | `www/manager6/dc/RoleEdit.js:16` |
| Tipos de ACL (user/group/token) | `www/manager6/dc/ACLView.js:203-231` |
