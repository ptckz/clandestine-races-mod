# Natives confirmados (RedLua\natives.json)

Conferidos no `natives.json` do RedLua v0.6.4 instalado na pasta do jogo. Não usar nomes que não estejam nesta lista sem verificar antes.

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
