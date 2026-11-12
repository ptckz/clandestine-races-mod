# ClandestineRaces (RDR2, single-player)

Mod de corridas clandestinas de cavalo com apostas, escrito em Lua para o RedLua.

## Estrutura

- `Scripts/ClandestineRaces.lua`: o script. O RedLua só carrega arquivos `.lua` soltos na pasta `RedLua\Scripts\`. Pastas com `main.lua` não são carregadas (testado em 11/11/2026).
- `.gitignore`: exclui logs e arquivos gerados em runtime.

## Status

- Etapa 0 concluída: RedLua v0.6.4 carrega o script, `OnLoad` é executado e o log é gravado (testado no jogo, 11/11/2026).
- Log do mod: `RedLua\ClandestineRaces.log`. Log do RedLua: `RedLua\Run.log`.

## Instalação (para teste)

1. Instalar o RedLua v0.6.4 na pasta do jogo (`RedLua.asi`, `lua51.dll` e a pasta `RedLua`).
2. Ativar `"autorun": true` em `RedLua\Settings.json`.
3. Ativar o log de arquivo em `RedLua\Log.conf` (`TO_FILE = true`, `FILENAME = "RedLua\Run.log"`).
4. Copiar `Scripts\ClandestineRaces.lua` para `<pasta do jogo>\RedLua\Scripts\`.
5. Reiniciar o jogo e entrar no mundo.

## Natives confirmados (`RedLua\natives.json`)

Conferidos no arquivo instalado. Não usar nomes que não estejam nesta lista sem verificar antes.

| Uso | Native | Parâmetros | Retorno |
|---|---|---|---|
| Hash de modelo | `GET_HASH_KEY` | `const char*` | `Hash` |
| Carregar modelo | `REQUEST_MODEL`, `HAS_MODEL_LOADED`, `SET_MODEL_AS_NO_LONGER_NEEDED` | `Hash` | |
| Criar ped (jóquei, cavalo como ped) | `CREATE_PED` | `Hash, x, y, z, heading, isNetwork, bScriptHostPed, p7, p8` | `Ped` |
| Montar em animal | `TASK_MOUNT_ANIMAL` | `Ped, Ped mount, timer, seat, speed, style, ...` | |
| Mover ped | `TASK_GO_TO_COORD_ANY_MEANS` | `Ped, x, y, z, speed, Entity, p6, walkingStyle, p8` | |
| Posição | `GET_ENTITY_COORDS`, `SET_ENTITY_COORDS` | `Entity, ...` | `Vector3` |
| Distância | `GET_DISTANCE_BETWEEN_COORDS` | `x1,y1,z1,x2,y2,z2,useZ` | `float` |
| Jogador | `PLAYER_PED_ID`, `PLAYER_ID`, `GET_PLAYER_PED` | | |
| Dinheiro | `_MONEY_GET_CASH_BALANCE`, `_MONEY_DECREMENT_CASH_BALANCE`, `_MONEY_INCREMENT_CASH_BALANCE` | `amount` (e `addReason` no incremento) | `int` / `BOOL` |
| Procurado | `SET_PLAYER_WANTED_LEVEL` | `Player, int level, BOOL disableNoMission` | |
| Texto na tela | `_DISPLAY_TEXT`, `_SET_TEXT_COLOR` | `text, x, y` / `r, g, b, a` | |
| Retângulo na tela | `DRAW_RECT` | `x, y, w, h, r, g, b, a, p8, p9` | |
| Controles | `IS_CONTROL_JUST_PRESSED`, `GET_CONTROL_NORMAL` | `int control, Hash action` | `BOOL` / `float` |
| Limpeza | `DELETE_PED`, `SET_PED_AS_NO_LONGER_NEEDED`, `SET_ENTITY_AS_MISSION_ENTITY` | | |

Ainda não confirmados: escala e fonte do texto na tela (não encontrei natives com esses nomes). Se o painel de apostas precisar de texto maior, confirmar antes.

## Próximas etapas

Ver o plano em `C:\Users\PHILDEN\.claude\plans\eventual-brewing-walrus.md`.

Só para single-player. Não usar no modo online.
