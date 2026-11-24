# TODO

Legenda: [Studio] exige Roblox Studio/site · [Código] pode ser feito na nuvem

## Jogo base (prioridade)
- [ ] [Studio] Jogar o loop no Studio e ajustar o ritmo: HP dos inimigos, Yen por kill, preço do orbe (100/280 ¥).
- [ ] [Studio/Arte] Modelos reais dos lutadores e inimigos do Mundo 1 (substituem os bonecos do `RigBuilder`).
- [ ] [Studio/Arte] Mapa do Mundo 1 feito à mão (`Workspace.Worlds.W1`), substituindo o greybox.
- [ ] [Código] Animações de ataque (hoje: avanço/recuo simples) e som de moedas/golpes.
- [ ] [Código] Depois de validado o loop, religar sistemas um a um em `Features.luau`.

## Antes de publicar
- [ ] [Studio] Sincronizar com Rojo e rodar o jogo; revisar a Output (ver `STUDIO_SETUP.md`).
- [ ] [Studio] Verificar visualmente todas as janelas (PC e celular). Ajustar tamanhos/escala para telas pequenas.
- [ ] [Studio] Ativar API Services e testar save/load real; definir `GameConfig.Data.StoreName` final.
- [ ] [Studio] Criar Developer Products / Game Passes e preencher IDs em `Config/Shop.luau`.
- [ ] [Código] Definir datas reais do evento de lançamento (`Config/Events.luau`, `EV_LaunchLuck`).
- [ ] [Código] Preencher `GameConfig.Admin.UserIds` com os UserIds dos administradores.
- [ ] [Código/Design] Balanceamento: custos de mundos, HP de inimigos, taxas de banner (planilha recomendada).

## UI
- [ ] [Studio] Conferir o preview contra o Studio real (fontes Gotham, tamanhos de texto em telas reais).
- [ ] [Código] Layouts dedicados para celular (no celular as janelas encolhem para ~60% e o texto fica pequeno).
- [ ] [Código/Arte] Ícones e retratos das unidades nos cards (hoje só texto).

## Conteúdo / arte
- [ ] [Studio] Mapas reais dos 5 mundos (`Workspace.Worlds.*`, ver convenções em `STUDIO_SETUP.md`).
- [ ] [Studio] Modelos de inimigos (`ServerStorage/Assets/Enemies/<Id>`) e unidades (`ReplicatedStorage/Assets/Units/<Id>`).
- [ ] [Studio] Animações de ataque/habilidade e VFX (hook: `UnitVisualController:PlayCast`).
- [ ] [Studio] Animação de summon (hook: `SummonController:PlayReveal`).
- [ ] [Studio] Ícones de itens/moedas (`Items.Icon`), sons e música (SoundGroups "Music"/"SFX" já respeitados).

## Funcionalidades futuras
- [ ] [Código] Raids em grupo (lobby/convite). O modelo de dados já suporta `Players` e `MaxPlayers`.
- [ ] [Código] Mostrar unidades de outros jogadores (replicar equipados via atributos; setting `ShowOtherUnits` já existe).
- [ ] [Código] Índice/coleção de unidades obtidas.
- [ ] [Código] Trocas entre jogadores (exige cuidado extra contra duplicação: transação dupla com locks).
- [ ] [Código] Códigos promocionais (usar `GrantRewards` com `OnceKey = "Code:<código>"`).
- [ ] [Código] Leaderboards (OrderedDataStore) de dano total / nível.
- [ ] [Código] Localização (strings da UI estão em inglês; centralizar em um módulo de textos).
- [ ] [Código] Analytics (AnalyticsService) para funil de progressão e economia.

## Técnico
- [ ] [Código] Rodar `selene` com a std oficial `roblox` quando houver acesso a `setup.rbxcdn.com`.
- [ ] [Código] Rodar `luau-analyze`/luau-lsp em modo strict (não disponível neste ambiente).
- [ ] [Studio] Medir desempenho com muitos jogadores/inimigos (MicroProfiler); ajustar `TickRate`/`MaxEnemies`.
- [ ] [Código] Backups periódicos do perfil (ex.: chave de snapshot diária) se o jogo crescer.
