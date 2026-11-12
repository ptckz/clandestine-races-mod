-- Máquina de estados do painel de admin. Não desenha nada.
-- Recebe uma tecla e devolve (novo estado, ação). A ação é executada pelo adaptador.
--
-- Teclas aceitas: "up", "down", "enter", "back", "add", "delete".
-- Ações possíveis: close, add_spot_here, remove_spot, add_checkpoint, set_stars, start_race.

local spots = require("clandestine.spots")

local panel = {}

local MAX_STARS = 5

local function copy(state)
	return {
		page = state.page,
		cursor = state.cursor,
		selectedSpotId = state.selectedSpotId,
		targetStars = state.targetStars,
		message = state.message,
	}
end

local function goTo(state, page)
	state.page = page
	state.cursor = 1
end

-- Quantos itens o cursor pode percorrer na página atual.
function panel.itemCount(state, ctx)
	if state.page == "menu" then
		return 4
	elseif state.page == "spots" or state.page == "race" then
		return #ctx.spots
	elseif state.page == "spot" then
		return 2
	end
	return 0
end

function panel.new()
	return {
		page = "menu",
		cursor = 1,
		selectedSpotId = nil,
		targetStars = 0,
		message = "",
	}
end

local function moveCursor(state, delta, ctx)
	local count = panel.itemCount(state, ctx)
	local next = state.cursor + delta
	if next < 1 then
		next = 1
	end
	if count > 0 and next > count then
		next = count
	end
	state.cursor = next
end

local function onEnter(state, ctx)
	if state.page == "menu" then
		if state.cursor == 1 then
			goTo(state, "spots")
		elseif state.cursor == 2 then
			goTo(state, "stars")
			state.targetStars = ctx.currentStars
		elseif state.cursor == 3 then
			goTo(state, "race")
		else
			return state, { type = "close" }
		end
		return state, nil
	end

	if state.page == "spots" then
		local spot = ctx.spots[state.cursor]
		if spot then
			state.selectedSpotId = spot.id
			goTo(state, "spot")
		end
		return state, nil
	end

	if state.page == "spot" then
		if state.cursor == 1 then
			return state, { type = "add_checkpoint", id = state.selectedSpotId }
		end
		goTo(state, "spots")
		return state, nil
	end

	if state.page == "stars" then
		return state, { type = "set_stars", stars = state.targetStars }
	end

	if state.page == "race" then
		local spot = ctx.spots[state.cursor]
		if spot == nil then
			return state, nil
		end
		if not spots.isReady(spot) then
			state.message = "Percurso incompleto: precisa de pelo menos 2 checkpoints"
			return state, nil
		end
		return state, { type = "start_race", id = spot.id }
	end

	return state, nil
end

-- Processa uma tecla. Retorna (novo estado, ação ou nil).
function panel.handle(state, key, ctx)
	local r = copy(state)
	r.message = ""

	if key == "back" then
		if r.page == "menu" then
			return r, { type = "close" }
		end
		goTo(r, "menu")
		return r, nil
	end

	if r.page == "stars" then
		if key == "up" then
			r.targetStars = math.min(MAX_STARS, r.targetStars + 1)
			return r, nil
		elseif key == "down" then
			r.targetStars = math.max(0, r.targetStars - 1)
			return r, nil
		elseif key == "enter" then
			return onEnter(r, ctx)
		end
		return r, nil
	end

	if key == "up" then
		moveCursor(r, -1, ctx)
		return r, nil
	elseif key == "down" then
		moveCursor(r, 1, ctx)
		return r, nil
	elseif key == "enter" then
		return onEnter(r, ctx)
	elseif key == "add" and r.page == "spots" then
		return r, { type = "add_spot_here" }
	elseif key == "delete" and r.page == "spots" then
		local spot = ctx.spots[r.cursor]
		if spot then
			return r, { type = "remove_spot", id = spot.id }
		end
		return r, nil
	end

	return r, nil
end

return panel
