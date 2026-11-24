# aeroplataform

Este repositório contém:

1. **Anime Fighters (Roblox)** — jogo em Luau/Rojo (`src/`, `default.project.json`, `tests/`, `docs/`).
2. **Plataforma Aero** — aplicação web Python/JS pré-existente (`app.py`, `services.py`, `index.html`, ...), não relacionada ao jogo.

## Anime Fighters — início rápido

```bash
rokit install          # Rojo, Lune, Selene, StyLua
lune run tests/run     # 167 testes automatizados (fora do Roblox)
selene src             # lint
rojo serve             # sincronizar com o Roblox Studio

# Preview da UI sem Studio (cliente real + servidor real, renderizado em HTML/PNG)
lune run tools/ui-preview/preview ui-preview-out
node tools/ui-preview/screenshot.js ui-preview-out
```

Documentação:
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — estrutura e decisões técnicas
- [docs/SYSTEMS.md](docs/SYSTEMS.md) — cada sistema, API e estado real
- [docs/STUDIO_SETUP.md](docs/STUDIO_SETUP.md) — o que precisa ser feito no Roblox Studio
- [docs/DEVELOPMENT_LOG.md](docs/DEVELOPMENT_LOG.md) — histórico
- [docs/TODO.md](docs/TODO.md) — pendências
