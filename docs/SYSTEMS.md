# Sistemas

Cada seção indica arquivos, API principal, regras e estado real. "Testado" = coberto por testes
automatizados em Lune (fora do Roblox). Nada foi executado dentro do Roblox Studio.

---

## A. Player Data — `DataService`
Arquivos: `Server/Services/DataService.luau`, `Server/Data/{DataTemplate,Migrations,DataStoreAdapter}.luau`

Campos do perfil (`DataTemplate.Create`): `Level`, `Experience`, `Currencies {Yen, Gems, Gold, Tokens}`,
`Damage` (espelho de `Upgrades.Damage`), `Upgrades`, `Playtime`, `CurrentWorld`, `UnlockedWorlds`,
`ClearedWorlds`, `Inventory {Units, Items, LockedItems}`, `EquippedUnits`, `Quests`, `Achievements`,
`Settings`, `Stats`, `SummonPity`, `SummonHistory`, `TransactionLog`, `ClaimedRewards`, `ActiveBoosts`,
`RaidCooldowns`, `ProcessedReceipts`, `FirstJoin`, `LastJoin`, `DataVersion`.

Proteções contra perda de dados:
- **Session lock** gravado no registro (`Session = {JobId, LockedAt}`); outro servidor espera/retenta e, se o lock continuar ativo, **expulsa o jogador sem carregar** (nunca joga com dados padrão). Lock mais velho que `SessionLockTimeout` (30 min) é considerado órfão e é assumido.
- Leitura e escrita via `UpdateAsync` com retentativas exponenciais.
- Ao salvar, se outro servidor assumiu o lock, o save é abortado e o jogador é desconectado.
- `Sanitize` repara valores impossíveis (NaN/negativos, unidades/itens removidos da config, equipados inválidos, mundo atual inválido).
- Autosave (120 s), save + liberação ao sair, `BindToClose` salva todos.
- Versionamento: `DataVersion` + `Migrations` + `Reconcile` com o template (campos novos entram automaticamente). Perfis de versão mais nova que o servidor são recusados.
- Sem acesso a API no Studio → fallback em memória com aviso (`DataStoreAdapter`).

Estado: **implementado e testado** (lock, lock órfão, falhas transitórias, perda de lock, reconcile, sanitização, versão futura, playtime).

## I. Economy — `EconomyService`
API: `GetBalance`, `CanAfford`, `Add`, `Remove`, `Purchase` (cobra → executa → reembolsa se falhar),
`PurchaseBundle` (várias moedas), `GrantRewards` (formato de recompensa compartilhado, `OnceKey` idempotente,
multiplicadores opcionais). Sinal `CurrencyChanged`. Log de transações (50 últimas; motivos muito frequentes
como `EnemyKill` ficam fora). Saldo máximo `1e15`.
Estado: **implementado e testado**.

## B. Units — `UnitService` (+ `Shared/Modules/UnitStats`)
Instância salva: `{ Uid, UnitId, Level, XP, Stars, Trait?, Locked, ObtainedAt, Source }`.
Definição (`Config/Units`): Id, Name, Anime, Rarity, BaseDamage, AttackSpeed, Range, CombatStyle,
CritChance, Passive, Special, EvolvesTo, EvolutionCost, Evolved, Model.
- Raridades: Common, Rare, Epic, Legendary, Mythical, Secret, Divine, Exclusive (`Config/Rarities`).
- Criação com trait sorteado no servidor; UID sequencial por jogador (`U1`, `U2`...).
- Equipar/desequipar com limite (3 base + upgrade + game pass, máx. 8); "Equip Best" por Power.
- Bloqueio; exclusão (venda por Yen, ignora travadas/equipadas); comparação (`UnitStats.Compare`).
- **Fusão**: consome unidades (não travadas/não equipadas) → XP; cópias da mesma unidade dão +1 estrela (máx 5, +20% dano cada).
- **Evolução**: unidade no nível máximo + Yen/Gold + materiais → forma evoluída (mantém UID, estrelas, trait).
- Reroll de trait (Trait Crystal).
Estado: **implementado e testado**.

## J. Inventory — `InventoryService`
Itens empilháveis (Potion, Material, Evolution, Boost, Consumable) com `MaxStack`, bloqueio, venda,
`RemoveItems` tudo-ou-nada e `UseItem` com handlers por tipo de efeito (`UnitXP`, `TraitReroll`, `Boost`,
`Currency`) — o item só é consumido se o efeito tiver sucesso. Capacidade de unidades (100 base + upgrade, máx. 500).
Estado: **implementado e testado**.

## C. Summon — `SummonService` (+ `Config/Banners`)
- x1 e x10 (x10 com desconto), banners por mundo + banner de raid (Tokens) com Divine.
- Taxas em `Config/Banners` (pesos), validadas ao carregar; luck (upgrade, boost, evento, game pass) multiplica as raridades listadas em `LuckAffects`.
- **Pity** por banner e por raridade (ex.: Legendary em 75, Mythical em 400), persistido em `SummonPity`.
- **Garantia no x10** (`MultiGuarantee`).
- Auto-venda configurável de Common/Rare.
- Checagem de espaço antes de cobrar; cobrança via `Economy:Purchase`.
- Histórico (`SummonHistory`, 100 últimas) e resultado detalhado para a animação do cliente (`SummonController:PlayReveal`, substituível).
Estado: **implementado e testado** (inclui teste estatístico com 20.000 rolagens).

## D. Combat — `CombatService` (+ `Combat/AbilityHandlers`)
- Loop a cada 0,1 s; cada unidade equipada tem seu temporizador (Attack Speed) e cooldown de especial.
- Alvo manual (`SetTarget`, validado por zona e distância) ou automático (inimigo mais próximo no alcance, se `AutoAttack`).
- Dano = Damage da unidade × multiplicador do jogador (upgrades/boosts/eventos/passes) × passivas de time × buff Rally × bônus contra chefes × crítico; defesa reduz (`Formulas.DamageAfterDefense`).
- Habilidades especiais por **registro** (`AbilityHandlers.Register(tipo, fn)`): Strike, Cleave, Execute, Frenzy, Rally. Novos tipos não exigem mudar o CombatService.
- Números de dano agrupados por tick para o cliente.
Estado: **implementado e testado**.

## E. Enemies — `EnemyService` (+ `Combat/EnemyVisuals`)
- Tiers: Normal, Elite, MiniBoss, WorldBoss, RaidBoss (`Config/Enemies.Tiers`).
- Campos: ID, Nome, HP, Damage, Defense, Rewards (moedas, XP, XP de unidade, drops), Respawn Time, World, Boss.
- Spawners por área (mantêm `MaxEnemies`) e pontos de chefe; respawn pelo `RespawnTime`.
- Recompensas: inimigo comum → quem matou; chefes → todos que causaram ≥10% do HP.
- Chefes agressivos causam dano a jogadores próximos.
- Modelo: `ServerStorage.Assets.Enemies.<Id>` se existir; senão um placeholder colorido por tier.
Estado: **implementado e testado** (lógica). Visual 3D **não testado no Studio**.

## F. Worlds — `WorldService` + `MapService` (+ `Config/Worlds`)
5 mundos configuráveis (nome, ordem, custo, requisitos, banner, áreas de spawn, chefes, NPCs, recompensa de clear).
Desbloqueio em ordem com requisitos e custo; teleporte; recompensa única ao derrotar o chefe final.
`MapService` gera um mapa greybox jogável se não existir `Workspace.Worlds` (chão, spawn, NPCs com ProximityPrompt, marcadores, arenas de raid).
Estado: **implementado e testado** (lógica + geração do mapa em Lune). Aparência no Studio **não verificada**.

## G. Progression — `ProgressionService` + `BoostService`
Nível do jogador (curva `100 × nível^1.5`, máx. 150) com recompensas a cada 5/25 níveis; XP e nível de
unidades (máximo por raridade); evolução; upgrades permanentes (Damage, Yen, XP, Luck, EquipSlots,
UnitStorage); `BoostService` compõe todos os multiplicadores (upgrades × boosts × eventos × passes × bônus de unidades).
Estado: **implementado e testado**.

## H. Quests — `QuestService` + `AchievementService`
- Cadeia principal (12 quests) e diárias (3 por dia, sorteadas com semente dia+usuário, reset 00:00 UTC).
- Tipos: KillEnemies, KillBoss, Summon, EarnYen, UnlockWorld, ReachLevel, LevelUpUnits, EvolveUnit, FuseUnits, CompleteRaid — com filtros (inimigo, mundo, tier, banner, raid).
- Progresso dirigido por sinais dos outros serviços; resgate idempotente.
- Conquistas em níveis a partir de `Stats`.
Estado: **implementado e testado**.

## Raids e Eventos — `RaidService`, `EventService`
- Raids instanciadas (zona privada), ondas, chefe final, limite de tempo, cooldown, custo de entrada, recompensas; falha por tempo, morte ou saída.
- Eventos globais agendados (ex.: 2x Yen no fim de semana) ou iniciados por admin; modificadores multiplicativos.
Estado: **implementado e testado**. Raids são **solo** por enquanto (ver TODO).

## Shop — `ShopService`
Loja por moedas do jogo; Developer Products com `ProcessReceipt` deduplicado; Game Passes com perks
(multiplicadores, slots extras). IDs de Robux = 0 até serem criados no site do Roblox.
Estado: loja por moedas **testada**; Robux **implementado, não testado** (precisa de IDs reais).

## Settings / Admin — `SettingsService`, `AdminService`
Configurações validadas por esquema (tipo e faixa). Comandos admin (give, unit, item, xp, level, unlockall,
event, spawn, resetquests) disponíveis no Studio e para UserIds em `GameConfig.Admin.UserIds`; usam os
serviços normais (mesmas validações).
Estado: **implementado e testado**.

## K. UI — `Client/Controllers/*`
Interfaces criadas por código (`UI/Components` + `UI/Theme`), cada uma com controller próprio:
HUD (moedas, nível/XP, mundo, boosts/eventos, auto-ataque), Inventário (grade, ordenação, venda em massa,
modo fusão, aba de itens), Detalhes da Unidade (stats, habilidades, comparação, equipar, travar, vender,
fundir, evoluir, poções, reroll), Summon (banners, taxas, pity, x1/x10, revelação), Mundos, Quests/Conquistas,
Loja, Upgrades, Configurações, Raids (lista + HUD da raid), Notificações, Indicadores de dano, Barras de vida,
Alvo por clique/toque, Unidades seguindo o jogador, NPCs (ProximityPrompt → janela).
Atalhos: I (unidades), Q (quests), M (mundos), B (loja), X / botão direito (limpar alvo).
Estado: **implementado, compila e passa no linter; não testado visualmente** (requer Studio).
