# Arquitetura — Anime Fighters (Roblox)

## Visão geral

O jogo é um projeto **Rojo** escrito 100% em **Luau**. Toda a lógica de jogo que envolve moedas, dano,
recompensas, raridades e resultados de invocação roda **no servidor**. O cliente só exibe estado e envia
pedidos, que o servidor valida.

```
default.project.json            mapeamento Rojo -> DataModel
src/
  ReplicatedStorage/Shared/     (ReplicatedStorage.Shared) — visível ao cliente e ao servidor
    Config/                     dados do jogo (unidades, inimigos, mundos, banners, quests...)
    Modules/                    lógica pura compartilhada (fórmulas, stats, RNG, validação...)
    Types/                      tipos Luau dos dados salvos e do protocolo
    Remotes/                    RemoteNames (superfície de rede) + Net (camada de rede)
  ServerScriptService/Server/   (ServerScriptService.Server) — só servidor
    Main.server.luau            ponto de entrada: carrega todos os serviços
    Core/                       ServiceLoader, PlayerUtil
    Data/                       DataTemplate, Migrations, DataStoreAdapter
    Combat/                     AbilityHandlers (registro de habilidades), EnemyVisuals (Instances)
    Services/                   18 serviços (ver SYSTEMS.md)
  ServerStorage/Assets/         (ServerStorage.Assets) — modelos de inimigos/NPCs (só servidor)
  StarterPlayer/StarterPlayerScripts/Client/
    Main.client.luau            ponto de entrada do cliente
    State.luau                  espelho somente-leitura do perfil do jogador
    UI/                         Theme + Components (fábrica de UI por código)
    Controllers/                17 controllers (HUD, inventário, summon, combate...)
tests/                          testes automatizados em Lune (fora do Roblox)
docs/                           esta documentação
```

## Decisões técnicas

| Decisão | Motivo |
|---|---|
| **Rojo** + arquivos `.luau` | Versionamento em Git, edição fora do Studio, revisão de código. |
| **Serviços com ciclo Init/Start** (`Core/ServiceLoader`) | `Init` é síncrono (resolve dependências, registra remotes); `Start` roda em thread própria (loops, eventos de Players). Evita dependência de ordem de `require`. |
| **Serviços se acessam pela tabela `services`**, não por `require` direto | Elimina ciclos de require (Economy ↔ Unit ↔ Inventory). |
| **Configs como dados puros** (`Shared/Config`) sem tipos do Roblox | Posições são `{x, y, z}`, cores são `{r, g, b}`. Assim as configs rodam nos testes fora do Roblox e podem ser lidas pela UI. Cada config se auto-valida com `assert` ao carregar. |
| **Lógica pura compartilhada** (`Formulas`, `UnitStats`, `Requirements`, `Rewards`) | A UI mostra exatamente os números que o servidor usa, sem duplicar fórmulas. |
| **Uma única camada de rede** (`Remotes/Net`) | Todos os remotes declarados em `RemoteNames`; cada handler tem rate limit por jogador, `pcall` e resposta padronizada `{ ok, data?, error? }`. |
| **EconomyService é o único que altera moedas** | Validação central (NaN, infinito, negativos, limite), log de transações, idempotência (`OnceKey`). |
| **Estado de inimigos em tabelas, visuais num adaptador** (`EnemyVisuals`) | O combate é testável sem Instances; o modelo 3D é só espelho. |
| **Unidades do jogador são virtuais no servidor** | O servidor simula ataques a partir da posição do personagem; o cliente desenha as unidades (`UnitVisualController`). Menos carga de rede/física. |
| **Zonas** (`World:<id>`, `Raid:<instância>`) | Inimigos de raid ficam isolados: outros jogadores não podem atacá-los. |
| **`Clock` e `RNG` injetáveis** | Testes controlam o tempo (resets diários, cooldowns) e a aleatoriedade (pity, drops). |

## Fluxo de dados

```
Cliente (Controller) --Net.Request--> Net (rate limit + pcall) --> Serviço (valida) --> EconomyService / DataService
                                                                                      |
Cliente (State) <--DataChanged(chave, valor)-- DataService:MarkDirty (agrupado por frame) <-+
```

- O perfil completo chega no início via `GetProfile`; depois só chaves de primeiro nível alteradas.
- Chaves privadas (`ProcessedReceipts`, `ClaimedRewards`) nunca são enviadas ao cliente.

## Ciclo de vida do servidor

1. `Main.server.luau` chama `Net.Init()` (cria a pasta `ReplicatedStorage.Remotes`).
2. `ServiceLoader.Load` faz `require` de cada ModuleScript em `Services/`.
3. `InitAll` em ordem de `Priority` (Map 0, Data 1, Economy 2, Event 2, Boost 3, Inventory 4, Unit 5, ...).
4. `StartAll`: cada `Start` em sua própria thread.

## Segurança (resumo)

- Cliente nunca envia quantidades de moedas, dano, raridade ou resultado — apenas IDs e escolhas.
- Todo argumento remoto passa por `Shared/Modules/Validate` (tipos, NaN, infinito, tamanho, listas sem duplicatas).
- Rate limit por remote e por jogador (token bucket).
- Compras são atômicas: `Economy:Purchase` cobra, executa e **reembolsa** se a concessão falhar.
- Recompensas únicas (quests, conquistas, nível, clear de mundo) usam `OnceKey` persistido.
- Recibos de Robux deduplicados por `PurchaseId`.
- Dados com **session lock**, `UpdateAsync`, retentativas e kick seguro (ver SYSTEMS.md › Player Data).

## Testes

`lune run tests/run` executa os testes em [Lune](https://lune-org.github.io/docs). O harness
(`tests/harness/Runtime.luau`) monta uma árvore virtual idêntica ao `default.project.json`, implementa
`script`, `require(instance)` e `game:GetService`, e fornece mocks de DataStore, Players, RunService,
HttpService e MarketplaceService. Assim **os módulos reais** do servidor são testados, não cópias.
