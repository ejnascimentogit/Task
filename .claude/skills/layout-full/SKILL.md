---
name: layout-full
description: Use esta skill sempre que criar, alterar ou revisar qualquer tela, componente visual ou página da família Full (Task Full, Full Commerce, Ótica Full / Full Ótica). Aplica o layout "v7" do Taskfull: faixa de resumo escura, cartões com cabeçalho colorido, linhas com faixa lateral, abas com contador, modal com banner, temas claro/escuro e a regra de nunca repetir o mesmo número na tela. Use também quando o Edimilson pedir "no estilo do Taskfull", "layout da família Full" ou mandar uma imagem de referência para adaptar.
---

# Layout da família Full (v7)

Linguagem visual única para **Task Full**, **Full Commerce** e **Ótica Full** (nome ainda não decidido: Ótica Full ou Full Ótica). A fonte de verdade do código é o `index.html` do Taskfull (`ejnascimentogit/Task`); esta skill descreve o que copiar e por quê. Em outro repositório, copie esta pasta para `.claude/skills/layout-full/`.

## Como trabalhar (processo combinado com o Edimilson)

1. **Imagem de proposta antes de mexer numa tela nova** (HTML solto com dados inventados, screenshot, mostrar). Só aplicar depois do "pode aplicar". Quando ele manda uma imagem de referência, ela já é a proposta: aplicar e mostrar o resultado.
2. **Só incluir:** não remover comportamento existente sem pedido. Layout é só marcação e estilo; dados e ações ficam iguais.
3. **Nenhum número aparece duas vezes na mesma tela.** Se o cartão do topo já mostra "tarefas abertas", a faixa não repete.
4. **Nunca cor fixa para tema:** usar as variáveis (abaixo). Cores fixas só em dados (etapas, raias, categorias, saúde) e na Lâmina.
5. Dados de teste **inventados**, nunca reais; prints para o material de venda também.
6. Testar no navegador (Playwright + Chromium, rede bloqueada: usar dados simulados) em **desktop escuro, desktop claro e celular (390 px)**, e conferir que não há erro de JavaScript.
7. Cada mudança registrada em CLAUDE.md do projeto (uma linha com função/classe).

## Tokens (variáveis CSS)

```css
:root {
  --navy:#021F33; --green:#00FF7A; --white:#FFFFFF; --page-bg:#F4F5F3; --light-bg:#F4F5F3;
  --border-light:#E5E7EB; --text-main:#1a1a1a; --gray-text:#5F6673; --on-navy:#FFFFFF;
  --red:#DC2626; --amber:#F59E0B;
  --accent-ink:#067A45;                /* verde legível sobre claro; no escuro vira var(--green) */
  --font-display:'Bricolage Grotesque','Inter',system-ui,sans-serif;  /* títulos */
  --radius-md:14px; --radius-lg:18px;
  --shadow-soft:0 1px 2px rgba(2,31,51,.05),0 8px 24px rgba(2,31,51,.06);
  --tipo-1:#1F6FA8; --tipo-2:#6B46C1; --tipo-3:#B4560F; --tipo-4:#0B7F58; --tipo-5:#B0316B; --tipo-6:#4D6B00; /* 6 cores de categoria; versão clara para o escuro em [data-theme="dark"] */
}
```
- Cada produto pode trocar só `--navy` e `--green` (marca) e a lista `--tipo-N`; **estrutura e componentes não mudam**. No Taskfull o usuário também escolhe tema no Estúdio de Temas, que reescreve essas variáveis.
- Texto de corpo: Inter. Títulos de tela: `h2.view-titulo` (Bricolage, ~34 px, 800). Rótulos de número: 10,5 px maiúsculas, `letter-spacing:.05em`.
- Escuro: `:root[data-theme="dark"]` e `@media (prefers-color-scheme: dark)` com `:root:not([data-theme="light"])`. Todo componente novo precisa ficar legível nos dois.

## Componentes

### 1. Faixa de resumo (`.faixa-resumo`)
Barra escura no topo da tela: 2 a 4 números grandes (24 px), uma barra segmentada e uma legenda com contagem. Primeiro número em verde (`.dest`), números ruins em vermelho-claro (`.alerta`).
```html
<div class="faixa-resumo">
  <div class="fr-k dest"><b>12</b><span>Hoje</span></div>
  <div class="fr-k alerta"><b>3</b><span>Atrasados</span></div>
  <div class="fr-barra"><i style="flex:5;background:var(--tipo-1)"></i><i style="flex:2;background:var(--tipo-2)"></i></div>
  <div class="fr-leg"><span><i style="background:var(--tipo-1)"></i>Reunião <b>5</b></span></div>
</div>
```
CSS essencial: `display:grid; grid-template-columns:repeat(auto-fit,minmax(120px,1fr)); border-radius:18px; color:#fff; background: linear-gradient(135deg, rgba(255,255,255,.07), transparent), var(--navy)`; `.fr-barra{display:flex;height:7px;border-radius:999px;overflow:hidden}`. Variante `.unica` com `.fr-cartoes` (um cartão por coluna do quadro) quando a faixa substitui um bloco inteiro.
Regra: a barra mostra **a distribuição do que o usuário já filtrou**; a legenda traz a contagem (os números só aqui).

### 2. Linha de lista com faixa lateral
Tabela/lista com cada linha como cartão (`box-shadow: var(--shadow-soft)`, raio 14) e **faixa lateral de 4–5 px na cor da categoria**: `td:first-child { box-shadow: inset 4px 0 0 var(--e) }` com `--e` definido na linha (`style="--e:cor"`). Mais: avatar redondo de 30 px com a inicial e borda na mesma cor; etiqueta em pílula (`border-radius:99px`); valor/hora em destaque (800, tabular).

### 3. Cartão com cabeçalho colorido (`.bk-card`)
Para grupos (pessoa, cliente, loja, laboratório, categoria):
- Cabeçalho em degradê `linear-gradient(135deg, cor, color-mix(in srgb, cor 62%, #000))` com avatar, nome, subtítulo e pílula "N% do total".
- Corpo: **anel** (`conic-gradient`) com o total no centro + lista de faixas com bolinha colorida; 3 mini-números (`.bk-st`); selo de estado (`✓ tudo certo` verde, `⚠ N atrasados` vermelho, `⏸ aguardando` âmbar).
- Grade `repeat(3, minmax(0,1fr))` → 2 colunas até 1100 px → 1 coluna até 700 px.

### 4. Abas com contador (`.view-toggle` + `.bk-n`)
Uma tela longa vira abas ("Visão geral", "Por pessoa", "Por cliente", "Por urgência"), cada uma com **contador** em pílula. O usuário troca de aba em vez de rolar a página. Abas que não fazem sentido para o perfil **não aparecem** (ex.: "Por pessoa" para quem não tem equipe).

### 5. Modal com banner
Cabeçalho que sangra para fora do padding (`margin:-28px -28px 20px`) com cor pela situação (verde/laranja/vermelho, neutro se o dado não existe), avatar com inicial, título, subtítulo "Editar cadastro · #código · etapa" e selo à direita. Atualiza ao mudar o campo que dá a cor.

### 6. Barra de período
`Tudo | Semana | Mês | Ano` + setas ◀ ▶ + "Hoje" + seletor de data. Padrão **Tudo** (não esconder nada sem o usuário escolher). Semana de domingo a sábado.

### 7. Detalhes que dão a cara
- **Largura:** conteúdo até 2200 px (`main`/`.topbar`); quadros dividem o espaço (`grid-auto-columns: minmax(250px,1fr)`).
- **Barras de rolagem finas:** `scrollbar-width:thin; scrollbar-color: rgba(128,140,155,.38) transparent;` e `::-webkit-scrollbar{width:6px}` com thumb arredondado, sem setas.
- **Altura:** o quadro ocupa só o que sobra na tela e rola por dentro; listas largas com `max-height: calc(100dvh - 280px)`.
- **Celular (≤ 860 px):** barra de abas fixa embaixo, modais como folha de baixo, campos de 16 px (evita zoom no iPhone), `env(safe-area-inset-*)`.
- Estado vazio sempre com ícone + frase ("Nada por aqui"). Botão principal verde (`--green`, texto `--navy`).

## Como cada produto usa

| Produto | Faixa de resumo | Cartões de grupo | Abas de Backlog/Indicadores |
|---|---|---|---|
| **Task Full** | atividades, agenda, e-mails, recibos, clientes | pessoa, cliente/projeto, urgência | idade, fluxo, por pessoa/cliente/urgência |
| **Full Commerce** | pedidos de hoje, a enviar, atrasados + barra por status do pedido (pago, separando, enviado, entregue) | por categoria, por canal (loja, app), por transportadora | visão geral (idade do pedido em aberto), por status, por canal; valor e ticket médio nos mini-números |
| **Ótica Full** (ou Full Ótica) | ordens de serviço de hoje, prontas para retirar, atrasadas no laboratório + barra por etapa (armação, lente, montagem, pronto) | por laboratório, por vendedor, por loja | idade da OS, prazo de entrega prometido, por laboratório; recibos e receitas como linhas com faixa lateral |

Cores de status: verde = em dia, amarelo/laranja = atenção, vermelho = atrasado, cinza = interno/sem classificação; o resto usa `--tipo-N`. Em Full Commerce e Ótica Full, valores em R$ sempre com `toLocaleString('pt-BR',{style:'currency',currency:'BRL'})` e `font-variant-numeric: tabular-nums`.

## Armadilhas já vividas (não repetir)
- **Imagem exportada (html2canvas):** `color-mix()` e `color()` quebram ("unsupported color function"). Em HTML que vira imagem/PDF, calcular as cores em JavaScript. Texto pode sair embaralhado no celular: desenhar pelo navegador (SVG com `foreignObject` → canvas) e deixar html2canvas só de reserva.
- **Grade de 12 colunas (Indicadores):** bloco novo cai numa coluna estreita; dar `grid-column: 1 / -1`.
- **Cache do app instalado:** depois de publicar, o celular pode manter a versão antiga; abrir e fechar o app duas vezes (o service worker busca sempre da rede).
- **Dois `index.html`:** `index.html` e `deploy/public/index.html` mudam juntos (script Python com `assert s.count(old)==1`; `node --check` do maior `<script>`; `diff` vazio).
- **Tema escuro:** cores de texto de selo (`#B45309`, `#15803D`...) precisam de versão clara no escuro (regras `:root[data-theme="dark"]`).
- **Sem repetir número:** faixa e cartões do topo não podem mostrar o mesmo total.

## Checklist antes de entregar
- [ ] Usa só variáveis de tema (e `--tipo-N`/cores de dado); nada de cor fixa em fundo ou texto.
- [ ] Legível em escuro, claro e celular de 390 px; sem rolagem horizontal da página.
- [ ] Nenhum número repetido; abas só quando a tela ficaria longa.
- [ ] Dados de teste inventados; sem erro no console.
- [ ] Dois `index.html` iguais; CLAUDE.md atualizado; commit com o trailer combinado.
