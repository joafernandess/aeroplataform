# O que fazer no Roblox Studio

Tudo abaixo depende do Studio/site do Roblox e **não foi feito** neste ambiente de nuvem.

## 1. Ferramentas (uma vez)
1. Instale o [Rokit](https://github.com/rojo-rbx/rokit) (ou Aftman) e rode na raiz do repositório:
   `rokit install` — instala Rojo, Lune, Selene e StyLua nas versões de `rokit.toml`.
2. Instale o plugin **Rojo** no Studio (Plugins › Manage Plugins, ou `rojo plugin install`).

## 2. Sincronizar o código
1. Na raiz do repositório: `rojo serve`
2. No Studio, abra um place (pode ser o template **Baseplate**), clique em **Rojo › Connect**.
3. O código aparece em `ReplicatedStorage.Shared`, `ServerScriptService.Server`,
   `ServerStorage.Assets` e `StarterPlayer.StarterPlayerScripts.Client`.
   Alternativa sem servidor: `rojo build -o AnimeFighters.rbxlx` e abrir o arquivo.

## 3. Primeira execução (Play)
- O `MapService` gera um mapa greybox se não houver `Workspace.Worlds`. Se o template tiver um
  `Baseplate` e `SpawnLocation`, pode removê-los (o mapa gerado já tem SpawnLocation no Mundo 1).
- Abra a Output: deve aparecer `[Server] 18 services running: ...`.
- No Studio todo jogador é admin. Exemplo pelo console do **cliente** (Command Bar em modo cliente):
  ```lua
  local Net = require(game.ReplicatedStorage.Shared.Remotes.Net)
  print(Net.Request("AdminCommand", "give", { Currency = "Gems", Amount = 5000 }))
  print(Net.Request("AdminCommand", "unlockall"))
  ```

## 4. DataStores
- Game Settings › Security › **Enable Studio Access to API Services** (o jogo precisa estar publicado).
- Sem isso, o `DataStoreAdapter` usa memória e avisa na Output (o progresso não é salvo).
- Antes de lançar, defina `GameConfig.Data.StoreName` definitivo. Nunca o altere depois (zera dados) — use `Migrations`.

## 5. Monetização (opcional)
1. Crie Developer Products e Game Passes no Creator Dashboard.
2. Preencha `ProductId` / `PassId` em `Shared/Config/Shop.luau` (0 = desativado e oculto na UI).
3. Teste compras no Studio (compras de teste não cobram Robux).

## 6. Arte e mapa
- **Mapa**: construa `Workspace.Worlds.<W1..W5>` com `Spawn` (BasePart), `SpawnAreas/<Field|Camp>` (BaseParts)
  e `NPCs/*` com `ProximityPrompt` e atributos `Role` (Summon/Quest/Shop/Upgrade/Teleport/Raid) e `WorldId`.
  Se `Workspace.Worlds` existir, o greybox não é gerado e as posições das peças substituem as da config.
  Convenção de altura da config: Y = 3 é "1 stud acima do chão".
- **Inimigos**: Models em `ServerStorage/Assets/Enemies/<EnemyId>` com `PrimaryPart` (ex.: `W1_Bandit`).
- **Unidades** (visual no cliente): Models em `ReplicatedStorage/Assets/Units/<UnitId>` com `PrimaryPart`.
  Precisam estar em ReplicatedStorage porque o cliente os clona.
- Sem modelos, placeholders coloridos são gerados automaticamente.

## 7. Verificações manuais recomendadas (não feitas aqui)
- [ ] Layout das janelas em PC, celular (Device Emulator) e console.
- [ ] Clique/toque em inimigos seleciona o alvo; X limpa.
- [ ] Barras de vida e números de dano aparecem.
- [ ] Unidades seguem o personagem.
- [ ] Teleporte entre mundos e arena de raid (alturas do greybox).
- [ ] Salvar → sair → entrar novamente com API Services ativado.
- [ ] Desempenho com muitos jogadores (MicroProfiler) — ajustar `GameConfig.Combat.TickRate` se necessário.
