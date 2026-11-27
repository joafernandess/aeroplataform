# aeroplataform

Este repositório contém:

1. **Anime Fighters (Roblox)** — jogo em Luau/Rojo (`src/`, `default.project.json`, `tests/`, `docs/`).
2. **Plataforma Aero** — aplicação web Python/JS pré-existente (`app.py`, `services.py`, `index.html`, ...), não relacionada ao jogo.

## Anime Fighters — jogo base

O foco atual é o **jogo base**: o loop essencial do gênero no Mundo 1 — andar, clicar num inimigo, ver os
lutadores correrem e baterem, coletar as moedas de Yen que voam até você, abrir o orbe de invocação (x1/x3) e
equipar lutadores melhores. Todos os outros sistemas já implementados (mundos 2-5, quests, raids, loja,
upgrades, eventos, itens, fusão, evolução, traits...) estão desligados em
`src/ReplicatedStorage/Shared/Config/Features.luau` e voltam com uma chave.

## Início rápido

```bash
rokit install          # Rojo, Lune, Selene, StyLua
lune run tests/run     # 237 testes automatizados (fora do Roblox)
selene src             # lint
rojo serve             # sincronizar com o Roblox Studio

# Preview sem Studio: UI real (cliente + servidor) e cena 3D do Mundo 1 com o mapa gerado pelo código
(cd tools/ui-preview && npm install)
lune run tools/ui-preview/preview ui-preview-out
lune run tools/ui-preview/scene ui-preview-out tools/ui-preview/node_modules/three/build/three.min.js
node tools/ui-preview/screenshot.js ui-preview-out
```

Documentação:
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — estrutura e decisões técnicas
- [docs/SYSTEMS.md](docs/SYSTEMS.md) — cada sistema, API e estado real
- [docs/STUDIO_SETUP.md](docs/STUDIO_SETUP.md) — o que precisa ser feito no Roblox Studio
- [docs/DEVELOPMENT_LOG.md](docs/DEVELOPMENT_LOG.md) — histórico
- [docs/TODO.md](docs/TODO.md) — pendências
