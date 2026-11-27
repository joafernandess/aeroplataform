# UI Research — Brief de design (preto / branco / azul)

> Público: engenheiro de UI. Tudo aqui é construível com primitivas Roblox (Frame, TextLabel, TextButton,
> UICorner, UIStroke, UIGradient, UIScale, UIListLayout, UIGridLayout, UIPadding) em
> `Client/UI/Theme.luau` e `Client/UI/Components.luau`. Medidas em px na resolução de design **1280x720**
> (o `UIController` já aplica `UIScale` — ver §9).

---

## 1. Fontes e referências

**Buscados nesta pesquisa (WebSearch, só resumos de resultados; nenhuma página aberta por completo):**
- Roblox Docs, UI/UX design: https://create.roblox.com/docs/production/game-design/ui-ux-design — botões de simulador
  "em contêiner colorido, destacado do fundo, com highlight/sombra"; títulos maiores e mais grossos que o corpo;
  UIStroke em texto = contorno do glifo, em Frame = borda.
- DevForum, guias de UI: https://devforum.roblox.com/t/3074034 , https://devforum.roblox.com/t/ui-design-guide/2975811 ,
  https://devforum.roblox.com/t/the-guide-to-ui-designing/606984 — stroke dá definição aos botões; poucas famílias de fonte;
  paleta única.
- DevForum, fontes cartoon: https://devforum.roblox.com/t/what-is-a-good-roblox-font-to-use-for-a-cartoony-style-game/2320642 ,
  https://devforum.roblox.com/t/cartoon-style-ui-review/3617988 — FredokaOne + stroke grosso para visual "playful";
  `Enum.Font.FredokaOne` e `Enum.Font.LuckiestGuy` confirmados na lista.
- Safe area / mobile: https://create.roblox.com/docs/reference/engine/enums/ScreenInsets ,
  https://devforum.roblox.com/t/the-correct-way-to-design-mobile-buttons/2494558 ,
  https://support.google.com/accessibility/android/answer/7101858 (alvo de toque ≥ 48dp, 8dp de espaço).
- Convenções de inventário / summon (guias de jogadores): https://gamertweak.com/equip-best-pets-pet-simulator-99 ,
  https://www.theclick.gg/?p=96677 (PS99: linha "Pinned", categorias recolhíveis),
  https://allthings.how/how-to-play-anime-stars-on-roblox-core-loop-and-progression/ (auto-sell por raridade; botões
  One/Multi/Auto; % de drop visível), https://www.sportskeeda.com/esports/how-level-quickly-roblox-anime-fighters-simulator
  (capacidade de inventário limitada, ampliada por upgrades).
- Kits de UI de terceiros (só para confirmar que o padrão é genérico, **não usar como referência visual**):
  https://builtbybit.com/resources/anime-simulator-ui-kit.109252/ , https://builtbybit.com/resources/anime-units-ui.112235/

**Falharam (proxy / DNS bloqueado):** `create.roblox.com` (WebFetch) e `animefighterssimulator.fandom.com`.
Para buscar screenshots, esses hosts precisam ser liberados nas configurações de rede da sessão.

**De memória (marcado como [M] no texto):** observações visuais de Anime Fighters Simulator, Anime Champions
Simulator, Pet Simulator X/99, Anime Defenders, Anime Dimensions, Bee Swarm, Blox Fruits, Arm Wrestle Simulator.
Confiança média: valide com screenshots próprias antes de decisões finas. Nenhuma medida deste doc foi copiada
de um jogo; todas são nossas.

---

## 2. Princípios do gênero (convenções comuns, livres para uso)

1. **Legibilidade sobre cenário 3D poluído:** todo texto com contorno escuro grosso; painéis opacos; nada de texto fino.
2. **Centro da tela livre:** HUD ancorado nas bordas (moedas à esquerda/topo, menu lateral, ações à direita/baixo).
3. **Números grandes e abreviados:** 1.2K, 3.4M, 5.6B, 7.8T, 1.2Qa, 3.4Qi, Sx, Sp, Oc, No, Dc.
4. **Um toque = uma ação:** "Equipar melhores", "Abrir x3", toggles de auto-venda; confirmações só no que é destrutivo.
5. **"Juice" em toda recompensa:** pop de escala, brilho, números flutuantes, moedas voando ao HUD, contador animado.
6. **Raridade codificada por cor + texto + estrelas** (nunca só cor).
7. **Botões "chunky" 3D:** gradiente vertical, borda escura, "lábio" inferior mais escuro que afunda ao pressionar.
8. **Uma janela por vez,** centralizada, com X redondo no canto; ESC/clique fora fecha.
9. **Consistência > variedade:** mesma família de botões, raios e strokes em tudo; ícones monocromáticos padronizados.

---

## 3. Tokens de design

### 3.1 Cores (hex)
Pretos levemente azulados contam como "preto" e harmonizam com o azul.

| Token | Hex | Uso |
|---|---|---|
| `Ink` | `#05070D` | contorno de texto, bordas (UIStroke), sombra |
| `Bg` | `#080C16` | fundo de HUD/overlays; scrim modal (`Ink` @ 0.45 transp.) |
| `Panel` | `#0E1424` | corpo de janela (base) |
| `PanelAlt` | `#16203A` | poços internos, cards, células |
| `PanelLight` | `#1F2C4F` | hover de item, toolbar, tab inativa |
| `Line` | `#2A3A66` | divisores, rim interno (1.5px) |
| `White` | `#FFFFFF` | texto principal, botão secundário, ícones |
| `TextDim` | `#A9B8D9` | legendas, texto secundário |
| `TextMuted` | `#6B7BA3` | desabilitado, placeholder |
| `Blue900` | `#0A2A6B` | lábio do botão primário, fundo de header (base) |
| `Blue700` | `#1546B8` | botão "dark blue", base de gradiente |
| `Blue500` | `#1E6BFF` | **cor primária** (CTA, seleção, toggles ON) |
| `Blue400` | `#4A95FF` | topo do gradiente primário, hover |
| `Cyan` | `#4FD2FF` | acento/energia: destaque, crit, sucesso, item NOVO |
| `Ice` | `#CFEFFF` | brilhos, fundo de alerta "cheio", fundo do botão branco (base) |

**Estados dentro da paleta (sem verde/vermelho):**
- Positivo/sucesso = `Cyan` (toast, "+XP", toggle ON usa `Blue500`).
- Aviso (inventário cheio, sem moeda) = fundo `Ice` + texto `Ink` + glifo `!` pulsando.
- Erro/destrutivo = **invertido**: fundo `Ink`, stroke `White` 2.5px, texto branco; ação destrutiva exige 2 toques
  ("Vender" → "Confirmar? (3s)").
- `DangerOptional = #FF3B4E`: **desligado por padrão.** Só ativar se playtest mostrar que jogadores vendem por engano;
  usar apenas no botão de confirmação de venda/exclusão em massa. Justificativa: vermelho = "destrutivo" é convenção
  universal, mas o invertido preto/branco + confirmação já cobre o risco mantendo a paleta.
- Raridades (`Config/Rarities.luau`) continuam como **acento pequeno** só em cards/reveal/pool. Atenção: Rare
  (`#4696FF`) e Exclusive (`#00FFC8`) se parecem com Blue500/Cyan → sempre acompanhar de nome/estrelas.

### 3.2 Gradientes (UIGradient, `Rotation = 90`, `BackgroundColor3 = White` e cores reais no ColorSequence)
| Nome | Topo → Base | Lábio (Frame 4px abaixo) |
|---|---|---|
| Primary | `#4A95FF` → `#1652E0` | `#0A2A6B` |
| Accent (cyan) | `#8BE6FF` → `#22A9E8` | `#0B5E8A` |
| Secondary (branco) | `#FFFFFF` → `#C9DAFF` | `#6F86B8` |
| Dark | `#233257` → `#151F38` | `#070B16` |
| Danger (invertido) | `#1A1F2B` → `#05070D` | `#000000` |
| Disabled | `#3A4560` → `#2A3247` | nenhum |
| Window body | `#121A2E` → `#0A0F1C` | — |
| Window header | `#2A7BFF` → `#0E3A9E` | — |
| Progress fill | `#4FD2FF` → `#1E6BFF` (Rotation 0, esquerda→direita) | — |

Brilho ("gloss"): Frame filho cobrindo os 45% superiores, `White` @ 0.82 de transparência, mesmo UICorner.

### 3.3 Strokes, raios, espaçamento, tamanhos de texto
- **Strokes de borda (Border):** janela 4 · botão 3 · card 3 · toolbar/ícone 3 · badge pequeno 2 · rim interno 1.5 (`Line`).
- **Contorno de texto (Contextual, `Ink`):** display ≥30px → 3 · título/botão 20–28px → 2.5 · 15–19px → 2 · ≤14px → 1.5.
  `LineJoinMode = Round`. Não usar `TextStrokeTransparency` (1px, fraco) em texto novo.
- **Raios:** janela 18 · header 14 · botão 12 · card 12 · toolbar 10 · toast 12 · badges/pílulas/barras `UDim.new(0.5,0)`.
- **Espaçamento (escala de 4):** 4 · 8 · 12 · 16 · 24 · 32. Padding de janela 16; gap de grid 10; gap de HUD 8.
- **Texto (design 1280x720):** Display 34 · H2 24 · botão grande 24 · botão 20 · corpo 18 · pequeno 15 · micro 13
  (mínimo absoluto 12, só em card). Números de HUD 24.

### 3.4 Snippet sugerido para `Theme.luau`
```lua
local hex = Color3.fromHex
Theme.Colors = {
	Ink = hex("05070D"), Bg = hex("080C16"), Panel = hex("0E1424"), PanelAlt = hex("16203A"),
	PanelLight = hex("1F2C4F"), Line = hex("2A3A66"), White = hex("FFFFFF"), TextDim = hex("A9B8D9"),
	TextMuted = hex("6B7BA3"), Blue900 = hex("0A2A6B"), Blue700 = hex("1546B8"), Blue500 = hex("1E6BFF"),
	Blue400 = hex("4A95FF"), Cyan = hex("4FD2FF"), Ice = hex("CFEFFF"),
}
-- Mapeamento dos tokens atuais: Background→Bg, Stroke/Outline→Ink, Button→Blue700, Header→Blue500,
-- Cta→Blue500, Accent→Cyan, Good→Cyan, Bad→(Danger invertido), Info→Blue500, XP→Cyan, Crit→Cyan.
-- Theme.MenuColors: todos Primary, exceto Summon = Accent. Moedas: ver §6 (badge por tom de azul).
```

---

## 4. Tipografia (Enum.Font)

| Papel | Fonte | Uso | Contorno |
|---|---|---|---|
| Display | `LuckiestGuy` | títulos de janela, raridade no reveal, números de dano | 3 |
| UI | `FredokaOne` | botões, abas, legendas de ícone, nomes em card | 2–2.5 |
| Números | `BuilderSansExtraBold` (fallback `GothamBlack`) | contadores de moeda, %, "87/120", preços | 2 |
| Corpo | `BuilderSansBold` (fallback `GothamBold`) | descrições, stats, toasts | 1.5–2 |

- Máximo 3 famílias visíveis ao mesmo tempo. Títulos e números em CAIXA ALTA só no Display.
- `Gotham*` hoje é remapeado pelo Roblox (para Montserrat) [M]; preferir BuilderSans. Confirmar nomes no autocomplete do Studio.
- Glifos que a fonte não tem caem num fallback do sistema (peso diferente): testar cada ícone de §6.

---

## 5. Especificações de componentes

### 5.1 Botões (`C.Button(kind)`): sempre `AutoButtonColor = false` (estados manuais)
- Estrutura: `TextButton` (Text = "") → face (Frame com gradiente + gloss + UICorner 12 + UIStroke 3 `Ink`) sobre lábio
  (Frame da cor "Lábio", 4px mais baixo, mesmo raio) → `TextLabel` filho com contorno Contextual.
- Tamanhos: L 200x56 (texto 24) · M 160x48 (20) · S 120x40 (18) · mínimo de toque 44x44.
- Primary: gradiente Primary, texto `White` contorno 2.5. Secondary: gradiente branco, texto `#0B1A3A` sem contorno.
  Accent: gradiente cyan, texto branco contorno 2.5. Danger: invertido (§3.1) + confirmação em 2 toques.
- **Estados:** hover → `UIScale` 1.04 + face lerp 8% para branco (0.08s) · pressionado → face desce 3px (lábio some),
  `UIScale` 0.95 (0.06s) · disabled → gradiente Disabled, texto `TextMuted`, sem lábio, contorno 1.5 ·
  selecionado/toggle → stroke `Cyan` 3. Easing `Quad Out`.

### 5.2 Botão-ícone de menu (+ legenda)
- Quadrado arredondado ("squircle") 68x68, raio 20, gradiente Primary (Summon: Accent), stroke 3 `Ink`, lábio 4px.
- Glifo branco 32px FredokaOne contorno 2; legenda abaixo 14px FredokaOne, contorno 1.5, largura 84.
- Grade 2 colunas na lateral esquerda, centralizada verticalmente; gap 10. Badge de notificação: círculo 22px
  `White`, stroke 2 `Ink`, número `Blue500` 13px, canto superior direito (-6,-6). Summon "respira" (UIScale 1↔1.05, 1.2s).

### 5.3 Barra de moedas (HUD) com "+"
- Pílula 200x40 por moeda, empilhadas verticalmente (gap 8) abaixo da área do topbar (≥ 58px do topo), à esquerda.
- Corpo: `Panel` @ 0.1 transp., stroke 3 `Ink`, raio pílula. Badge do ícone: círculo 44px sobrepondo a borda esquerda
  (x = -6), fill por moeda (§6), stroke 3 `Ink`, glifo branco 22px.
- Valor: `BuilderSansExtraBold` 24, branco, contorno 2, alinhado à esquerda após o badge; contagem animada (0.4s).
- "+": círculo 30px dentro da extremidade direita (margem 5), gradiente Primary, "+" branco 22px FredokaOne contorno 2.
- Power: pílula maior 240x44, badge `Ink` com glifo `Cyan`.

### 5.4 Janela (`C.Window`)
- Corpo: gradiente Window body, raio 18, stroke 4 `Ink`, rim interno 1.5 `Line` (Frame inset 3px). Tamanho padrão 760x520;
  inventário/summon 860x560 (`UISizeConstraint` máx 960x640).
- Header 56px (dentro da janela, cantos superiores): gradiente Window header + **listras "speed-lines"**: 8 Frames
  2x120px, `White` @ 0.88, `Rotation = 25`, espaçadas 28px, no terço direito, header com `ClipsDescendants`.
  Linha de energia `Cyan` 3px na base do header.
- Ícone do título: quadrado 40x40 raio 10, fill `White`, glifo `Blue500` 24px, à esquerda (x 12).
- Título: `LuckiestGuy` 34, branco, contorno 3, alinhado à esquerda (x 62). **Sem inclinação, sem faixa amarela.**
- Fechar: círculo 44px gradiente Secondary, stroke 3 `Ink`, "✕" `Ink` 24px; centro em (largura-10, 10) sobrepondo o
  canto; hover gira 90° (0.12s). Scrim `Ink` @ 0.45 atrás da janela; clique no scrim fecha.
- Abrir: UIScale 0.85→1, 0.18s `Back Out`; fechar: 1→0.9 + fade, 0.12s `Quad In`.

### 5.5 Abas (segmented)
- Poço 44px de altura, `Bg`, stroke 3 `Ink`, raio 14, padding 4. Abas 136x36, raio 10.
- Ativa: gradiente Primary + texto branco contorno 2; inativa: transparente, texto `TextDim` sem contorno; hover → `PanelLight`.

### 5.6 Toolbar de filtro/ordenação
- Linha 44px. Botões-ícone 40x40, raio 10, `PanelLight`, stroke 3 `Ink`, glifo branco 20px; ativo = Primary + stroke `Cyan`.
- Ordem: [⇅ Ordenar] [≡ Filtro raridade] [cadeado: só travados] [✓ Modo seleção] … [Busca 220x40] … contadores à direita.
- Ordenar cicla (Poder → Raridade → Nível → Recentes) e mostra tooltip "Ordenar: Poder" 1.2s abaixo do botão.

### 5.7 Contadores de capacidade
- Pílula 120x34, `PanelAlt`, stroke 2.5 `Ink`; glifo 16px + "87/120" `BuilderSansExtraBold` 18.
- ≥ 90%: stroke `Cyan`. Cheio: fundo `Ice`, texto `Ink`, "!" pulsando (UIScale 1↔1.1, 0.6s) + toast ao tentar invocar.
- Dois contadores: Unidades (▦) e Equipados (✓ "3/5").

### 5.8 Card de unidade (100x124, grid `UIGridLayout` célula 100x124, gap 10)
- Base: `PanelAlt`, raio 12, stroke 3 `Ink`. Poço do retrato 84x76 em (8,8), gradiente `#1F2C4F`→`#0A0F1C`, raio 10
  (iniciais em `LuckiestGuy` 28 até existir arte; depois `ImageLabel`/`ViewportFrame`).
- **Raridade (acento):** faixa 84x5 na cor da raridade logo abaixo do retrato + contorno do nome na cor da raridade
  escurecida 40%. Não pintar o card inteiro com a raridade.
- Nível: "Lv 25" `FredokaOne` 13, contorno 1.5, canto superior esquerdo do retrato.
- Estrelas: "★★★" 12px `White` (máximo → `Cyan`), contorno 1.5, centralizadas na base do retrato.
- Nome: `BuilderSansBold` 13, branco, contorno 1.5, `TextTruncate.AtEnd`, área 92x20 na base.
- Equipado: círculo 26px em (largura-4, 4) sobrepondo o canto, gradiente Primary, stroke 2.5 `Ink`, "✓" branco 16.
- Travado: círculo 22px `Ink`, stroke 2 `White`, cadeado (primitivas, §6) no canto inferior esquerdo do retrato.
- Novo: pílula "NOVO" 40x16 `Cyan`, texto `Ink` 11, canto superior direito (some ao abrir o inventário).
- Selecionado (inspecionar): stroke `Cyan` 3 + UIScale 1.04. Marcado (fundir/vender): overlay `Blue500` @ 0.5 + "✓" 32px.
- Ordenação padrão: equipados primeiro, depois poder decrescente.

### 5.9 Rodapé de ações
- Faixa 64px, `Bg` @ 0.2, divisor `Line` 1.5 no topo. Botões M 160x48, gap 12, à direita:
  [Equipar melhores — Primary] [Desequipar todos — Secondary] [Vender selecionados — Danger]; à esquerda: [Fundir — Accent]
  só no modo seleção.

### 5.10 Janela de Summon
- Esquerda (≈ 60%): grade de pool, cards 112x140 (mesmo estilo de §5.8), com **% grande** `BuilderSansExtraBold` 20
  sob o retrato ("12.5%"). Raridade marcada para auto-venda: card @ 0.5 de opacidade + etiqueta "AUTO" `Ink`/branco.
- Direita (≈ 40%): nome do banner (`LuckiestGuy` 28), preço com glifo da moeda, botões L empilhados:
  "ABRIR x1" (Secondary) e "ABRIR x3" (Primary); opcional "AUTO" (toggle pílula, §5.14).
  Linha 2 do botão: preço `BuilderSansExtraBold` 16.
- Auto-venda: lista de chips 200x34 por raridade: checkbox 26x26 (OFF `PanelAlt` + stroke 2.5 `Ink`; ON `Blue500` + "✓"),
  bolinha 12px na cor da raridade, nome `FredokaOne` 16.
- Sem moeda suficiente: botão vira Disabled + legenda "Faltam 1.2K ¥".

### 5.11 Reveal (resultado)
- Scrim `Ink` @ 0.35; container central 640x300 sem moldura pesada; atrás, "estouro" de speed-lines: 16 Frames
  4x400 `White` @ 0.85 girando lentamente (Rotation +30°/s).
- Cards 120x150 aparecem em sequência: UIScale 0→1.15→1 (0.25s `Back Out`), intervalo 0.12s.
- Raridade em `LuckiestGuy` 26 na cor da raridade, contorno 3 `Ink`. ≥ Legendary: flash branco tela cheia 0.15s + leve
  tremor (Position ±4px, 0.2s). Vendido automaticamente: card @ 0.5 + fita "VENDIDO" `Ink` rotacionada -12°.
- Botões: "OK" (Secondary M) e "ABRIR DE NOVO" (Primary M). Toque em qualquer lugar acelera a animação.

### 5.12 Toast / notificação
- 360x52, topo-centro (y = 70) empilhando para baixo, máx. 3; `Panel`, stroke 3 `Ink`, raio 12.
- Barra lateral 6px: Info `Blue500` · Sucesso `Cyan` · Aviso `White` · Erro `Ink` com stroke branco.
- Ícone em círculo 32px + texto `BuilderSansBold` 18 contorno 1.5. Entra deslizando de cima 0.2s, vive 3s, sai 0.2s.
  Mensagens iguais se fundem ("… x3").

### 5.13 Barra de progresso (XP, quest, upgrade)
- Altura 18, raio pílula, fundo `Ink`, stroke 2.5 `Ink`. Fill: gradiente Progress fill + gloss (40% superior).
- Legenda central `FredokaOne` 14 contorno 1.5 ("1.2K / 5K XP"). Animar o fill (0.25s `Quad Out`).

### 5.14 Toggle (configurações)
- Pílula 64x32, stroke 3 `Ink`; OFF fundo `PanelAlt`, botão branco 24px à esquerda; ON fundo `Blue500`, botão à direita
  (tween 0.12s). Linha de configuração 48px: rótulo `FredokaOne` 18 à esquerda, toggle à direita.

### 5.15 Barra de vida do inimigo (BillboardGui)
- `Size = UDim2.fromOffset(170, 40)`, `StudsOffset` acima da cabeça, `MaxDistance` 80, `LightInfluence = 0`.
- Nome `FredokaOne` 14, branco, contorno 1.5. Barra 160x14, raio pílula, fundo `Ink` @ 0.15, stroke 2 `Ink`.
- **Fill do inimigo em BRANCO** (`#FFFFFF`→`#BFD6FF`) — azul fica reservado ao que é do jogador. "Rastro de dano" em
  `Cyan` que desce até o valor atual após 0.3s. Texto de HP opcional `BuilderSansExtraBold` 11.
- Boss: barra topo-centro 520x26, nome `LuckiestGuy` 22 acima, mesmas cores.

### 5.16 Números de dano
- BillboardGui 120x50, `AlwaysOnTop = true`, `LuckiestGuy` 30, contorno 3 `Ink`.
- Normal (fighters) `White` · clique do jogador `Ice` · crítico `Cyan` 42px com "!" · cura/ganho "+".
- Animação: escala 0.6→1.2 (0.08s) →1 (0.1s); sobe ~1.5 studs em 0.7s; fade nos últimos 0.3s; desvio X aleatório ±20px.
  Abreviar (§2). Pool de instâncias, máx. ~30 simultâneos.

---

## 6. Ícones (glifos monocromáticos que respeitam `TextColor3`)
Emoji coloridos (💎🪙🎒🛒) **ignoram TextColor3** e quebram a paleta — substituir pelos glifos abaixo. Alguns símbolos
podem virar emoji conforme plataforma (marcado ⚠): testar em PC, iOS e Android.

| Função | Glifo | Badge/cor | Futuro ImageLabel? |
|---|---|---|---|
| Yen | `¥` | badge `Blue500` | baixa |
| Gems | `◆` | badge `Cyan` | baixa |
| Gold | `●` | badge `White` + glifo `Ink` | média |
| Tokens | `✦` | badge `Blue900` | baixa |
| Power | `✸` | badge `Ink` + glifo `Cyan` | baixa |
| Inventário | `▦` | — | média |
| Summon | `✪` | — | média |
| Mundos | `◎` | — | média |
| Quests | `☰` | — | baixa |
| Loja | `$` | — | baixa |
| Upgrades | `▲` | — | baixa |
| Raids | `⚔` ⚠ (fallback `✕`) | — | **alta** |
| Config. | `⚙` ⚠ (fallback `≡`) | — | **alta** |
| Auto-ataque | `↻` | — | baixa |
| Equipado | `✓` | — | baixa |
| Estrela | `★` | — | baixa |
| Fechar | `✕` | — | baixa |
| Ordenar / Filtro | `⇅` / `≡` | — | baixa |
| Fundir | `✚` | — | baixa |
| Voltar / Avançar | `◄` / `►` | — | baixa |
| Cadeado | primitivas: corpo Frame 12x9 raio 2 + alça Frame 10x10 só stroke 2 (metade inferior escondida pelo corpo) | — | **alta** |

Quando houver assets: ícones de menu, moedas e cadeado viram `ImageLabel` brancos (cor via `ImageColor3`) mantendo
os mesmos badges/tamanhos; arte de retrato em `ImageLabel` ou `ViewportFrame` dentro do poço do card.

---

## 7. Layout do HUD (1280x720)
- Topo-esquerdo: reservado ao topbar do Roblox (58px). Moedas: coluna em x 16, y 70.
- Esquerda-centro: grade 2x4 de botões de menu (§5.2).
- Direita-centro: tracker de quest (painel 260px, `Panel` @ 0.15) e botões de ação (AUTO 72px).
- Baixo-direita: **livre** (botão de pulo no mobile). Baixo-centro: barra de XP 420x18 + nível.
- Topo-centro: toasts e barra de boss.
- `ScreenInsets = CoreUISafeInsets`; nada interativo a menos de 16px das bordas.

---

## 8. Convenções genéricas vs. elementos a NÃO copiar

**(a) Genéricas — ok (aparecem em dezenas de simuladores):** texto cartoon com contorno grosso; botões com gradiente,
borda escura e lábio 3D; botões-ícone laterais com legenda; pílulas de moeda com badge e "+"; grade de inventário com
cards por raridade, check de equipado, cadeado, "X/Y", Equipar melhores/Desequipar todos; summon com pool e %,
x1/x3, auto-venda por raridade; reveal com pop em sequência; números de dano flutuantes abreviados; toasts; barra de
boss no topo; X redondo no canto da janela; abas; toggles pílula.

**(b) Marcas registradas — NÃO copiar:**
- **Anime Fighters Simulator:** logotipo/wordmark; o header **amarelo/laranja inclinado** de "Your Fighters" e a fileira
  específica de ícones dentro dele; proporções e posições exatas das janelas e da barra lateral; arte dos ícones,
  da moeda Yen e das "stars"/orbes de summon do mundo; sons; textos e nomes de UI idênticos. [M] O nome de moeda "Yen"
  também é usado por ele — é genérico em jogos de anime (risco baixo), mas nosso ícone/badge deve ser próprio.
- **Pet Simulator X/99:** o visual claro azul-claro/branco "bolha" com a sua iconografia de diamantes/moedas e
  layout de inventário de pets [M]. Como nossa paleta também é azul/branco, **diferenciar indo para o escuro**
  (painéis pretos, acentos cyan, speed-lines), não para o claro.
- **Anime Champions / Anime Defenders / Anime Dimensions:** molduras específicas de card de unidade, banners de
  summon com arte própria, logos [M].
- **Bee Swarm Simulator:** inventário/ícones hexagonais em favo, tema amarelo-preto [M] — não usar grade hexagonal.
- **Blox Fruits:** ícones pincelados, layout de stats/fruta, arte de frutas [M].
- **Arm Wrestle Simulator:** seu layout de HUD/treino específico [M].
- Geral: nada de traçar screenshots, reusar ícones/fontes customizadas ou nomes/arte de personagens de animes reais.

**Assinaturas próprias (usar sempre, para identidade):** header azul reto com speed-lines + linha de energia cyan;
painéis quase pretos com rim interno `Line`; fill de vida do inimigo em branco vs. tudo do jogador em azul;
botão destrutivo invertido (preto + stroke branco); card com faixa de raridade fina (não card inteiro colorido).

---

## 9. Do / Don't

**Do**
- Usar só tokens de §3 (nunca `Color3.fromRGB` solto em controllers).
- `AutoButtonColor = false` + estados manuais (§5.1); todo botão com lábio e contorno de texto.
- Texto via `TextLabel` filho com `UIStroke` Contextual (não misturar com o stroke de borda no mesmo objeto).
- Manter o `UIController` atual (design 1280x720, `HUD_BOOST` 1.2); subir `MIN_SCALE` de janela para ~0.55 e,
  se a janela não couber, reduzir colunas da grade (rolagem) em vez de encolher abaixo disso.
- Alvos de toque ≥ 44px no design e ≥ 8px de espaço; testar no emulador (iPhone SE paisagem, tablet, 1080p).
- Confirmar em 2 toques toda venda/exclusão em massa; mostrar % de drop no summon.
- Verificar no Studio se `UIStroke.Thickness` acompanha o `UIScale`; se não, multiplicar pela escala atual.
- Animar com TweenService curto (0.06–0.25s); respeitar uma janela aberta por vez.

**Don't**
- Não usar verde/vermelho/amarelo/roxo na UI base (só raridades, só nos cards/reveal/pool).
- Não usar emoji colorido como ícone definitivo; não usar `TextStrokeTransparency` como contorno principal.
- Não usar header inclinado amarelo, faixa de título em fita diagonal nem fileira de ícones no header (evita AFS).
- Não usar grade hexagonal, tema claro "bolha" azul-claro, nem logos/ícones de qualquer jogo citado.
- Não colocar UI interativa sob o topbar do Roblox nem sob o botão de pulo.
- Não depender só da cor para raridade, estado ou erro (sempre texto/ícone junto).
- Não passar de 3 famílias de fonte nem de 6 tamanhos de texto por tela.
