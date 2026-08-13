# Personalização Blue3 — o que mudou e por quê

**Implementado em:** 13/08/2026 · **Base:** pve-manager 9.2.10

---

## Princípio

Toda alteração aqui vai conflitar num rebase futuro. Por isso:

1. **Arquivo novo > patch em arquivo existente.**
2. **Arquivos do upstream ficam intactos** — só as referências mudam.
3. **Onde comportamento do upstream foi removido, fica um comentário** dizendo o
   que havia ali. Sem isso o conflito de rebase vira enigma.

---

## Assets

Fonte: `blue3-logos/` na raiz. Copiados para `www/images/` com prefixo `blue3-`:

| Arquivo | Origem | Uso |
|---------|--------|-----|
| `blue3-logo.png` | `blue3.png` (220×65) | Wordmark do cabeçalho |
| `blue3-icon-128.png` | `favicon-128.png` | Favicon |
| `blue3-icon-196.png` | `favicon-196x196.png` | Favicon HiDPI, apple-touch-icon |
| `blue3-favicon.ico` | `favicon.ico` | Favicon legado |

Registrados em `www/images/Makefile`. **`logo-128.png`, `proxmox_logo.png` e
`favicon.ico` do upstream foram deixados no lugar** — não são mais
referenciados, mas remover arquivo do upstream cria conflito sem ganho.

> `blue3-logos/` tem 33 MB e a maior parte é um template admin AngularJS sem
> relação com PVE (ckeditor, jquery, gulp). Candidato a limpeza ou `.gitignore`.

---

## Paleta

Extraída do próprio logo com `magick ... histogram:`:

| Cor | Hex | Papel |
|-----|-----|-------|
| Ciano | `#29ABE2` | Acento primário |
| Azul | `#0071BC` | Acento profundo — headers, botões |
| Cinza | `#A1A0A0` | Neutro da marca |

Vivem em **`www/css/blue3.css`**, arquivo novo, carregado por último no
`index.html.tpl` — depois do `ext6-pve.css` **e** do tema — para vencer por
cascata.

### O que foi deliberadamente deixado de fora

Seleção e hover de grid/tree **não** foram recoloridos. Essas cores diferem
entre o tema `crisp` e o `proxmox-dark`, e uma regra única num arquivo só
quebraria um dos dois. Só acentos de marca — que funcionam sobre qualquer fundo
— foram tocados.

---

## Arquivos alterados

| Arquivo | Mudança |
|---------|---------|
| `www/index.html.tpl` | Título, favicons, link do `blue3.css` |
| `www/manager6/Workspace.js` | Título, logo do cabeçalho, texto de versão, botão de docs, cor do botão de usuário, remoção do nag |
| `www/manager6/window/LoginWindow.js` | Título da janela, mensagem de falha de conexão |
| `www/manager6/Utils.js` | URLs Blue3, `noSubKeyHtml` |
| `www/manager6/dc/Support.js` | Textos e links de suporte |
| `www/manager6/dc/Summary.js` | Link do widget de subscription |
| `www/manager6/node/StatusView.js` | `product: 'Blue3 Cloud'` |
| `www/manager6/node/Summary.js` | Remoção do nag em "Package versions" |
| `www/images/Makefile`, `www/css/Makefile` | Registro dos arquivos novos |

---

## Decisões que precisam de contexto

### Logo do cabeçalho virou `<img>`

O upstream usa `xtype: 'proxmoxLogoSvg'`, componente que vive no
**proxmox-widget-toolkit** — pacote separado, que não dá para rebrandear a
partir daqui. Por isso virou um `box` com `<img>` apontando para
`/pve2/images/blue3-logo.png`.

> Segurança: a string do `html:` é **estática e literal**, por isso é segura.
> Se um dia esse conteúdo vier de configuração ou API, precisa ser escapado —
> `html:` não escapa nada.

### Botão "Documentation" virou botão comum

O `proxmoxHelpButton` sempre resolve para o `pve-docs` instalado localmente.
Virou `button` com `window.open(PVE.Utils.blue3DocsURL)`.

### URLs centralizadas

`PVE.Utils.blue3SiteURL`, `blue3DocsURL`, `blue3SupportURL` em `Utils.js`.
**Exceção:** `noSubKeyHtml` está no mesmo object literal e não pode
auto-referenciar, então tem a URL hardcoded — é a única duplicação.

### Nag de subscription removido em dois pontos

`Workspace.js` (pós-login) e `node/Summary.js` ("Package versions"). Ambos
tinham `Proxmox.Utils.checked_command()`. Um terceiro uso em
`node/Subscription.js` foi **mantido** — ali é o botão "Check" da própria tela
de subscription, onde o comportamento é legítimo.

---

## Pendências

| Item | Situação |
|------|----------|
| Domínio dos links | `Utils.js` aponta para `blue3.com.br`, mas o deploy é `blue3.cloud`. **As URLs foram inventadas como placeholder e nunca confirmadas.** |
| Botões de ajuda por painel | 156 arquivos usam `onlineHelp:`; redirecionar exige a API de help do widget-toolkit, ausente neste checkout |
| Lint | `proxmox-biome` não instalado — validação possível foi `node --check` nos 7 arquivos alterados (passou) |
| `blue3-logos/` | 33 MB, maior parte irrelevante |

---

## Como validar

```bash
node --check www/manager6/Workspace.js
make -C www/images install DESTDIR=/tmp/test
make -C www/css   install DESTDIR=/tmp/test
find /tmp/test -name 'blue3-*'
```
