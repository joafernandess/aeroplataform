# Ícones — conjunto próprio (preto / branco / azul)

> **Menus do HUD:** os 13 ícones dos menus (Shop, Fighters, Settings, Codes, Quests, TP, Inventory, Mounts,
> Upgrades, Stats, Index, Update Log, Yen) agora são PNGs 512×512 minimalistas e chapados em `assets/UI_Icons/` — ver
> `assets/UI_Icons/README.md` para o mapeamento e o upload. Os IDs vão em `Client/UI/IconAssets.luau`.
> Os ícones vetoriais do código (`Client/UI/Icons.luau`) também são chapados (sem contorno; `Bordered = true` volta
> o contorno antigo onde precisar).
> Este documento descreve o conjunto antigo (moedas, ferramentas e detalhes das janelas, `assets/icons/`).

Substitui os glifos Unicode de `Theme.Icons` por imagens. Arte 100% original (nada traçado ou copiado de Anime
Fighters Simulator nem de outro jogo — ver §8 de `docs/ui/UI_RESEARCH.md`).

| Caminho | Conteúdo |
|---|---|
| `assets/icons/svg/<nome>.svg` | fonte vetorial escrita à mão (editar aqui) |
| `assets/icons/png/<nome>.png` | exportação 256x256, fundo transparente (é o que sobe para o Roblox) |
| `assets/icons/contact-sheet.png` | todos os ícones a 64 px sobre `Panel` e sobre botão `Blue500`, + linha a 32 px |
| `assets/icons/manifest.json` | `nome -> { png, rbxassetid }` (ids preenchidos depois do upload) |
| `assets/icons/tools/export.js` | exportador (Playwright/Chromium): PNGs, contact sheet, manifest e validação de paleta |

---

## 1. Regras de estilo

- **Grade:** `viewBox="0 0 128 128"`. Silhueta dentro de ~6..122 (margem de 6 px já contando o contorno).
- **Contorno:** `#05070D` (Ink), **8 px** na silhueta, `stroke-linejoin="round"` e `stroke-linecap="round"`.
  Detalhes internos (facetas, olhos, linhas do pergaminho) usam 5–6 px. Traços "de linha" (✓, ✕, +, setas, alças)
  são feitos com traço duplo: Ink com largura = cor + 16 (8 px de cada lado), depois a cor por cima.
- **Cores (só estas — o exportador recusa qualquer outra):**
  | Papel | Token | Hex |
  |---|---|---|
  | corpo principal | White | `#FFFFFF` |
  | sombra suave do branco / face secundária | Ice | `#CFEFFF` |
  | energia, magia, destaque | Cyan | `#4FD2FF` |
  | meio-tom de peças azuis | Blue400 | `#4A95FF` |
  | acentos sólidos (guarda da espada, faixa, cubo) | Blue500 | `#1E6BFF` |
  | partes escuras (cabo, espessura da moeda) | Blue700 | `#1546B8` |
  | contorno e pequenos detalhes | Ink | `#05070D` |
- **Branco domina, azul é acento.** Áreas grandes são White ou Cyan (leem bem sobre botão azul e sobre painel
  escuro). Blue500/Blue700 só em peças pequenas, sempre separadas do fundo pelo contorno Ink.
- **Brilho:** permitido um highlight interno pequeno (arco ou elipse White/Cyan) — nada de gradiente.
- **Sem texto.** Única exceção: o `¥` da moeda (desenhado como path, nunca `<text>`). O `!` do `new` é forma.
- **Linguagem compartilhada:** a mesma espada (lâmina branca com meia-face Ice, guarda Blue500, cabo Blue700,
  pomo Cyan) aparece em `auto`, `raids` e `kills`; a mesma moeda `¥` em `yen` e `sell`; o mesmo brilho de 4 pontas
  em `summon`, `gold` e `worlds`. Modificadores vêm como "selo" no canto (ex.: `sell` = moeda + selo de menos).
- **Legibilidade:** testar sempre a 32 px (linha pequena da contact sheet). Se virar "listras", simplificar.

## 2. Lista de ícones (contrato com o código)

Os nomes abaixo são as chaves de `Theme.IconAssets` e do `manifest.json`. Não renomear sem combinar com o código.

| Nome | Desenho | Uso / significado |
|---|---|---|
| `yen` | moeda branca, face Blue500 com `¥` | moeda principal (Yen) |
| `gems` | diamante facetado ciano | moeda premium (Gems) |
| `gold` | duas pilhas de moedas brancas + brilho | moeda Gold |
| `tokens` | tíquete inclinado com canhoto ciano e estrela | Tokens (eventos/raids) |
| `power` | punho branco sobre estouro de impacto ciano | Power total / dano |
| `fighters` | busto de lutador: cabelo espetado ciano, faixa e gi azuis | inventário de unidades |
| `summon` | orbe azul no suporte com estrela de 4 pontas | invocar / banner |
| `settings` | engrenagem branca, cubo Blue500 | configurações |
| `auto` | duas setas ciano em ciclo em volta de uma espada | auto-ataque / auto-farm |
| `sort` | seta branca para cima + seta ciano para baixo | ordenar |
| `lock` | cadeado branco, alça Ice, buraco Blue500 | travar unidade / bloqueado |
| `check` | visto branco grosso | equipado / confirmado |
| `close` | X branco grosso | fechar janela |
| `plus` | + branco grosso | comprar mais / adicionar |
| `quests` | pergaminho com rolos ciano e linhas | missões |
| `shop` | sacola branca com faixa Blue500 | loja |
| `upgrades` | seta branca para cima + duas divisas | upgrades |
| `worlds` | planeta ciano com anel branco | mundos / teleporte |
| `raids` | duas espadas cruzadas | raids |
| `boss` | caveira com chifres ciano e olhos brilhando | chefe / barra de boss |
| `zone` | pino de mapa branco sobre anel ciano no chão | zona / área atual |
| `target` | mira com anel branco e marcas ciano | alvo / travar alvo |
| `team` | três bustos (líder branco na frente) | time equipado |
| `timer` | cronômetro com fatia ciano do tempo decorrido | tempo / boost / cooldown |
| `sell` | moeda `¥` + selo ciano com "−" | vender |
| `new` | selo estourado ciano com `!` | item NOVO / notificação |
| `star` | estrela branca chanfrada (meias pontas Ice) | estrelas / favorito / raridade |
| `kills` | marcas de contagem ciano riscadas por uma espada | abates |

Glifos antigos de `Theme.Icons` → ícone novo: Yen→`yen`, Gems→`gems`, Gold→`gold`, Tokens→`tokens`, Power→`power`,
Inventory→`fighters`, Summon→`summon`, Worlds→`worlds`, Quests→`quests`, Shop→`shop`, Upgrades→`upgrades`,
Raids→`raids`, Settings→`settings`, Auto→`auto`, Lock→`lock`, Equipped→`check`, Star→`star`, Close→`close`,
Sort→`sort`, Plus→`plus`. (Filter e Fuse continuam como glifo até ganharem arte.)

## 3. Upload para o Roblox

### 3.1 Em lote pelo Studio (Asset Manager / Bulk Import) — recomendado
1. Abra o place no Roblox Studio (o jogo precisa estar publicado para os assets ficarem no dono certo:
   **File → Publish to Roblox** se ainda não estiver).
2. **View → Asset Manager**.
3. Clique em **Bulk Import** (ícone de upload no topo do Asset Manager).
4. Selecione **todos** os arquivos de `assets/icons/png/` (28 PNGs) e confirme.
5. Aguarde a moderação: os itens aparecem em **Images** com o nome do arquivo (`yen`, `gems`, …). Enquanto
   estiverem "em revisão", aparecem em branco/cinza no Studio — é normal.
6. Para cada imagem: clique com o botão direito → **Copy Asset ID** (copia `rbxassetid://<id>`).

### 3.2 Alternativa pelo Creator Hub (navegador)
1. https://create.roblox.com → **Creations** → escolha a experiência (ou o grupo dono dela).
2. **Development Items → Decals/Images → Upload Asset**, envie os PNGs (o Creator Hub aceita vários arquivos).
3. Abra cada item, copie o **Asset ID** numérico. Atenção: se subir como **Decal**, use o id da **Image**
   (no Studio, colar o id de decal num `ImageLabel` converte para o id da imagem; copie o id convertido).
4. Envie os ícones pela mesma conta/grupo dono do jogo; imagens de outro dono podem não carregar.

### 3.3 Registrar os ids
1. Preencha `assets/icons/manifest.json` (só o número ou já no formato `rbxassetid://<id>`):
   ```json
   "yen": { "png": "png/yen.png", "rbxassetid": "rbxassetid://1234567890" }
   ```
2. Copie para `Theme.IconAssets` em `src/StarterPlayer/StarterPlayerScripts/Client/UI/Theme.luau`
   (tabela criada pelo agente de código; chave = nome do ícone):
   ```lua
   Theme.IconAssets = {
   	yen = "rbxassetid://1234567890",
   	gems = "rbxassetid://…",
   	-- … um por ícone da tabela do §2
   }
   ```
   Chave vazia/ausente → o código deve cair no glifo de `Theme.Icons` (fallback).
3. Rode `rojo serve` / sincronize e confira no Play Solo e no emulador de celular (iPhone SE paisagem).

### 3.4 Uso em `ImageLabel`
- `Image = Theme.IconAssets.<nome>`, `BackgroundTransparency = 1`, `ScaleType = Fit`, `ImageColor3 = (1,1,1)`.
  Os ícones já vêm coloridos: **não** tingir com `ImageColor3` (multiplica as cores e quebra a paleta).
  Desabilitado = `ImageTransparency 0.45` (ou `ImageColor3` cinza `#6B7BA3`, que só escurece).
- Tamanhos-alvo: menu 40–44 px no botão de 68 · badge de moeda 30–32 px · toolbar 24–28 px · card 18–22 px.
  Abaixo de 18 px use o glifo.
- O PNG tem 256 px: o Roblox reduz sem perda visível; não suba versões menores.

## 4. Reexportar / adicionar um ícone

1. Edite (ou crie) `assets/icons/svg/<nome>.svg` seguindo o §1. Ícone novo: adicione o nome ao array `ICONS`
   no topo de `assets/icons/tools/export.js`.
2. Pré-requisito (uma vez): Node 18+ e Playwright com Chromium
   (`npm i -g playwright && npx playwright install chromium`).
3. Na raiz do repositório:
   ```sh
   node assets/icons/tools/export.js
   # opcional: folha grande para revisar detalhes (128 px)
   node assets/icons/tools/export.js --review /tmp/icons-review.png
   ```
   O script valida cada SVG (viewBox 128, sem `<text>`, sem imagem embutida, **só cores da paleta**) e falha
   com a lista de problemas; depois gera `png/`, `contact-sheet.png` e atualiza `manifest.json` **preservando**
   os `rbxassetid` já preenchidos.
4. Abra `assets/icons/contact-sheet.png` e confira a 64 px e a 32 px nos dois fundos.
5. Ícone alterado = **novo upload** (o Roblox não substitui a imagem de um id): suba o PNG novo, troque o id no
   `manifest.json` e em `Theme.IconAssets`.
