-- Adaptador de natives: único módulo que chama o jogo.
-- `api` é a API do RedLua: api.call(namespace, name, ...) e api.misc.iskeyjustup(vk, exclusive).

local natives = {}

-- Modelos usados no mod. Confirmar no jogo; se algum não existir, o log mostra qual falhou.
natives.HORSE_MODEL = "A_C_HORSE_ARABIAN_WHITE"
natives.COP_MODEL = "S_M_M_ARMYSOLDIER_01"

function natives.new(api)
	local n = {}
	local call = api.call

	-- Acesso direto para a sonda de diagnóstico.
	n.call = call
	n.new = api.new

	-- O RedLua devolve valores de 64 bits com lixo na parte alta (ex.: 0x7FF6...). O hash real são os
	-- 32 bits baixos (confirmado: bate com o joaat do nome). Sempre mascarar antes de usar.
	local function mask32(v)
		local num = tonumber(v)
		if num == nil then
			return v
		end
		return math.floor(num % 4294967296)
	end
	n.mask32 = mask32

	function n.hash(text)
		return mask32(call("MISC", "GET_HASH_KEY", text))
	end

	-- Modelo (hash de 32 bits) de uma entidade.
	function n.entityModel(entity)
		return mask32(call("ENTITY", "GET_ENTITY_MODEL", entity))
	end

	function n.exists(entity)
		return call("ENTITY", "DOES_ENTITY_EXIST", entity) and true or false
	end

	-- O RedLua converte argumentos numéricos via float (24 bits de precisão), o que corrompe hashes de
	-- 32 bits (confirmado no código-fonte do RedLua, native_prepare_arg). Um objeto nativo do tipo Hash
	-- guarda o valor exato e é entregue ao native sem passar por float.
	local function hashArg(hash)
		local ok, obj = pcall(function()
			local box = api.new("Hash", 1)
			box[0] = hash
			return box
		end)
		if ok then
			return obj
		end
		n.hashError = tostring(obj)
		return hash
	end

	-- Diz se o objeto Hash exato pode ser criado neste RedLua.
	function n.hashMode()
		local ok, err = pcall(function()
			local box = api.new("Hash", 1)
			box[0] = 2231677610
		end)
		return ok, err
	end

	-- Cria um ped a partir do hash do modelo. Se o modelo ainda não carregou, pede e devolve nil.
	function n.createPedFromHash(hash, x, y, z, heading)
		if not call("STREAMING", "HAS_MODEL_LOADED", hashArg(hash)) then
			call("STREAMING", "REQUEST_MODEL", hashArg(hash), false)
			return nil
		end
		local ped = call("PED", "CREATE_PED", hashArg(hash), x, y, z, heading or 0.0, false, false, false, false)
		if ped ~= nil then
			n.dress(ped)
		end
		return ped
	end

	-- Coloca uma entidade (e quem está montado nela) em uma posição e direção.
	function n.place(entity, x, y, z, heading)
		call("ENTITY", "_SET_ENTITY_COORDS_AND_HEADING", entity, x, y, z, heading, false, false, false)
	end

	-- Peds recém-criados ficam sem outfit (invisíveis) até o jogo aplicar um; documentado no natives.json.
	function n.dress(ped)
		call("PED", "_SET_RANDOM_OUTFIT_VARIATION", ped, true)
	end

	function n.requestModel(hash)
		n.createPedFromHashRequest(hash)
	end

	function n.isOnMount(ped)
		return call("PED", "IS_PED_ON_MOUNT", ped) and true or false
	end

	-- Cria o cavaleiro já sentado no cavalo. Chamada usada por um projeto real de RDR2 (RDR2-Personal-Dog):
	-- CREATE_PED_ON_MOUNT(horse, model, seatIndex, 1, 1, 0, 0). Seat -1 = sela principal.
	-- Se o modelo ainda não carregou, pede e devolve nil.
	function n.createRiderOn(horse, hash)
		if not call("STREAMING", "HAS_MODEL_LOADED", hashArg(hash)) then
			call("STREAMING", "REQUEST_MODEL", hashArg(hash), false)
			return nil
		end
		local ped = call("PED", "CREATE_PED_ON_MOUNT", horse, hashArg(hash), -1, true, true, false, false)
		if ped ~= nil then
			n.dress(ped)
		end
		return ped
	end

	-- Impede o cavaleiro de reagir a eventos e de cair do cavalo durante a corrida.
	function n.configureRider(rider)
		call("PED", "SET_BLOCKING_OF_NON_TEMPORARY_EVENTS", rider, true)
		call("PED", "SET_PED_CAN_BE_KNOCKED_OFF_VEHICLE", rider, 1)
	end

	-- Só pede o modelo (sem criar nada).
	function n.createPedFromHashRequest(hash)
		call("STREAMING", "REQUEST_MODEL", hashArg(hash), false)
	end

	function n.createPed(modelName, x, y, z, heading)
		return n.createPedFromHash(n.hash(modelName), x, y, z, heading)
	end

	-- Cavalo em que o jogador está montado (ou o último que montou). nil se não houver.
	function n.playerMount()
		local ped = call("PED", "GET_MOUNT", call("PLAYER", "PLAYER_PED_ID"))
		if ped ~= nil and n.exists(ped) then
			return ped
		end
		return nil
	end

	-- Ponto da estrada mais próxima, ou nil. Usa GET_CLOSEST_VEHICLE_NODE (nodeType 1 = qualquer caminho);
	-- no RDR2 o comportamento ainda não está documentado, então qualquer falha devolve nil.
	function n.closestRoad(x, y, z)
		local ok, result = pcall(function()
			local out = api.new("Vector3", 1)
			local found = call("PATHFIND", "GET_CLOSEST_VEHICLE_NODE", x, y, z, out, 1, 3.0, 0.0)
			if not found then
				return nil
			end
			local p = n.toPoint(out)
			if p == nil or (p.x == 0 and p.y == 0 and p.z == 0) then
				return nil
			end
			return p
		end)
		if ok then
			return result
		end
		return nil
	end

	-- Deixa o NPC protegido: não reage a eventos, não morre, não cai e não some do mundo.
	function n.protect(ped)
		call("ENTITY", "SET_ENTITY_AS_MISSION_ENTITY", ped, true, true)
		call("PED", "SET_BLOCKING_OF_NON_TEMPORARY_EVENTS", ped, true)
		call("ENTITY", "SET_ENTITY_INVINCIBLE", ped, true)
		call("PED", "SET_PED_CAN_RAGDOLL", ped, false)
	end

	-- Fica parado (tempo -1 = sem prazo).
	function n.stand(ped)
		call("TASK", "TASK_STAND_STILL", ped, -1)
	end

	-- Vira o NPC para olhar para outra entidade (usado ao começar a conversa).
	function n.faceEntity(ped, target)
		call("TASK", "TASK_TURN_PED_TO_FACE_ENTITY", ped, target, 3000, 0.0, 0.0, 0.0)
	end

	function n.deletePed(ped)
		call("PED", "DELETE_PED", ped)
	end

	function n.markCop(ped)
		call("PED", "SET_PED_AS_COP", ped, true)
	end

	-- Manda o policial atacar (perseguir) o alvo.
	function n.chase(cop, target)
		call("TASK", "TASK_COMBAT_PED", cop, target, 0, 16)
	end

	-- Manda um ped (ou o cavaleiro de um cavalo) ir até um ponto. Só parâmetros simples: o RedLua rejeita
	-- número em parâmetros Entity/Any (TASK_GO_TO_COORD_ANY_MEANS falhava por isso).
	-- mode "straight" anda em linha reta; o padrão segue a navmesh (contorna obstáculos).
	function n.goTo(ped, x, y, z, speed, mode, refHorse)
		if mode == "straight" then
			call("TASK", "TASK_GO_STRAIGHT_TO_COORD", ped, x, y, z, speed, -1, 40000.0, 0.5, 0)
		elseif mode == "navmesh" then
			call("TASK", "TASK_FOLLOW_NAV_MESH_TO_COORD", ped, x, y, z, speed, -1, 2.0, 0, -1.0)
		else
			-- Caminho do próprio jogo (pathfinding). O parâmetro Entity não aceita número nem nil no RedLua;
			-- GET_MOUNT de um cavalo (que não está montado em nada) devolve um Ped nulo, aceito como Entity.
			local nullEntity = call("PED", "GET_MOUNT", refHorse or ped)
			call("TASK", "TASK_GO_TO_COORD_ANY_MEANS", ped, x, y, z, speed, nullEntity, false, 0, -1.0)
		end
	end

	-- Faz o ped ficar parado por alguns segundos (usado quando o rival está longe demais de você).
	function n.hold(ped)
		call("TASK", "TASK_STAND_STILL", ped, 2500)
	end

	function n.entityCoords(entity)
		return call("ENTITY", "GET_ENTITY_COORDS", entity, true, true)
	end

	function n.playerPed()
		return call("PLAYER", "PLAYER_PED_ID")
	end

	-- Blip no mapa. Padrão do RedM: BLIP_ADD_FOR_COORDS com um estilo (e, se quiser, SET_BLIP_SPRITE).
	-- Estilos da lista do RDR2: BLIP_STYLE_OBJECTIVE, BLIP_STYLE_WAYPOINT, BLIP_STYLE_MISSION, BLIP_STYLE_RACE_FINISH.
	function n.addBlip(x, y, z, opts)
		opts = opts or {}
		local blip = call("MAP", "BLIP_ADD_FOR_COORDS", hashArg(n.hash(opts.style or "BLIP_STYLE_MISSION")), x, y, z)
		if opts.sprite ~= nil then
			call("MAP", "SET_BLIP_SPRITE", blip, hashArg(n.hash(opts.sprite)), true)
		end
		if opts.name ~= nil then
			pcall(function()
				local vs = call("MISC", "VAR_STRING", 10, "LITERAL_STRING", opts.name)
				call("MAP", "_SET_BLIP_NAME", blip, vs)
			end)
		end
		return blip
	end

	-- Confere se o blip existe e onde está (para o log). Devolve ok, existe, noMinimapa, ponto.
	function n.blipInfo(blip)
		local ok, exists, onMap, coords = pcall(function()
			return call("MAP", "DOES_BLIP_EXIST", blip), call("MAP", "IS_BLIP_ON_MINIMAP", blip), call("MAP", "GET_BLIP_COORDS", blip)
		end)
		if not ok then
			return false, tostring(exists)
		end
		return true, exists and true or false, onMap and true or false, n.toPoint(coords)
	end

	-- Rota GPS no mapa passando pelos pontos (o "alvo" da corrida). Devolve ok, erro.
	function n.startRoute(points)
		return pcall(function()
			call("MAP", "CLEAR_GPS_MULTI_ROUTE")
			call("MAP", "START_GPS_MULTI_ROUTE", hashArg(n.hash("COLOR_YELLOW")), true, false)
			for _, p in ipairs(points) do
				call("MAP", "ADD_POINT_TO_GPS_MULTI_ROUTE", p.x, p.y, p.z, false)
			end
			call("MAP", "SET_GPS_MULTI_ROUTE_RENDER", true)
		end)
	end

	function n.clearRoute()
		pcall(function() call("MAP", "CLEAR_GPS_MULTI_ROUTE") end)
	end

	-- Altura do chão em (x, y), procurando de cima para baixo a partir de zHint + 40. nil se não achar.
	function n.groundZ(x, y, zHint)
		local ok, res = pcall(function()
			local box = api.new("float", 1)
			local found = call("MISC", "GET_GROUND_Z_FOR_3D_COORD", x, y, zHint + 40.0, box, false)
			if found then
				return box[0]
			end
			return nil
		end)
		if ok then
			return res
		end
		n.groundError = tostring(res)
		return nil
	end

	function n.removeBlip(blip)
		call("MAP", "REMOVE_BLIP", blip)
	end

	function n.setWanted(stars)
		local id = call("PLAYER", "PLAYER_ID")
		call("PLAYER", "SET_PLAYER_WANTED_LEVEL", id, stars, false)
	end

	function n.getWanted()
		return call("PLAYER", "GET_PLAYER_WANTED_LEVEL", call("PLAYER", "PLAYER_ID"))
	end

	function n.clearWanted()
		call("PLAYER", "CLEAR_PLAYER_WANTED_LEVEL", call("PLAYER", "PLAYER_ID"))
	end

	function n.getMoney()
		return call("MONEY", "_MONEY_GET_CASH_BALANCE")
	end

	-- Tecla pressionada neste tick (código de tecla do Windows, ex.: 0x77 = F8).
	-- Uma tecla só conta uma vez: iskeyjustup pode devolver verdadeiro em vários ticks seguidos.
	-- Depois de aceitar um pressionamento, a mesma tecla fica bloqueada por KEY_COOLDOWN segundos.
	local KEY_COOLDOWN = 0.5
	local lastAccepted = {}
	function n.keyJustPressed(vk)
		if not api.misc.iskeyjustup(vk, false) then
			return false
		end
		local t = os.clock()
		local last = lastAccepted[vk]
		if last ~= nil and t - last < KEY_COOLDOWN then
			return false
		end
		lastAccepted[vk] = t
		return true
	end

	-- Texto na tela, validado no jogo: x, y em fração da tela (0 a 1), canto superior esquerdo.
	-- Usa _BG_DISPLAY_TEXT; o antigo _DISPLAY_TEXT não faz nada desde a build 1436.
	function n.drawText(text, x, y, scale, r, g, b, a)
		n.bgText(text, x, y, scale or 0.4, r, g, b, a)
	end

	-- Converte o retorno de um native de posição em {x, y, z}. Devolve nil se não der.
	function n.toPoint(v)
		if v == nil then
			return nil
		end
		local ok, x, y, z = pcall(function() return v.x, v.y, v.z end)
		if ok and type(x) == "number" and type(y) == "number" and type(z) == "number" then
			return { x = x, y = y, z = z }
		end
		return nil
	end

	-- Distância 3D entre dois pontos {x, y, z}.
	function n.distance(a, b)
		return call("MISC", "GET_DISTANCE_BETWEEN_COORDS", a.x, a.y, a.z, b.x, b.y, b.z, true)
	end

	-- Texto com o native atual (_BG_DISPLAY_TEXT + VAR_STRING), com escala e cor. Em validação.
	function n.bgText(text, x, y, scale, r, g, b, a)
		local vs = call("MISC", "VAR_STRING", 10, "LITERAL_STRING", text)
		call("UIDEBUG", "_BG_SET_TEXT_SCALE", scale, scale)
		call("UIDEBUG", "_BG_SET_TEXT_COLOR", r or 255, g or 255, b or 255, a or 255)
		call("UIDEBUG", "_BG_DISPLAY_TEXT", vs, x, y)
	end

	function n.drawRect(x, y, w, h, r, g, b, a)
		call("GRAPHICS", "DRAW_RECT", x, y, w, h, r, g, b, a, false, false)
	end

	return n
end

return natives
