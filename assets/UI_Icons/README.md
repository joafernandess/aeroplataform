# UI_Icons — ícones dos menus do HUD

13 ícones PNG **512×512, fundo transparente (RGBA)**, prontos para `ImageLabel` no Roblox.
Arte original, estilo **minimalista e chapado**: formas simples e arredondadas, uma cor por ícone (no máximo um
segundo tom da mesma cor), detalhes vazados (transparentes), sem contorno, sem 3D, sem brilho e sem estrelinhas.
Sem texto, sem fundo quadrado/redondo; legível a 32×32 e 48×48 px (ver `preview.png`).

| Arquivo | Botão no jogo | Cor | Chave em `UI/IconAssets.luau` |
|---|---|---|---|
| `Icon_Shop.png` | Menu esquerdo · Shop | dourado/amarelo `#FFD23F` | `shop` |
| `Icon_Fighters.png` | Menu esquerdo · Fighters | laranja `#FF8A1F` | `fighters` |
| `Icon_Settings.png` | Menu esquerdo · Settings | prata/branco `#E9EDF3` | `settings` |
| `Icon_Codes.png` | Menu esquerdo · Codes | roxo `#B04DFF` | `codes` |
| `Icon_Quests.png` | Menu esquerdo · Quests | verde `#3ED45E` | `quests` |
| `Icon_Teleport.png` | Menu esquerdo · TP | ciano `#2ED3FF` | `teleport` |
| `Icon_Inventory.png` | Menu direito · Inventory | azul `#3D8BFF` | `inventory` |
| `Icon_Mounts.png` | Menu direito · Mounts | rosa/magenta `#FF4FB8` | `mounts` |
| `Icon_Upgrades.png` | Menu direito · Upgrades | dourado `#FFB81C` | `upgrades` |
| `Icon_Stats.png` | Menu direito · Stats | vermelho `#FF4545` | `stats` |
| `Icon_Index.png` | Menu direito · Index | violeta `#7C5CFF` | `index` |
| `Icon_UpdateLog.png` | Card "UPDATE LOG" (canto superior direito) | menta `#34E3A5` | `update` |
| `Icon_Yen.png` | Contador de Yen (em cima do menu esquerdo) e cards Yen dos Upgrades | dourado `#FFC21A` | `yen` |

Dentro das janelas não se repete o ícone do menu (o botão já mostra).

## Colocar no jogo
1. Roblox Studio → **View → Asset Manager → Bulk Import** → selecione os 13 PNGs
   (ou Creator Hub → Development Items → Images → Upload).
2. Em cada imagem: botão direito → **Copy Asset ID**.
3. Cole em `src/StarterPlayer/StarterPlayerScripts/Client/UI/IconAssets.luau`, por exemplo
   `shop = "rbxassetid://1234567890",`.
4. Pronto: o botão passa a usar o PNG (sem tingir: a imagem mantém as próprias cores). Enquanto uma chave
   estiver `""`, o jogo usa o desenho vetorial em código na mesma cor, então nada aparece quebrado.

## Editar / exportar de novo
Os desenhos ficam em `tools/generate.py` (gera `src/*.svg`, viewBox 512). Depois de mudar:
```
python3 assets/UI_Icons/tools/generate.py assets/UI_Icons/src
node assets/UI_Icons/tools/fit.js assets/UI_Icons/src 424   # centraliza e ajusta o tamanho
node assets/UI_Icons/tools/export.js                         # PNGs, preview.png e manifest.json
```
(precisa do Playwright com Chromium). O jogo usa os mesmos formatos em vetor (`Client/UI/Icons.luau`, estilo chapado)
enquanto os PNGs não forem enviados — exceto Mounts, que no vetor é uma ferradura.
