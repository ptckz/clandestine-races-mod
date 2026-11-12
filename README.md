# ClandestineRaces (RDR2, single-player)

Mod de corridas clandestinas de cavalo com apostas, escrito em Lua para o RedLua.

## Estrutura

- `Scripts/ClandestineRaces.lua`: o script. O RedLua só carrega arquivos `.lua` soltos na pasta `RedLua\Scripts\`. Pastas com `main.lua` não são carregadas (testado em 11/11/2026).
- `.gitignore`: exclui logs e arquivos gerados em runtime.

## Status

- Etapa 0 concluída: RedLua v0.6.4 carrega o script, `OnLoad` é executado e o log é gravado (testado no jogo).
- Log de teste: `RedLua\ClandestineRaces.log`.

## Instalação (para teste)

1. Instalar o RedLua v0.6.4 na pasta do jogo (`RedLua.asi`, `lua51.dll` e a pasta `RedLua`).
2. Ativar `"autorun": true` em `RedLua\Settings.json`.
3. Copiar `Scripts\ClandestineRaces.lua` para `<pasta do jogo>\RedLua\Scripts\`.
4. Reiniciar o jogo e entrar no mundo.

Só para single-player. Não usar no modo online.
