# Development Log

## 2026-11-24 — Sessão 1 (nuvem, sem Roblox Studio)

### Etapa 1 — Análise e arquitetura
- Repositório continha apenas a plataforma web "Aero" (Python/JS: `app.py`, `services.py`, `index.html`...),
  sem nenhum código de jogo. Esses arquivos **não foram alterados**; o jogo foi adicionado em `src/`.
- Ambiente: sem Roblox Studio. Instalados via crates.io: **Lune 0.11.1** (runtime Luau para testes),
  **Selene 0.31.0** (linter) e **StyLua 2.6.0** (formatador). Rojo não foi necessário para gerar/validar arquivos.
- Selene: a std oficial `roblox` precisa baixar a API dump de `setup.rbxcdn.com` (bloqueado na rede deste
  ambiente). Criado `roblox_lite.yml` (std mínima com os globais do Roblox). Com rede liberada, trocar para `std = "roblox"`.
- Criados: `default.project.json`, estrutura `src/`, configs compartilhadas, módulos compartilhados, camada de rede,
  harness de testes (árvore virtual estilo Rojo + mocks).

### Etapa 2 — Player Data e Economy
- `DataService` (session lock, UpdateAsync, retentativas, kick seguro, sanitização, migrações, autosave, BindToClose).
- `EconomyService` (Add/Remove/Purchase/PurchaseBundle/GrantRewards com OnceKey, log de transações).
- `BoostService` (composição de multiplicadores).

### Etapa 3 — Units e Inventory
- `UnitService` (criação com trait, equipar/limite, Equip Best, travar, vender, XP/nível, fusão com estrelas, evolução, reroll).
- `InventoryService` (stacks, bloqueio, venda, uso de itens por handler de efeito, capacidade de unidades).

### Etapa 4 — Summon
- `SummonService` (x1/x10, pesos por banner, luck, pity persistido, garantia no x10, auto-venda, histórico).

### Etapa 5 — Combat e Enemy
- `EnemyService` (spawners por área, chefes, zonas, defesa, morte, recompensas compartilhadas, drops, agressão).
- `CombatService` (loop de 0,1 s, alvo manual/automático, crítico, especiais via `AbilityHandlers`).
- `EnemyVisuals` (modelos/placeholders + atributos para a UI).

### Etapa 6 — World e Progression
- `WorldService` (desbloqueio, teleporte, zonas, recompensa de clear), `ProgressionService` (níveis, upgrades),
  `MapService` (mapa greybox), `ShopService`, `EventService`.

### Etapa 7 — Quests
- `QuestService` (cadeia principal + diárias determinísticas), `AchievementService`, `RaidService`,
  `SettingsService`, `AdminService`.

### Etapa 8 — UI
- 17 controllers de cliente + `State` + `UI/Components` + `UI/Theme`.

### Etapa 9 — Integração
- Teste que executa o `Main.server.luau` real: os 18 serviços sobem sem erro, remotes registrados, mapa gerado,
  jogador entra e recebe perfil.
- Teste de sessão completa: combate → quest → summon → equip → upgrade → nível → mundo 2 → raid → salvar → recarregar em outro servidor.

### Etapa 10 — Auditoria
- Selene: 0 erros, 0 avisos. StyLua: formatado. **164 testes passando** (`lune run tests/run`).
- Correções da auditoria: limite de unidades que lutam quando slots diminuem; contagens regressivas do cliente
  usam o relógio do servidor; alturas do greybox (inimigos, marcadores, arenas); `SpawnLocation` no mapa gerado;
  `MapService` usa `CFrame` em vez de `Position`.

### Preview da UI (sem Studio)
- Criado `tools/ui-preview/`: executa o cliente REAL (`Main.client.luau` + 17 controllers) sobre Instances
  simuladas (`FakeRoblox`), ligado aos serviços REAIS do servidor por uma ponte de rede em memória, e
  renderiza a árvore de GUI em HTML (`Render`: UDim2, AnchorPoint, UIListLayout, UIGridLayout, UIPadding,
  UICorner, UIStroke, UIScale, AutomaticSize, ScrollingFrame) para screenshots via Playwright.
- É uma aproximação do renderizador do Roblox (fonte Inter no lugar da Gotham; mundo 3D não aparece).
- Problemas reais encontrados e corrigidos com ele:
  - nome do mundo sobreposto às moedas no HUD;
  - barra de rolagem cobrindo o fim dos valores (agora `VerticalScrollBarInset = ScrollBar`);
  - raridade Secret quase preta, ilegível no fundo escuro;
  - botões da aba Items com a mesma cor da linha (invisíveis);
  - **celular**: janelas de tamanho fixo saíam da tela (cabeçalho e botão fechar inacessíveis) → `UIScale`
    responsivo em janelas e HUD (`UIController:AddScaled`), recalculado quando o `ViewportSize` muda;
  - `C.Clear` apagava o `UIScale` junto com o conteúdo;
  - nome do mundo aparecendo cortado atrás das janelas.
- Novo teste `tests/specs/70_client.spec.luau`: sobe o cliente real, abre todas as janelas, faz summon pela UI
  e verifica a escala no celular. **167 testes passando.**

### Redesign visual (estilo "simulador", identidade própria)
- Inspirado na linguagem visual do gênero (botões redondos com ícone, pílulas de moeda, texto com contorno,
  gradientes, cards de raridade), **sem copiar** layout, logo, títulos ou arte do Anime Fighters Simulator.
- Tema novo (`UI/Theme`): paleta índigo/ciano/laranja, fontes Fredoka One e Luckiest Guy, ícones em emoji
  centralizados em `Theme.Icons` (trocar por imagens `rbxassetid` quando houver arte).
- Componentes novos: `C.IconButton`, `C.CurrencyPill`, `C.Title`/`C.Outline`, `C.Gloss`, `C.HighlightCard`;
  janelas com cabeçalho em gradiente e botão de fechar redondo; cards de unidade com retrato (iniciais).
- HUD: moedas empilhadas (atalho "+" para a loja), banner do mundo, "Team Power" (DPS estimado), boosts/eventos
  em selos, menu em grade de botões redondos, nível em selo + barra, botão AUTO grande.
- Inventário: contadores de unidades/equipados, botões grandes Equip Best / **Unequip All** (novo remote no servidor).
- Preview atualizado: `UIGradient`, contorno de texto (`UIStroke` Contextual), fontes do Google Fonts. **168 testes.**

### Jogo base (essência do gênero, só o Mundo 1)
- `Config/Features.luau`: chaves para cada sistema; o jogo base desliga tudo que não é o loop essencial.
  O servidor responde `FeatureDisabled` e a UI esconde botões/abas. Testes rodam com tudo ligado
  (`ServerHarness.new()`) e com o jogo base (`{ BaseGame = true }`).
- Loop essencial: clicar inimigo → lutadores correm até ele (alcance `Combat.FighterReach` = 60) e cercam/golpeiam;
  auto-ataque pega o mais próximo em `AutoTargetRange` = 45 → moedas espirram e voam até o jogador
  (`EnemyDefeated` → `CoinController`) → Yen abre o **orbe** do Mundo 1 (x1 = 100 ¥, x3 = 280 ¥) →
  Equip Best → zonas mais fortes e chefes.
- `RigBuilder`: bonecos humanoides em blocos (com olhos e cabelo) para inimigos e lutadores até existir arte.
- Mapa greybox do Mundo 1: chão, caminhos entre zonas, árvores, placas "Zone 1/2", arenas dos chefes,
  orbe de invocação com letreiro e ProximityPrompt, cerca viva + paredes invisíveis na borda.
- Inimigos renomeados para nomes originais (Bandit King, Oni Warlord).
- Preview 3D (`tools/ui-preview/scene.luau` + three.js): o mapa real e os rigs, com a UI real sobreposta.
- **179 testes passando.**

### UI preto/branco/azul (agentes pesquisador + construtor)
- Pesquisador: guia `docs/ui/UI_RESEARCH.md` (convenções do gênero, tokens da paleta, fontes, specs de componentes,
  lista do que NÃO copiar de jogos existentes).
- Construtor: `UI/Theme` e `UI/Components` refeitos (botões 3D com base que afunda, tipos Primary/Secondary/Accent/
  Dark/Danger com confirmação em 2 toques, janelas com cabeçalho azul com speed-lines, cards escuros com faixa de
  raridade, ✓ azul de equipado, pílulas de moeda, toggles), todos os controllers migrados, ícones em glifos
  monocromáticos, barras de vida brancas, números de dano brancos/ciano. AUTO foi para o centro-direita
  (fora do botão de pulo no celular); toasts no topo.
- 179 testes passando, selene 0/0, preview sem warnings.

### HUD + ícones (5 agentes em paralelo, git worktrees separados)
- Ícones: 28 ícones originais em SVG + PNG 256px (`assets/icons/`, script de exportação com checagem de paleta,
  folha de contato, `manifest.json`, guia de upload `docs/ui/ICONS.md`) e o mesmo conjunto desenhado em código
  (`UI/Icons.luau`: imagem de `Theme.IconAssets` se houver, senão vetor, senão glifo).
- Barra do time (lutadores equipados, espaços vazios, toque abre o lutador), aviso de lutador melhor, contador NOVO.
- Indicador de zona, painel do alvo (vida branca com rastro), alertas de chefe, toasts reposicionados.
- Feedback de recompensa (+X ¥ animado, contagem, ¥/min), painel STATS da sessão, AUTO com ponto orbitando
  (o ícone não gira: ícones vetoriais usam recorte, que o Roblox desliga sob rotação).
- Letreiro grande do mundo removido do topo. Pastas vazias de Assets agora versionadas (.gitkeep).
- 205 testes passando, selene 0/0.

### Rework completo da UI (imagem de referência)
- Servidor: `CodesService` + `Config/Codes` (resgate único, validade, sem diferença de maiúsculas), pontos de
  teleporte por mundo (`TeleportToPoint`), `data.Discovered` para o Index, `Settings.LastSeenUpdate`.
- Removidos: pílula de Power, "≈ ¥/min", botão AUTO (o auto-ataque continua em Settings), barra dos lutadores
  equipados embaixo (e o aviso de lutador melhor), painel/botão STATS do canto superior direito, legendas
  embaixo dos ícones. O poder do time está na janela Stats; o contador NOVO de lutadores foi para o botão Fighters.
- Menus laterais em grade 2×N só com ícones (`UI/Navigation`, `C.NavButton`): esquerda Shop/Fighters/Settings/
  Codes/Quests/TP, direita Inventory/Mounts/Achievements/Stats/Index. Hover cresce e acende o contorno, clique
  afunda, janela abre com "pop" + escurecimento. As grades se posicionam abaixo das infos do jogador e do card de
  Update Log e encolhem no celular sem sobrepor nada (`UIController:LayoutNav`).
- Card UPDATE LOG no canto superior direito + janela (`Config/UpdateLog`, mais nova primeiro, selo NEW salvo).
- Janelas novas: Codes, Teleport, Index, Inventory (carteira + itens), Achievements (separada de Quests), Stats,
  Mounts (preparada, sem dados falsos); Shop mostra "fechada" enquanto o sistema está desligado.
- Componentes novos: `C.Section`, `C.EmptyState`, `C.StatTile`, `C.TextInput`, `C.ClaimRow`. Preview com TextBox.
- 8 ícones novos (codes, mounts, index, achievements, stats, teleport, update, inventory).
- **223 testes passando**, selene 0/0, preview sem warnings.

### Ícones PNG + botões preto/branco
- `assets/UI_Icons/`: 12 ícones originais em PNG 512×512 com fundo transparente (Shop, Fighters, Settings, Codes,
  Quests, Teleport, Inventory, Mounts, Achievements, Stats, Index, UpdateLog), cada um com cor própria; estilo
  minimalista/brutalista arredondado com volume 3D (extrusão sólida, contorno preto grosso, realce branco em pílula); fontes SVG em `src/`, exportador `tools/export.js` (Chromium), folha de
  revisão `preview.png` (512/48/32 px), `manifest.json`, `README.md` com o mapeamento; `assets/UI_Icons.zip`.
- Redesenhados com base em referências de ícones de jogos: Fighters = punho fechado com faixa (mais legível que
  um busto em 32 px), Teleport = portão de pedra em arco com redemoinho dentro, Mounts = cabeça de cavalo de perfil
  com crina e cabresto (deixa claro que é montaria).
- Depois: Teleport virou o próprio portal azul (aro arredondado com vórtice em espiral afundado e núcleo
  brilhante, sem portão); todos ficaram mais redondos (arredondamento maior) e mais 3D (faces com iluminação
  difusa + especular via filtro SVG, reflexos em degradê, detalhes também iluminados).
- `Client/UI/IconAssets.luau`: único arquivo a editar depois do upload (ícone → `rbxassetid://`). Imagens enviadas
  são mostradas sem tingir; sem ID, o desenho vetorial aparece na mesma cor (`Theme.IconColors`).
- Botões dos menus, card do Update Log e ladrilho do título das janelas: face grafite, borda clara, sombra preta
  suave; hover clareia, clique escurece e encolhe. Sem barras de cor e sem fundo ciano; badges brancos.
- Preview: `lune run tools/ui-preview/preview <dir> --png-icons` mostra os PNGs onde o jogo mostrará as imagens.
- **225 testes passando**, selene 0/0.

### HUD no estilo da referência + ícone do Yen
- `Icon_Yen.png` (moeda dourada com ¥, mesmo estilo 3D); moedas que voam e a carteira agora são douradas.
- Contador de Yen virou um bloco arredondado da largura do menu e fica colado em cima dos botões da esquerda
  (`UIController:AttachAboveNav`), escalando junto com eles.
- Botões no estilo da imagem de referência: fundo escuro tingido e borda grossa na cor do ícone, aro escuro e sombra,
  nome dentro do botão, tecla de atalho no canto (PC), botões largos (Shop, Teleport, Index) com brilho periódico,
  hover/clique animados, badges vermelhos pulsando. Atalhos novos sem conflito com as teclas padrão do Roblox.
- Preview: suporte a `UITextSizeConstraint` e a degradê só de transparência.

### Sistema de janelas no estilo das referências
- Modelo único de janela: título em degradê azul, X vermelho dentro da barra, corpo azul-marinho, aro e linha
  dourados; animação de abrir (aumento + fade) e fechar (redução + fade) com CanvasGroup; arrastar pela barra de
  título com limite na tela; Esc fecha; botão do menu fica destacado com a janela aberta; abas ativas com sublinhado
  dourado; item selecionado com contorno dourado.
- Conteúdo: Shop com abas e cards (quando ligada), Power nos cards do Fighters, Teleport por mundo com mundos
  bloqueados e requisitos, Inventory em grade com detalhes, Mounts pronto para dados reais (`Config/Mounts`),
  Achievements com %, Stats com Yen gasto e dano total, Index com abas por mundo, Update Log com seções.
- Preview: CanvasGroup, arrastar (InputChanged) e cena `tools/ui-preview/scenes/windows` com Shop/Items ligados.
- **236 testes passando**, selene 0/0.

### Ajustes pedidos nas janelas
- Inventory sem carteira (o Yen já está no HUD). Shop virou loja de game passes (preço em Robux, BUY/OWNED,
  bônus aplicados pelo servidor); a loja por moedas continua no servidor, mas fora da UI.
- Sem ícone repetido dentro das janelas: tirado o ícone do título, das telas vazias e dos botões REDEEM/GO.
- Fighters: barra com A (nome), espada (força), ¥ (vender) e cadeado (trancar personagens).
- **237 testes passando**.

### Números
- 77 arquivos Luau em `src/` (~9.800 linhas), ~2.200 linhas de testes.

### O que NÃO foi feito/verificado
- Nada foi executado no Roblox Studio nem publicado. A UI e os visuais 3D só foram verificados por compilação e lint.
- Nenhum modelo 3D real foi criado (apenas placeholders gerados por código).
- DataStores reais não foram configurados (testados com mock que simula serialização JSON e falhas).
- IDs de Developer Products/Game Passes não existem ainda.
