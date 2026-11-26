# UI_Icons — ícones dos menus do HUD

13 ícones PNG **512×512, fundo transparente (RGBA)**, prontos para `ImageLabel` no Roblox.
Arte original, estilo minimalista arredondado em 3D: formas simples e grossas com cantos bem redondos, cor própria
de cada ícone, contorno preto pesado, faces "infladas" com luz de cima/esquerda (brilho e sombra nas bordas),
reflexos em degradê e lateral extrudada mais escura. Sem texto, sem fundo
quadrado/redondo; legível a 32×32 e 48×48 px (ver `preview.png`).

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
| `Icon_Achievements.png` | Menu direito · Achievements | dourado `#FFB81C` | `achievements` |
| `Icon_Stats.png` | Menu direito · Stats | vermelho `#FF4545` | `stats` |
| `Icon_Index.png` | Menu direito · Index | violeta `#7C5CFF` | `index` |
| `Icon_UpdateLog.png` | Card "UPDATE LOG" (canto superior direito) | menta `#34E3A5` | `update` |
| `Icon_Yen.png` | Contador de Yen (em cima do menu esquerdo) e carteira do Inventory | dourado `#FFC21A` | `yen` |

Os mesmos ícones aparecem no ladrilho do título de cada janela.

## Colocar no jogo
1. Roblox Studio → **View → Asset Manager → Bulk Import** → selecione os 13 PNGs
   (ou Creator Hub → Development Items → Images → Upload).
2. Em cada imagem: botão direito → **Copy Asset ID**.
3. Cole em `src/StarterPlayer/StarterPlayerScripts/Client/UI/IconAssets.luau`, por exemplo
   `shop = "rbxassetid://1234567890",`.
4. Pronto: o botão passa a usar o PNG (sem tingir: a imagem mantém as próprias cores). Enquanto uma chave
   estiver `""`, o jogo usa o desenho vetorial em código na mesma cor, então nada aparece quebrado.

## Editar / exportar de novo
Fontes em `src/*.svg` (viewBox 512). `node assets/UI_Icons/tools/export.js` regera os PNGs, `preview.png`
e `manifest.json` (precisa do Playwright com Chromium).
