-- ClandestineRaces: locais de largada com negociador (NPC), menu de admin, corrida, procura e perseguição policial.
-- Módulos em RedLua\Libs\clandestine\. Log em RedLua\ClandestineRaces.log.

local course = require("clandestine.course")
local spots = require("clandestine.spots")
local wanted = require("clandestine.wanted")
local pursuit = require("clandestine.pursuit")
local natives = require("clandestine.natives")
local route = require("clandestine.route")
local menu = require("clandestine.menu")
local routes = require("clandestine.routes")
local dialogue = require("clandestine.dialogue")

local LOG_FILE = "RedLua\\ClandestineRaces.log"

-- Teclas (códigos do Windows).
local KEY_TOGGLE = 0x77 -- F8: abre/fecha o menu de admin
local KEY_STOP = 0x78 -- F9: encerra a corrida em andamento
local KEY_DIAG = 0x79 -- F10: liga/desliga o diagnóstico de texto
local KEY_PROBE = 0x7A -- F11: sonda que registra no log o que os natives devolvem
local KEY_NEGOTIATE = 0x45 -- E: inicia a corrida com o NPC do local
local KEY_UP, KEY_DOWN, KEY_ENTER, KEY_BACK = 0x26, 0x28, 0x0D, 0x08

local WANTED_CFG = { escalateEverySeconds = 30, clearOnFinish = true }
local PURSUIT_CFG = { pursuersPerStar = 1, maxPursuers = 4, maxRange = 400 }
local CHECKPOINT_RADIUS = 20.0 -- pontos marcados à mão: margem maior que a de pontos sorteados
local ROUTES_FILE = "RedLua\\ClandestineRoutes.dat"
local START_MAX_DISTANCE = 150 -- a que distância da largada você pode estar para iniciar a corrida
local RACE_TIMEOUT_SECONDS = 360 -- 6 minutos no máximo de corrida e perseguição
local ROUTE_CFG = { count = 5, minStep = 250, maxStep = 600 } -- percurso sorteado a cada corrida
local HORSES_PER_RACE = 3

-- Preset aleatório: a cada corrida, cada rival recebe um cavalo e um cavaleiro sorteados.
-- Nomes vistos em arquivos de mods do RDR2; "OWN" copia o modelo do cavalo do próprio jogador.
local PRESET = {
	horses = { "A_C_HORSE_ARABIAN_WHITE", "A_C_HORSE_MUSTANG_TIGERSTRIPEDBAY", "OWN" },
	riders = { "A_M_M_VALTOWNFOLK_01", "A_M_M_VALTOWNFOLK_02", "A_M_M_VALFARMER_01", "A_M_M_VALLABORER_01" },
}
local PREPARE_TIMEOUT_SECONDS = 12

-- Planejador de rota dos rivais: olha a altura do chão à frente e evita penhascos e buracos.
local PLAN_OFFSETS = { 0, 20, -20, 40, -40, 60, -60, 90, -90, 130, -130 } -- graus em relação ao destino
local PLAN_STEP = 10 -- metros entre as amostras de chão
local PLAN_SAMPLES = 4 -- amostras por direção (40 m à frente)
local PLAN_MAX_DZ = 6.0 -- diferença máxima de altura entre amostras seguidas (m)
local PLAN_INTERVAL = 1.0 -- segundos entre replanejamentos
-- Rédea: o terreno e o caminho só ficam carregados perto de você. Rival mais longe que LEASH_FAR e à frente espera.
local LEASH_FAR = 150
local LEASH_NEAR = 90

-- Policiais (nomes da lista de modelos do RDR2): chegam a cavalo, de trás da largada.
local COP_PRESET = { "S_M_M_DISPATCHLAWRURAL_01", "S_M_M_MARSHALLSRURAL_01", "A_M_M_VALDEPUTYRESIDENT_01" }
local COP_SPAWN_DISTANCE = 45 -- metros atrás da largada
local GRID_SPACING = 2.5 -- metros entre os cavalos alinhados na largada
local MOUNT_WAIT_SECONDS = 4
local COUNTDOWN_SECONDS = 3

local function pickOne(list)
	return list[math.random(1, #list)]
end
local NEGOTIATE_RANGE = 3.0
local NEGOTIATOR_MODEL = "A_M_M_VALTOWNFOLK_01" -- nome existe nos arquivos do jogo; o hash agora é mascarado em 32 bits

local S = nil -- estado de runtime, criado no OnLoad

local function log(msg)
	print("[ClandestineRaces] " .. msg)
	local f = io.open(LOG_FILE, "a")
	if f then
		f:write(os.date("%H:%M:%S") .. " " .. msg .. "\n")
		f:close()
	end
end

local function now()
	return os.time()
end

-- Posição do jogador como {x, y, z}, ou nil se o native não devolver uma posição legível.
local function playerPoint()
	local raw = S.N.entityCoords(S.N.playerPed())
	local p = S.N.toPoint(raw)
	if p == nil and not S.posLogged then
		S.posLogged = true
		log("não consegui ler a posição do jogador; tipo do retorno = " .. type(raw))
	end
	return p
end

local function say(text)
	S.message = text
	S.messageUntil = now() + 4
end

-- ---------------------------------------------------------------- negociador (NPC de cada local)

-- Mantém o negociador de cada largada sempre no lugar: cria, protege, recria se sumir e recoloca se sair do ponto.
local function syncNegotiators()
	for _, spot in ipairs(spots.list(S.store)) do
		local ped = S.negotiators[spot.id]
		if ped ~= nil and not S.N.exists(ped) then
			S.negotiators[spot.id] = nil
			ped = nil
			log("o negociador de " .. spot.name .. " sumiu; recriando")
		end
		if ped == nil then
			local created = S.N.createPed(NEGOTIATOR_MODEL, spot.point.x, spot.point.y, spot.point.z, 0.0)
			if created ~= nil then
				S.N.protect(created)
				S.N.stand(created)
				S.negotiators[spot.id] = created
				log("negociador criado e parado em " .. spot.name)
			else
				S.negoWaitStart = S.negoWaitStart or os.clock()
				if not S.negotiatorWaitLogged then
					S.negotiatorWaitLogged = true
					log("modelo " .. NEGOTIATOR_MODEL .. " pedido; aguardando carregar")
				elseif os.clock() - S.negoWaitStart > 5 and not S.negoTimeoutLogged then
					S.negoTimeoutLogged = true
					log("modelo " .. NEGOTIATOR_MODEL .. " não carregou em 5 s")
				end
			end
		end
	end

	-- A cada 2 s: se o negociador saiu do ponto, volta para ele; reaplica o "ficar parado".
	if os.clock() - (S.anchorAt or 0) >= 2 then
		S.anchorAt = os.clock()
		for _, spot in ipairs(spots.list(S.store)) do
			local ped = S.negotiators[spot.id]
			if ped ~= nil then
				local p = S.N.toPoint(S.N.entityCoords(ped))
				if p ~= nil and course.distance2d(p, spot.point) > 2.5 then
					S.N.place(ped, spot.point.x, spot.point.y, spot.point.z, 0.0)
					log("o negociador de " .. spot.name .. " saiu do ponto; reposicionado")
				end
				if S.dlg == nil then
					S.N.stand(ped)
				end
			end
		end
	end
end

-- Local cujo negociador está ao alcance do jogador, ou nil.
local function nearbyNegotiatorSpot()
	local pp = playerPoint()
	if pp == nil then
		return nil
	end
	for _, spot in ipairs(spots.list(S.store)) do
		if S.negotiators[spot.id] ~= nil and S.N.distance(pp, spot.point) <= NEGOTIATE_RANGE then
			return spot
		end
	end
	return nil
end

-- ---------------------------------------------------------------- ações

-- Estilos de blip candidatos. Em vez de adivinhar, o mod cria cada um na sua posição, pergunta ao jogo qual aparece
-- no minimapa (IS_BLIP_ON_MINIMAP) e passa a usar o primeiro que aparecer.
local BLIP_CANDIDATES = {
	{ style = "BLIP_STYLE_OBJECTIVE" },
	{ style = "BLIP_STYLE_OBJECTIVE", sprite = "blip_objective" },
	{ style = "BLIP_STYLE_WAYPOINT" },
	{ style = "BLIP_STYLE_WAYPOINT", sprite = "blip_code_waypoint" },
	{ style = "BLIP_STYLE_MISSION" },
	{ style = "BLIP_STYLE_CHECKPOINT_CHALLENGE" },
	{ style = "BLIP_STYLE_RACE_FINISH" },
	{ style = "BLIP_STYLE_SHOP", sprite = "blip_objective" },
	{ style = "BLIP_STYLE_SHOP", sprite = "blip_ambient_horse" },
}

local function discoverBlipStyle()
	if S.blipChoice ~= nil then
		return
	end
	local here = playerPoint()
	if here == nil then
		S.blipChoice = BLIP_CANDIDATES[1]
		return
	end
	for _, c in ipairs(BLIP_CANDIDATES) do
		local b = S.N.addBlip(here.x, here.y, here.z, c)
		local okb, exists, onMap = S.N.blipInfo(b)
		log("teste de blip " .. c.style .. (c.sprite and (" + " .. c.sprite) or "") .. ": existe=" .. tostring(exists) .. " minimapa=" .. tostring(onMap))
		S.N.removeBlip(b)
		if S.blipChoice == nil and okb and exists and onMap then
			S.blipChoice = c
		end
	end
	if S.blipChoice == nil then
		S.blipChoice = BLIP_CANDIDATES[1]
		log("nenhum estilo apareceu no minimapa; usando o primeiro da lista")
	else
		log("estilo de blip escolhido: " .. S.blipChoice.style .. (S.blipChoice.sprite and (" + " .. S.blipChoice.sprite) or ""))
	end
end

local function blipOpts(name)
	local c = S.blipChoice or BLIP_CANDIDATES[1]
	return { style = c.style, sprite = c.sprite, name = name }
end

local function blipFor(spot)
	if S.blips[spot.id] == nil then
		S.blips[spot.id] = S.N.addBlip(spot.point.x, spot.point.y, spot.point.z, { style = "BLIP_STYLE_MISSION", name = "Corrida clandestina" })
	end
end

local function dropBlip(id)
	if S.blips[id] ~= nil then
		S.N.removeBlip(S.blips[id])
		S.blips[id] = nil
	end
end

local function dropNegotiator(id)
	if S.negotiators[id] ~= nil then
		S.N.deletePed(S.negotiators[id])
		S.negotiators[id] = nil
	end
end

local function clearRace(reason)
	if S.race == nil then
		return
	end
	for _, r in ipairs(S.race.horses) do
		if not r.own then
			if r.rider ~= nil then
				S.N.deletePed(r.rider)
			end
			S.N.deletePed(r.ped)
		end
	end
	for _, c in ipairs(S.race.cops) do
		if c.rider ~= nil then
			S.N.deletePed(c.rider)
		end
		S.N.deletePed(c.ped)
	end
	local pend = S.race.copPending
	if pend ~= nil then
		if pend.rider ~= nil then
			S.N.deletePed(pend.rider)
		end
		if pend.horse ~= nil then
			S.N.deletePed(pend.horse)
		end
	end
	for _, b in ipairs(S.race.blips or {}) do
		S.N.removeBlip(b)
	end
	for _, b in pairs(S.race.cpBlips or {}) do
		S.N.removeBlip(b)
	end
	S.N.clearRoute()
	wanted.stopRace(S.wanted)
	S.N.clearWanted()
	log("corrida encerrada: " .. reason)
	S.race = nil
end

local function startRace(spot)
	if spot == nil then
		say("Nenhum local selecionado.")
		return
	end
	if S.race ~= nil or S.starting ~= nil then
		say("Já existe uma corrida em andamento ou em preparo.")
		return
	end

	-- Seu cavalo: é o corredor principal. Os rivais são cópias do modelo dele.
	local mount = S.N.playerMount()
	if mount == nil then
		say("Monte no seu cavalo para correr.")
		log("corrida não iniciada: o jogador não está montado")
		return
	end
	local modelHash = S.N.entityModel(mount)
	local here = playerPoint()
	if here == nil then
		say("Não consegui ler sua posição.")
		return
	end

	-- A rota define os pontos: largada, passagens obrigatórias e chegada, nesta ordem.
	local rt = routeById(spot.routeId)
	if rt == nil then
		say("Esta largada não tem rota.")
		return
	end
	if not routes.isComplete(rt) then
		local marked, total = routes.progress(rt)
		say("Rota incompleta (" .. marked .. "/" .. total .. "): marque os pontos em Rotas.")
		log("corrida não iniciada: rota '" .. rt.name .. "' incompleta (" .. marked .. "/" .. total .. ")")
		return
	end
	local points = routes.points(rt)
	local start = points[1]
	local away = course.distance2d(here, start)
	if away > START_MAX_DISTANCE then
		say(string.format("Vá até a largada (%s): você está a %.0f m.", rt.slots[1].name, away))
		log(string.format("corrida não iniciada: a %.0f m da largada", away))
		return
	end
	log("rota '" .. rt.name .. "': " .. #points .. " pontos fixos")
	local c = course.new(points, CHECKPOINT_RADIUS)

	-- Sorteia o preset de cada rival e pede os modelos; a criação acontece nos próximos ticks.
	local rivals = {}
	for i = 1, HORSES_PER_RACE do
		local horseName = pickOne(PRESET.horses)
		local riderName = pickOne(PRESET.riders)
		local horseHash = (horseName == "OWN") and modelHash or S.N.hash(horseName)
		local riderHash = S.N.hash(riderName)
		S.N.requestModel(horseHash)
		S.N.requestModel(riderHash)
		rivals[i] = {
			id = "H" .. i, horseName = horseName, riderName = riderName,
			horseHash = horseHash, riderHash = riderHash,
			x = start.x + i * 3, y = start.y, z = start.z,
		}
		log("rival H" .. i .. ": cavalo " .. horseName .. " + cavaleiro " .. riderName)
	end
	S.starting = { spot = spot, start = start, points = points, course = c, mount = mount, rivals = rivals, modelHash = modelHash, since = os.clock() }
	say("Preparando a corrida...")
end

local function cancelStarting(reason)
	local st = S.starting
	if st == nil then
		return
	end
	for _, rv in ipairs(st.rivals) do
		if rv.rider ~= nil then S.N.deletePed(rv.rider) end
		if rv.horse ~= nil then S.N.deletePed(rv.horse) end
	end
	S.starting = nil
	log("preparo da corrida cancelado: " .. reason)
end

-- Cria os rivais conforme os modelos carregam e, quando todos estiverem prontos, começa a corrida.
local function tickStarting()
	local st = S.starting
	if st == nil then
		return
	end
	local timedOut = os.clock() - st.since > PREPARE_TIMEOUT_SECONDS
	local missingHorse = false
	local ready = true
	for _, rv in ipairs(st.rivals) do
		if rv.horse == nil then
			rv.horse = S.N.createPedFromHash(rv.horseHash, rv.x, rv.y, rv.z, 0.0)
		end
		if rv.horse == nil then
			missingHorse = true
			ready = false
		elseif rv.rider == nil and not rv.riderFailed then
			local rider = S.N.createRiderOn(rv.horse, rv.riderHash)
			if rider ~= nil then
				rv.rider = rider
				S.N.configureRider(rider)
			elseif timedOut then
				rv.riderFailed = true
				log("cavaleiro " .. rv.riderName .. " não carregou; " .. rv.id .. " corre sem cavaleiro")
			else
				ready = false
			end
		end
	end
	if timedOut and missingHorse then
		for _, rv in ipairs(st.rivals) do
			if rv.horse == nil then
				log("cavalo " .. rv.horseName .. " não carregou em " .. PREPARE_TIMEOUT_SECONDS .. " s")
			end
		end
		say("Não consegui carregar os cavalos rivais.")
		cancelStarting("modelos de cavalo não carregaram")
		return
	end
	if not ready then
		return
	end

	local horses, racers = { { id = "VOCE", ped = st.mount, own = true } }, { course.newRacer("VOCE") }
	for _, rv in ipairs(st.rivals) do
		horses[#horses + 1] = { id = rv.id, ped = rv.horse, rider = rv.rider, speed = 2.6 + math.random() * 0.6, mode = "anymeans" }
		racers[#racers + 1] = course.newRacer(rv.id)
	end
	-- O ponto de largada é o primeiro da lista: todos já começam rumo ao segundo.
	for _, racer in ipairs(racers) do
		racer.nextIndex = 2
	end
	S.race = {
		spot = st.spot,
		start = st.start,
		modelHash = st.modelHash,
		course = st.course,
		racers = racers,
		horses = horses,
		cops = {},
		startedAt = now(),
		phase = "grid",
	}
	local finish = st.course.checkpoints[#st.course.checkpoints]
	discoverBlipStyle()
	S.race.blips = {
		S.N.addBlip(st.start.x, st.start.y, st.start.z, blipOpts("Largada")),
		S.N.addBlip(finish.x, finish.y, finish.z, blipOpts("Chegada")),
	}
	log(string.format("blips: largada %.0f, %.0f | chegada %.0f, %.0f", st.start.x, st.start.y, finish.x, finish.y))
	for i, b in ipairs(S.race.blips) do
		local okb, exists, onMap, p = S.N.blipInfo(b)
		log("blip " .. (i == 1 and "largada" or "chegada") .. ": ok=" .. tostring(okb) .. " existe=" .. tostring(exists) .. " minimapa=" .. tostring(onMap) .. (p and string.format(" em %.0f, %.0f", p.x, p.y) or ""))
	end
	-- Checkpoints obrigatórios: um blip para cada ponto intermediário (os índices 2 até o penúltimo).
	S.race.cpBlips = {}
	for i = 2, #st.points - 1 do
		local p = st.points[i]
		S.race.cpBlips[i] = S.N.addBlip(p.x, p.y, p.z, blipOpts("Checkpoint " .. (i - 1)))
	end
	log("checkpoints obrigatórios no mapa: " .. (#st.points - 2) .. " + chegada")
	if S.race.cpBlips[2] ~= nil then
		local okc, existsC, onMapC = S.N.blipInfo(S.race.cpBlips[2])
		log("blip do checkpoint 1: ok=" .. tostring(okc) .. " existe=" .. tostring(existsC) .. " minimapa=" .. tostring(onMapC))
	end
	local remaining = {}
	for i = 2, #st.points do
		remaining[#remaining + 1] = st.points[i]
	end
	local routeOk, routeErr = S.N.startRoute(remaining)
	log("rota GPS no mapa: " .. (routeOk and "pedida" or ("ERRO " .. tostring(routeErr))))
	S.starting = nil
	log("corrida iniciada em '" .. st.spot.name .. "': você + " .. #st.rivals .. " rivais, " .. #st.points .. " pontos")
	say("Todos a postos! Alinhando na largada...")
end

local function createSpotHere()
	local pos = playerPoint()
	if pos == nil then
		say("Não consegui ler sua posição.")
		return
	end
	local name = "Local " .. (#spots.list(S.store) + 1)
	local r = spots.add(S.store, name, pos)
	if r.ok then
		blipFor(spots.get(S.store, r.id))
		log("local criado: " .. name .. " id=" .. r.id)
		say("Local criado: " .. name)
	else
		say("Não criado: " .. r.reason)
		log("falha ao criar local: " .. r.reason)
	end
end

local function removeSpot(id)
	local r = spots.remove(S.store, id)
	dropBlip(id)
	dropNegotiator(id)
	log("local removido id=" .. id .. " " .. r.reason)
end

-- ---------------------------------------------------------------- rotas (pontos nomeados gravados em arquivo)

local function saveRoutes()
	local f = io.open(ROUTES_FILE, "w")
	if f == nil then
		log("não consegui gravar " .. ROUTES_FILE)
		return
	end
	f:write(routes.serialize(S.routes))
	f:close()
end

local function loadRoutes()
	local f = io.open(ROUTES_FILE, "r")
	if f ~= nil then
		local src = f:read("*a")
		f:close()
		local list, err = routes.parse(src)
		if list ~= nil and #list > 0 then
			log("rotas carregadas do arquivo: " .. #list)
			return list
		end
		log("arquivo de rotas inválido (" .. tostring(err) .. "); usando a rota inicial")
	end
	return routes.default()
end

local function routeById(id)
	for _, rt in ipairs(S.routes) do
		if rt.id == id then
			return rt
		end
	end
	return nil
end

-- Mantém a largada (blip + negociador) alinhada ao primeiro ponto da rota.
local function syncRouteSpot(rt)
	local first = rt.slots[1].point
	local old = rt.spotId and spots.get(S.store, rt.spotId) or nil
	if old ~= nil and (first == nil or old.point.x ~= first.x or old.point.y ~= first.y) then
		removeSpot(old.id)
		rt.spotId = nil
		old = nil
	end
	if first ~= nil and old == nil then
		local r = spots.add(S.store, rt.name, first)
		if r.ok then
			local spot = spots.get(S.store, r.id)
			spot.routeId = rt.id
			rt.spotId = r.id
			blipFor(spot)
			log("largada da rota '" .. rt.name .. "' criada")
		else
			log("falha ao criar a largada da rota: " .. r.reason)
		end
	end
end

-- Marca o ponto `index` da rota na posição em que você está agora.
local function markSlot(rt, index)
	local pos = playerPoint()
	if pos == nil then
		say("Não consegui ler sua posição.")
		return
	end
	local r = routes.setPoint(rt, index, pos)
	if not r.ok then
		say("Não marcado: " .. r.reason)
		return
	end
	log(string.format("rota '%s': ponto %d (%s) marcado em %.1f, %.1f, %.1f", rt.name, index, rt.slots[index].name, pos.x, pos.y, pos.z))
	saveRoutes()
	syncRouteSpot(rt)
	local marked, total = routes.progress(rt)
	say(rt.slots[index].name .. " marcado (" .. marked .. "/" .. total .. ")")
end

-- Por que a corrida não pode começar agora? Devolve o motivo (usado pelo negociador) ou nil se pode.
local function raceBlockReason(spot)
	if S.race ~= nil or S.starting ~= nil then
		return "busy"
	end
	if S.N.playerMount() == nil then
		return "need_horse"
	end
	local rt = routeById(spot.routeId)
	if rt == nil or not routes.isComplete(rt) then
		return "route_incomplete"
	end
	local here = playerPoint()
	if here ~= nil and course.distance2d(here, rt.slots[1].point) > START_MAX_DISTANCE then
		return "too_far"
	end
	return nil
end

local function setStars(n)
	wanted.setStars(S.wanted, n, now())
	S.N.setWanted(n)
	log("procura ajustada pelo admin: " .. n)
end

-- ---------------------------------------------------------------- menu (páginas e navegação)

local PAGE_TITLE = { home = "CLANDESTINE RACES", spots = "ESCOLHA A LARGADA", spot = "LOCAL", routes = "ROTAS", route = "PONTOS DA ROTA", stars = "NÍVEL DE PROCURA" }

-- Itens da página atual. Cada item: { label, arrow, footer }.
local function pageItems()
	local page = S.page
	if page == "home" then
		return {
			{ label = "Rotas", arrow = true, footer = "Marque os pontos de cada rota: largada, passagens e chegada." },
			{ label = "Nível de procura", arrow = true, footer = "Define quantas estrelas a polícia começa a corrida." },
			{ label = "Iniciar corrida", arrow = true, footer = "Escolha um local para começar uma corrida agora." },
			{ label = "Fechar", arrow = false, footer = "Fecha o menu." },
		}
	elseif page == "spots" then
		local items = {}
		for _, s in ipairs(spots.list(S.store)) do
			items[#items + 1] = { label = s.name, arrow = S.mode == "admin", footer = "Largada da rota. Os pontos do percurso são fixos.", spotId = s.id }
		end
		items[#items + 1] = { label = "Voltar", arrow = false, footer = "Volta ao menu anterior." }
		return items
	elseif page == "spot" then
		return {
			{ label = "Iniciar corrida aqui", arrow = false, footer = "Começa a corrida neste local com cavalos NPC." },
			{ label = "Remover local", arrow = false, footer = "Apaga o local, o blip e o negociador." },
			{ label = "Voltar", arrow = false, footer = "Volta à lista de locais." },
		}
	elseif page == "routes" then
		local items = {}
		for _, rt in ipairs(S.routes) do
			local marked, total = routes.progress(rt)
			items[#items + 1] = { label = rt.name .. " (" .. marked .. "/" .. total .. ")", arrow = true, footer = "Rota com pontos fixos. Marque cada ponto parado no lugar.", routeId = rt.id }
		end
		items[#items + 1] = { label = "Voltar", arrow = false, footer = "Volta ao menu inicial." }
		return items
	elseif page == "route" then
		local rt = routeById(S.routeId)
		local items = {}
		if rt ~= nil then
			for i, slot in ipairs(rt.slots) do
				local state = slot.point and "marcado" or "falta marcar"
				local role = (i == 1) and "Largada" or ((i == #rt.slots) and "Chegada" or "Passagem")
				items[#items + 1] = { label = role .. ": " .. slot.name .. " (" .. state .. ")", arrow = false, footer = "Fique parado no lugar e aperte Enter para marcar aqui.", slotIndex = i }
			end
		end
		items[#items + 1] = { label = "Voltar", arrow = false, footer = "Volta à lista de rotas." }
		return items
	elseif page == "stars" then
		local items = {}
		for n = 0, 5 do
			items[#items + 1] = { label = n .. " estrela(s)", arrow = false, footer = "A polícia começa a corrida com este nível de procura.", stars = n }
		end
		return items
	end
	return {}
end

local function currentSpot()
	if S.spotId == nil then
		return nil
	end
	return spots.get(S.store, S.spotId)
end

local function goPage(page)
	S.page = page
	S.cursor = 1
	if page == "stars" then
		S.cursor = wanted.stars(S.wanted) + 1
	end
end

-- Enter na página atual.
local function activate()
	local items = pageItems()
	local item = items[S.cursor]
	if item == nil then
		return
	end
	if S.page == "home" then
		if S.cursor == 1 then
			S.mode = "admin"
			goPage("routes")
		elseif S.cursor == 2 then
			goPage("stars")
		elseif S.cursor == 3 then
			S.mode = "race"
			goPage("spots")
		else
			S.open = false
			log("menu fechado")
		end
	elseif S.page == "spots" then
		if item.spotId ~= nil then
			if S.mode == "race" then
				S.open = false
				startRace(spots.get(S.store, item.spotId))
			else
				S.spotId = item.spotId
				goPage("spot")
			end
		elseif item.label == "Criar local aqui" then
			createSpotHere()
		else
			goPage("home")
		end
	elseif S.page == "spot" then
		if S.cursor == 1 then
			S.open = false
			startRace(currentSpot())
		elseif S.cursor == 2 then
			removeSpot(S.spotId)
			S.spotId = nil
			goPage("spots")
		else
			goPage("spots")
		end
	elseif S.page == "routes" then
		if item.routeId ~= nil then
			S.routeId = item.routeId
			goPage("route")
		else
			goPage("home")
		end
	elseif S.page == "route" then
		local rt = routeById(S.routeId)
		if item.slotIndex ~= nil and rt ~= nil then
			markSlot(rt, item.slotIndex)
		else
			goPage("routes")
		end
	elseif S.page == "stars" then
		setStars(item.stars)
		goPage("home")
	end
end

-- Voltar: sobe uma página, ou fecha no menu inicial.
local function back()
	if S.page == "home" then
		S.open = false
		log("menu fechado")
	elseif S.page == "spot" then
		goPage("spots")
	elseif S.page == "route" then
		goPage("routes")
	else
		goPage("home")
	end
end

local function handleMenuKeys()
	if S.N.keyJustPressed(KEY_UP) then
		S.cursor = menu.move(S.cursor, -1, #pageItems())
	elseif S.N.keyJustPressed(KEY_DOWN) then
		S.cursor = menu.move(S.cursor, 1, #pageItems())
	elseif S.N.keyJustPressed(KEY_ENTER) then
		activate()
	elseif S.N.keyJustPressed(KEY_BACK) then
		back()
	end
end

local function drawMenu()
	local items = pageItems()
	local footer = (items[S.cursor] and items[S.cursor].footer) or ""
	local subtitle = (S.mode == "race" and S.page == "spots") and "ESCOLHA O LOCAL" or PAGE_TITLE[S.page]
	menu.draw(S.N, {
		title = "CLANDESTINE RACES",
		subtitle = subtitle,
		counter = S.cursor .. "/" .. #items,
		items = items,
		cursor = S.cursor,
		footer = footer,
	})
end

-- ---------------------------------------------------------------- corrida em andamento

-- Quem recebe a ordem de correr: o cavaleiro, se já estiver montado; senão o próprio cavalo.
local function driverOf(h)
	if h.rider ~= nil and S.N.isOnMount(h.rider) then
		return h.rider
	end
	return h.ped
end

-- Aviso grande no centro da tela (contagem e "START, BOYS!").
local function showBanner(text, seconds)
	S.banner = { text = text, untilT = os.clock() + seconds }
end

local function drawBanner()
	local b = S.banner
	if b == nil then
		return
	end
	if os.clock() > b.untilT then
		S.banner = nil
		return
	end
	local scale = 1.4
	-- Largura aproximada do texto: 0,01615 da tela por caractere a escala 1.0 (medido nas capturas).
	local x = 0.5 - (#b.text * 0.01615 * scale) / 2
	S.N.drawText(b.text, x, 0.30, scale, 255, 255, 255, 255)
end

-- Alinha todos lado a lado na largada, de frente para o primeiro checkpoint. Você fica no meio.
local function alignGrid(r)
	local first = r.course.checkpoints[2]
	local dx, dy = first.x - r.start.x, first.y - r.start.y
	local len = math.sqrt(dx * dx + dy * dy)
	if len == 0 then
		len = 1
	end
	dx, dy = dx / len, dy / len
	r.dirx, r.diry = dx, dy
	-- Perpendicular à direção da corrida; direção do jogo: 0 = norte (+y), cresce para oeste.
	local px, py = -dy, dx
	local atan2 = math.atan2 or math.atan
	local heading = math.deg(atan2(-dx, dy))

	local order, own = {}, nil
	for _, h in ipairs(r.horses) do
		if h.own then
			own = h
		else
			order[#order + 1] = h
		end
	end
	table.insert(order, math.floor(#order / 2) + 1, own)

	local count = #order
	for slot, h in ipairs(order) do
		local off = (slot - (count + 1) / 2) * GRID_SPACING
		S.N.place(h.ped, r.start.x + px * off, r.start.y + py * off, r.start.z, heading)
	end
	log(string.format("grade alinhada: %d cavalos lado a lado, direção %.0f", count, heading))
end

-- Fase de preparo: espera montarem, alinha, conta 3-2-1 e o negociador grita "START, BOYS!".
local function tickGrid(r)
	local t = os.clock()
	r.gridAt = r.gridAt or t
	if not r.aligned then
		local allMounted = true
		for _, h in ipairs(r.horses) do
			if h.rider ~= nil and not S.N.isOnMount(h.rider) then
				allMounted = false
			end
		end
		if allMounted or (t - r.gridAt) >= MOUNT_WAIT_SECONDS then
			alignGrid(r)
			r.aligned = true
			r.alignedAt = t
		end
		return
	end
	local left = COUNTDOWN_SECONDS - math.floor(t - r.alignedAt)
	if left > 0 then
		if r.lastCount ~= left then
			r.lastCount = left
			showBanner(tostring(left), 1.1)
		end
		return
	end
	-- Largada: o relógio de 6 minutos, a procura e a ordem de correr dos rivais começam agora.
	r.phase = "go"
	r.startedAt = now()
	wanted.startRace(S.wanted, now())
	showBanner("START, BOYS!", 3)
	say("NEGOCIADOR: Start, boys!")
	log("largada dada: START, BOYS!")
end

-- Quem a polícia persegue: o cavaleiro do rival, ou você se o corredor for o seu cavalo.
local function targetOf(h)
	if h.own then
		return S.N.playerPed()
	end
	return h.rider or h.ped
end

-- Escolhe o próximo ponto de passagem: a direção mais próxima do destino cujo chão à frente não tem queda brusca.
-- Devolve o ponto ({x, y, z}), ou nil se nenhuma direção estiver livre ou se não houver dados de terreno.
local function planStep(from, target, prevOff)
	local atan2 = math.atan2 or math.atan
	local bearing = atan2(target.y - from.y, target.x - from.x)
	local dist = math.sqrt((target.x - from.x) ^ 2 + (target.y - from.y) ^ 2)
	local samples = math.min(PLAN_SAMPLES, math.max(1, math.floor(dist / PLAN_STEP)))
	local anyData = false
	local z0 = S.N.groundZ(from.x, from.y, from.z) or from.z
	local order = {}
	if prevOff ~= nil then
		order[1] = prevOff
	end
	for _, o in ipairs(PLAN_OFFSETS) do
		if o ~= prevOff then
			order[#order + 1] = o
		end
	end
	for _, off in ipairs(order) do		local ang = bearing + math.rad(off)
		local ok, lastZ, x, y = true, z0, from.x, from.y
		for s = 1, samples do
			x = from.x + math.cos(ang) * PLAN_STEP * s
			y = from.y + math.sin(ang) * PLAN_STEP * s
			local gz = S.N.groundZ(x, y, lastZ)
			if gz == nil then
				ok = false
				break
			end
			anyData = true
			if math.abs(gz - lastZ) > PLAN_MAX_DZ then
				ok = false
				break
			end
			lastZ = gz
		end
		if ok then
			return { x = x, y = y, z = lastZ }, off
		end
	end
	if not anyData and not S.planNoDataLogged then
		S.planNoDataLogged = true
		log("planejador sem dados de terreno (GET_GROUND_Z_FOR_3D_COORD): " .. tostring(S.N.groundError))
	end
	return nil
end

-- Manda o rival ir para o checkpoint atual. O modo padrão ("anymeans") usa o caminho do próprio jogo
-- (TASK_GO_TO_COORD_ANY_MEANS). O modo "straight" é o plano B, com o planejador de chão.
local function orderToRun(r, h)
	local idx = 2
	for _, racer in ipairs(r.racers) do
		if racer.id == h.id then
			idx = racer.nextIndex
		end
	end
	local target = r.course.checkpoints[idx]
	local wp, off = target, nil
	if h.mode == "straight" then
		local from = S.N.toPoint(S.N.entityCoords(h.ped))
		local planned, planOff = nil, nil
		if from ~= nil then
			planned, planOff = planStep(from, target, h.lastOff)
		end
		if planned ~= nil then
			wp, off = planned, planOff
			h.blocked = 0
		else
			h.blocked = (h.blocked or 0) + 1
			if h.blocked == 3 then
				log(h.id .. ": sem caminho seguro à frente, indo direto ao checkpoint " .. idx)
			end
		end
	end
	if h.wp == nil or h.wpIdx ~= idx or course.distance2d(wp, h.wp) > 8 then
		S.N.goTo(driverOf(h), wp.x, wp.y, wp.z, h.speed or 3.0, h.mode, h.ped)
		h.wp, h.wpIdx = wp, idx
		if off ~= nil and off ~= 0 and h.lastOff ~= off then
			log(h.id .. ": desviando " .. off .. " graus do destino (terreno)")
		end
		h.lastOff = off
	end
end

-- Você passou por um checkpoint obrigatório: some o blip dele, o GPS passa a mostrar só o que falta.
local function passPlayerCheckpoint(r, passedIdx, nextIdx)
	if r.cpBlips ~= nil and r.cpBlips[passedIdx] ~= nil then
		S.N.removeBlip(r.cpBlips[passedIdx])
		r.cpBlips[passedIdx] = nil
	end
	local remaining = {}
	for i = nextIdx, #r.course.checkpoints do
		remaining[#remaining + 1] = r.course.checkpoints[i]
	end
	S.N.startRoute(remaining)
	local inter = #r.course.checkpoints - 2
	say("Checkpoint " .. (passedIdx - 1) .. "/" .. inter)
	log("você passou pelo checkpoint " .. (passedIdx - 1) .. "/" .. inter)
end

-- Mostra no topo da tela qual é o próximo ponto obrigatório e a distância até ele.
local function drawRaceHud()
	local r = S.race
	if r == nil or r.phase ~= "go" then
		return
	end
	local me = r.racers[1]
	if me.finished then
		return
	end
	local cps = r.course.checkpoints
	local nextIdx = me.nextIndex
	local p = playerPoint()
	local d = p and course.distance2d(p, cps[nextIdx]) or 0
	local label = (nextIdx == #cps) and "CHEGADA" or ("CHECKPOINT " .. (nextIdx - 1) .. "/" .. (#cps - 2))
	S.N.drawText(string.format("%s - %.0f m", label, d), 0.38, 0.03, 0.55, 255, 255, 255, 255)
end

local function tickRace()
	local r = S.race
	local t = now()

	if r.phase == "grid" then
		tickGrid(r)
		return
	end

	if t - r.startedAt > RACE_TIMEOUT_SECONDS then
		clearRace("tempo esgotado")
		return
	end

	-- Rivais: quando o cavaleiro monta (ou após 4 s), manda correr para o checkpoint atual.
	for _, h in ipairs(r.horses) do
		if not h.own and not h.tasked then
			if h.rider == nil or S.N.isOnMount(h.rider) or (t - r.startedAt) >= 4 then
				h.p0 = S.N.toPoint(S.N.entityCoords(h.ped))
				orderToRun(r, h)
				h.tasked = true
				r.goAt = r.goAt or os.clock()
				log(h.id .. " recebeu a ordem de correr (velocidade " .. string.format("%.2f", h.speed or 3.0) .. ", cavaleiro montado=" .. tostring(h.rider ~= nil and S.N.isOnMount(h.rider)) .. ")")
			end
		end
	end

	-- Confere se os rivais saíram do lugar; se não, troca para o método em linha reta.
	if r.goAt and not r.moveChecked and os.clock() - r.goAt >= 6 then
		r.moveChecked = true
		for _, h in ipairs(r.horses) do
			if not h.own and h.p0 ~= nil and not h.holding then
				local pNow = S.N.toPoint(S.N.entityCoords(h.ped))
				local moved = pNow and course.distance(pNow, h.p0) or 0
				log(string.format("%s andou %.1f m em 6 s (modo %s)", h.id, moved, h.mode or "anymeans"))
				if moved < 8 then
					h.mode = "straight"
					h.wp = nil
					orderToRun(r, h)
					log(h.id .. " parado com o caminho do jogo: trocando para linha reta com planejador de terreno")
				end
			end
		end
	end

	-- A cada PLAN_INTERVAL s: segura rivais muito à frente de você (rédea) e reemite a ordem dos demais.
	local meRacer = r.racers[1]
	local meP = playerPoint()
	for _, h in ipairs(r.horses) do
		if not h.own and h.tasked and os.clock() - (h.planAt or 0) >= PLAN_INTERVAL then
			h.planAt = os.clock()
			local hp = S.N.toPoint(S.N.entityCoords(h.ped))
			local d = (hp and meP) and course.distance2d(hp, meP) or 0
			local ahead = false
			for _, racer in ipairs(r.racers) do
				if racer.id == h.id and hp ~= nil and meP ~= nil then
					local tIdx = math.max(racer.nextIndex, meRacer.nextIndex)
					ahead = racer.nextIndex > meRacer.nextIndex
						or (racer.nextIndex == meRacer.nextIndex and course.distance2d(hp, r.course.checkpoints[tIdx]) < course.distance2d(meP, r.course.checkpoints[tIdx]))
				end
			end
			if not h.holding and d > LEASH_FAR and ahead then
				h.holding = true
				log(string.format("%s esperando você (a %.0f m à frente)", h.id, d))
			end
			if h.holding and d < LEASH_NEAR then
				h.holding = false
				h.wp = nil
				log(h.id .. " voltou a correr")
			end
			if h.holding then
				S.N.hold(driverOf(h))
			else
				orderToRun(r, h)
			end
		end
	end

	-- Segunda medição, 6 s depois da primeira, para saber se o método escolhido fez os rivais andarem.
	if r.moveChecked and not r.moveChecked2 and os.clock() - r.goAt >= 12 then
		r.moveChecked2 = true
		for _, h in ipairs(r.horses) do
			if not h.own and h.p0 ~= nil then
				local pNow = S.N.toPoint(S.N.entityCoords(h.ped))
				local moved = pNow and course.distance(pNow, h.p0) or 0
				log(string.format("%s: %.1f m desde a largada, aos 12 s (modo %s)", h.id, moved, h.mode or "navmesh"))
			end
		end
	end

	-- Posições atuais dos cavalos e avanço nos checkpoints.
	local positions = {}
	for _, h in ipairs(r.horses) do
		positions[h.id] = S.N.toPoint(S.N.entityCoords(h.ped))
	end
	for _, racer in ipairs(r.racers) do
		if positions[racer.id] ~= nil then
			local before = racer.nextIndex
			local result = course.advance(r.course, racer, positions[racer.id])
			if result == "checkpoint" and racer.nextIndex ~= before then
				if racer.id == "VOCE" then
					passPlayerCheckpoint(r, before, racer.nextIndex)
				end
				for _, h in ipairs(r.horses) do
					if h.id == racer.id and not racer.finished and not h.own then
						orderToRun(r, h)
					end
				end
			elseif result == "finished" then
				log("cavalo " .. racer.id .. " chegou em " .. racer.finishOrder .. "º")
			end
		end
	end

	-- Procura: sobe com o tempo e ajusta a quantidade de policiais.
	local before = wanted.stars(S.wanted)
	local stars = wanted.update(S.wanted, t)
	if stars ~= before then
		S.N.setWanted(stars)
		log("procura subiu para " .. stars)
	end

	-- Alerta da polícia, uma vez por corrida.
	if wanted.alert(S.wanted) then
		say("ALERTA: corrida clandestina! A polícia foi acionada.")
		log("alerta da polícia emitido")
	end

	-- Policiais a cavalo: um por vez, conforme os modelos carregam (o cavaleiro nasce na sela).
	local want = pursuit.desiredCount(stars, PURSUIT_CFG)
	if #r.cops < want then
		local pend = r.copPending
		if pend == nil then
			pend = { name = pickOne(COP_PRESET), since = os.clock() }
			pend.hash = S.N.hash(pend.name)
			r.copPending = pend
			log("policial a caminho: " .. pend.name)
		end
		local k = #r.cops
		local dx, dy = r.dirx or 1, r.diry or 0
		local bx = r.start.x - dx * COP_SPAWN_DISTANCE - dy * (k * 4)
		local by = r.start.y - dy * COP_SPAWN_DISTANCE + dx * (k * 4)
		if pend.horse == nil then
			pend.horse = S.N.createPedFromHash(r.modelHash, bx, by, r.start.z, 0.0)
		end
		if pend.horse ~= nil and pend.rider == nil then
			pend.rider = S.N.createRiderOn(pend.horse, pend.hash)
		end
		if pend.horse ~= nil and pend.rider ~= nil then
			S.N.configureRider(pend.rider)
			S.N.markCop(pend.rider)
			r.cops[#r.cops + 1] = { id = "P" .. (#r.cops + 1), ped = pend.horse, rider = pend.rider, target = nil }
			log("policial " .. r.cops[#r.cops].id .. " apareceu (" .. pend.name .. ")")
			r.copPending = nil
		elseif os.clock() - pend.since > 8 and not S.copWaitLogged then
			S.copWaitLogged = true
			log("modelo do policial " .. pend.name .. " não carregou em 8 s")
		end
	end

	local copIds = {}
	local copById = {}
	for _, c in ipairs(r.cops) do
		copIds[#copIds + 1] = c.id
		copById[c.id] = c
	end
	local assignments = pursuit.assign(PURSUIT_CFG, copIds, r.racers, positions, r.start)
	for copId, racerId in pairs(assignments) do
		local cop = copById[copId]
		if cop.target ~= racerId then
			for _, h in ipairs(r.horses) do
				if h.id == racerId then
					S.N.chase(cop.rider or cop.ped, targetOf(h))
				end
			end
			cop.target = racerId
		end
	end

	-- Fim: todos os cavalos chegaram.
	local allDone = r.racers[1].finished -- a corrida termina quando você cruza a chegada
	if allDone then
		local rank = course.ranking(r.course, r.racers, positions)
		local names = {}
		for i, racer in ipairs(rank) do
			names[i] = racer.id
		end
		say("Corrida terminada. Ordem: " .. table.concat(names, ", "))
		log("ordem final: " .. table.concat(names, ", "))
		clearRace("todos chegaram")
	end
end

-- ---------------------------------------------------------------- entrada e desenho

local function drawMessage()
	if S.message ~= "" and now() <= S.messageUntil then
		S.N.drawText(S.message, 0.33, 0.9)
	end
end

local function dialogCtx()
	local rt = S.dlgSpot and routeById(S.dlgSpot.routeId) or nil
	return { routeName = rt and rt.name or "esta rota" }
end

local function closeDialogue()
	S.dlg = nil
	S.dlgSpot = nil
end

-- Teclas da conversa: setas escolhem, Enter confirma, Backspace volta. Se você se afasta, a conversa acaba.
local function handleDialogueKeys()
	local pp = playerPoint()
	if pp ~= nil and S.dlgSpot ~= nil and course.distance2d(pp, S.dlgSpot.point) > 8 then
		log("conversa encerrada: você se afastou do negociador")
		closeDialogue()
		return
	end
	local c = dialogCtx()
	if S.N.keyJustPressed(KEY_UP) then
		S.dlg = dialogue.move(S.dlg, -1, c)
	elseif S.N.keyJustPressed(KEY_DOWN) then
		S.dlg = dialogue.move(S.dlg, 1, c)
	elseif S.N.keyJustPressed(KEY_ENTER) then
		local nextState, action = dialogue.choose(S.dlg, c)
		S.dlg = nextState
		if action == "close" then
			closeDialogue()
		elseif action == "start" then
			local reason = raceBlockReason(S.dlgSpot)
			if reason ~= nil then
				log("negociador recusou a corrida: " .. reason)
				S.dlg = dialogue.refuse(S.dlg, reason)
			else
				local spot = S.dlgSpot
				closeDialogue()
				log("conversa: corrida aceita em " .. spot.name)
				startRace(spot)
			end
		end
	elseif S.N.keyJustPressed(KEY_BACK) then
		local nextState, action = dialogue.back(S.dlg)
		S.dlg = nextState
		if action == "close" then
			closeDialogue()
		end
	end
end

local function drawDialogue()
	local v = dialogue.view(S.dlg, dialogCtx())
	local items = {}
	for i, o in ipairs(v.options) do
		items[i] = { label = o.label, arrow = false }
	end
	menu.draw(S.N, {
		title = "CLANDESTINE RACES",
		subtitle = string.upper(v.speaker),
		counter = S.dlg.cursor .. "/" .. #items,
		items = items,
		cursor = S.dlg.cursor,
		footer = v.text,
	})
end

local function drawNegotiatePrompt()
	if S.open or S.dlg ~= nil then
		return
	end
	local spot = nearbyNegotiatorSpot()
	if spot ~= nil then
		S.N.drawText("Aperte E para falar com o negociador", 0.33, 0.85)
	end
end

local function drawDiagnostic()
	-- Quadrado branco no centro (0,5 / 0,5) para comparar as coordenadas.
	S.N.drawRect(0.5, 0.5, 0.05, 0.05, 255, 255, 255, 255)
	S.N.bgText("A: BG_DISPLAY_TEXT escala 0.4 branco", 0.20, 0.20, 0.4, 255, 255, 255, 255)
	S.N.bgText("B: escala 0.6 vermelho", 0.20, 0.30, 0.6, 255, 0, 0, 255)
	S.N.bgText("C: escala 0.25 verde", 0.20, 0.40, 0.25, 0, 255, 0, 255)
	S.N.drawText("D: _DISPLAY_TEXT antigo", 0.20, 0.50)
end

-- Sonda: registra no log o que cada native devolve, sem alterar nada no jogo.
local function probe()
	local N = S.N
	local function try(label, fn)
		local ok, res = pcall(fn)
		log("SONDA " .. label .. ": " .. (ok and tostring(res) or ("ERRO " .. tostring(res))))
		return ok and res or nil
	end
	local ped = N.playerPed()
	local playerId = N.call("PLAYER", "PLAYER_ID")
	log("SONDA ---- início ----")
	log("SONDA ped=" .. tostring(ped) .. " playerId=" .. tostring(playerId))
	try("IS_PED_ON_MOUNT", function() return N.call("PED", "IS_PED_ON_MOUNT", ped) end)
	local mount = try("GET_MOUNT", function() return N.call("PED", "GET_MOUNT", ped) end)
	local owned = try("GET_MOUNT_OWNED_BY_PLAYER", function() return N.call("PLAYER", "GET_MOUNT_OWNED_BY_PLAYER", playerId) end)
	local last = try("_GET_LAST_MOUNT", function() return N.call("PED", "_GET_LAST_MOUNT", ped) end)
	for _, h in ipairs({ { "mount", mount }, { "owned", owned }, { "last", last } }) do
		if h[2] ~= nil then
			try("GET_ENTITY_MODEL(" .. h[1] .. ")", function() return N.call("ENTITY", "GET_ENTITY_MODEL", h[2]) end)
			try("DOES_ENTITY_EXIST(" .. h[1] .. ")", function() return N.call("ENTITY", "DOES_ENTITY_EXIST", h[2]) end)
		end
	end
	try("GET_ENTITY_MODEL(player)", function() return N.call("ENTITY", "GET_ENTITY_MODEL", ped) end)

	-- Estrada mais próxima: testa como o RedLua cria o parâmetro de saída.
	local p = playerPoint()
	if p ~= nil then
		log("SONDA posição do jogador: " .. p.x .. ", " .. p.y .. ", " .. p.z)
		for _, variant in ipairs({ "Vector3", "Vector3x1" }) do
			try("GET_CLOSEST_VEHICLE_NODE out=" .. variant, function()
				local out
				if variant == "Vector3" then out = N.new("Vector3") else out = N.new("Vector3", 1) end
				local found = N.call("PATHFIND", "GET_CLOSEST_VEHICLE_NODE", p.x, p.y, p.z, out, 1, 3.0, 0.0)
				local okf, x, y, z = pcall(function() return out.x, out.y, out.z end)
				return "found=" .. tostring(found) .. " out=" .. (okf and (tostring(x) .. ", " .. tostring(y) .. ", " .. tostring(z)) or "campos ilegíveis")
			end)
		end
	end

	-- Modelos: pede e acompanha por alguns segundos se carregam.
	S.probe = { t0 = os.clock(), last = -1, models = {} }
	for _, name in ipairs({ "A_M_M_VALTOWNFOLK_01", "A_M_M_RHDTOWNFOLK_01", "A_C_HORSE_ARABIAN_WHITE" }) do
		local hash = N.hash(name)
		N.call("STREAMING", "REQUEST_MODEL", hash, false)
		S.probe.models[#S.probe.models + 1] = { name = name, hash = hash }
		log("SONDA modelo pedido: " .. name .. " hash=" .. tostring(hash))
	end
end

local function probeTick()
	local pr = S.probe
	if pr == nil then
		return
	end
	local sec = math.floor(os.clock() - pr.t0)
	if sec == pr.last then
		return
	end
	pr.last = sec
	for _, m in ipairs(pr.models) do
		log("SONDA t=" .. sec .. "s modelo " .. m.name .. " carregado=" .. tostring(S.N.call("STREAMING", "HAS_MODEL_LOADED", m.hash)))
	end
	if sec >= 6 then
		S.probe = nil
		log("SONDA ---- fim ----")
	end
end

local function handleKeys()
	if S.N.keyJustPressed(KEY_PROBE) then
		local okp, errp = pcall(probe)
		if not okp then
			log("erro na sonda: " .. tostring(errp))
		end
	end
	if S.N.keyJustPressed(KEY_DIAG) then
		S.diag = not S.diag
		log("diagnóstico de texto " .. (S.diag and "ligado" or "desligado"))
	end
	if S.N.keyJustPressed(KEY_TOGGLE) and S.dlg == nil then
		S.open = not S.open
		if S.open then
			S.mode = "admin"
			goPage("home")
		end
		log("menu " .. (S.open and "aberto" or "fechado"))
	end
	if S.N.keyJustPressed(KEY_STOP) and S.race ~= nil then
		clearRace("encerrada pelo admin")
	end

	-- Perto do negociador, E começa uma conversa (a corrida só começa se você aceitar nela).
	if not S.open and S.dlg == nil and S.N.keyJustPressed(KEY_NEGOTIATE) then
		local spot = nearbyNegotiatorSpot()
		if spot ~= nil then
			S.dlg = dialogue.new()
			S.dlgSpot = spot
			S.N.faceEntity(S.negotiators[spot.id], S.N.playerPed())
			log("conversa iniciada com o negociador de " .. spot.name)
		end
	end

	if S.dlg ~= nil then
		handleDialogueKeys()
	elseif S.open then
		handleMenuKeys()
	end
end

local function guarded(name, fn)
	local ok, err = pcall(fn)
	if not ok and not S.errorsLogged[name] then
		S.errorsLogged[name] = true
		log("erro em " .. name .. ": " .. tostring(err))
	end
end

return {
	OnLoad = function()
		S = {
			N = natives.new({ call = native.call, misc = misc, new = native.new }),
			store = spots.new(),
			open = false,
			page = "home",
			mode = "admin",
			cursor = 1,
			spotId = nil,
			wanted = wanted.new(WANTED_CFG),
			race = nil,
			blips = {},
			negotiators = {},
			message = "",
			messageUntil = 0,
			errorsLogged = {},
		}
		math.randomseed(os.time())
		S.routes = loadRoutes()
		for _, rt in ipairs(S.routes) do
			syncRouteSpot(rt)
		end
		local hashOk, hashErr = S.N.hashMode()
		log("hash exato (objeto nativo Hash): " .. (hashOk and "disponível" or ("INDISPONÍVEL: " .. tostring(hashErr))))
		log("carregado. F8 abre o menu de admin; E perto do negociador de um local inicia a corrida.")
	end,

	OnTick = function()
		if S == nil then
			return
		end
		guarded("negociadores", syncNegotiators)
		guarded("teclas", handleKeys)
		guarded("preparo", tickStarting)
		if S.race ~= nil then
			guarded("corrida", tickRace)
		end
		if S.open then
			guarded("menu", drawMenu)
		end
		if S.dlg ~= nil then
			guarded("conversa", drawDialogue)
		end
		if S.diag then
			guarded("diagnostico", drawDiagnostic)
		end
		guarded("sonda-tick", probeTick)
		guarded("prompt", drawNegotiatePrompt)
		guarded("mensagem", drawMessage)
		guarded("banner", drawBanner)
		guarded("hud", drawRaceHud)
	end,

	OnStop = function()
		if S == nil then
			return
		end
		clearRace("script descarregado")
		cancelStarting("script descarregado")
		for id in pairs(S.blips) do
			dropBlip(id)
		end
		for id in pairs(S.negotiators) do
			dropNegotiator(id)
		end
		log("descarregado")
	end,
}
