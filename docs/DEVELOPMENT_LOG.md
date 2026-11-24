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

### Números
- 77 arquivos Luau em `src/` (~9.800 linhas), ~2.200 linhas de testes.

### O que NÃO foi feito/verificado
- Nada foi executado no Roblox Studio nem publicado. A UI e os visuais 3D só foram verificados por compilação e lint.
- Nenhum modelo 3D real foi criado (apenas placeholders gerados por código).
- DataStores reais não foram configurados (testados com mock que simula serialização JSON e falhas).
- IDs de Developer Products/Game Passes não existem ainda.
