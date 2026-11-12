-- Locais de largada definidos pelo admin, cada um com seu percurso.
-- Lógica pura: não chama natives.
--
-- Cada local tem: id, name, point (ponto de largada, onde fica o blip) e route
-- (lista de checkpoints depois da largada, na ordem). O percurso fica pronto com
-- pelo menos 2 checkpoints na rota (um intermediário e a chegada).

local spots = {}

-- Limites padrão do mapa, em unidades do jogo. São aproximações: confirmar no jogo antes de usar.
local DEFAULT_BOUNDS = { minX = -4096, maxX = 4096, minY = -4096, maxY = 4096, minZ = -200, maxZ = 2000 }

local MIN_ROUTE_POINTS = 2

local function normalizeName(name)
	if type(name) ~= "string" then
		return nil
	end
	local trimmed = name:match("^%s*(.-)%s*$")
	if trimmed == "" then
		return nil
	end
	return trimmed
end

local function validPoint(p, bounds)
	if type(p) ~= "table" then
		return "invalid_point"
	end
	if type(p.x) ~= "number" or type(p.y) ~= "number" or type(p.z) ~= "number" then
		return "invalid_point"
	end
	if p.x < bounds.minX or p.x > bounds.maxX
		or p.y < bounds.minY or p.y > bounds.maxY
		or p.z < bounds.minZ or p.z > bounds.maxZ then
		return "out_of_bounds"
	end
	return nil
end

-- Cria um repositório de locais. `bounds` é opcional e sobrescreve os limites padrão.
function spots.new(bounds)
	local b = {}
	for k, v in pairs(DEFAULT_BOUNDS) do
		b[k] = v
	end
	for k, v in pairs(bounds or {}) do
		b[k] = v
	end
	return { items = {}, nextId = 1, bounds = b }
end

-- Adiciona um local. Retorna { ok = true, id = n } ou { ok = false, reason = "..." }.
function spots.add(store, name, point)
	local clean = normalizeName(name)
	if clean == nil then
		return { ok = false, reason = "invalid_name" }
	end
	local key = clean:lower()
	for _, item in ipairs(store.items) do
		if item.key == key then
			return { ok = false, reason = "duplicate_name" }
		end
	end
	local problem = validPoint(point, store.bounds)
	if problem then
		return { ok = false, reason = problem }
	end
	local id = store.nextId
	store.nextId = id + 1
	store.items[#store.items + 1] = {
		id = id,
		name = clean,
		key = key,
		point = { x = point.x, y = point.y, z = point.z },
		route = {},
	}
	return { ok = true, id = id }
end

-- Remove um local pelo id.
function spots.remove(store, id)
	for i, item in ipairs(store.items) do
		if item.id == id then
			table.remove(store.items, i)
			return { ok = true }
		end
	end
	return { ok = false, reason = "not_found" }
end

-- Devolve o local com o id, ou nil.
function spots.get(store, id)
	for _, item in ipairs(store.items) do
		if item.id == id then
			return item
		end
	end
	return nil
end

-- Lista os locais em ordem de criação.
function spots.list(store)
	local out = {}
	for i, item in ipairs(store.items) do
		out[i] = item
	end
	return out
end

-- Acrescenta um checkpoint ao final do percurso do local.
function spots.addCheckpoint(store, id, point)
	local item = spots.get(store, id)
	if item == nil then
		return { ok = false, reason = "not_found" }
	end
	local problem = validPoint(point, store.bounds)
	if problem then
		return { ok = false, reason = problem }
	end
	item.route[#item.route + 1] = { x = point.x, y = point.y, z = point.z }
	return { ok = true }
end

-- O percurso está pronto para correr?
function spots.isReady(item)
	return #item.route >= MIN_ROUTE_POINTS
end

return spots
