-- Rotas definidas: uma lista de pontos nomeados que a corrida percorre em ordem.
-- O primeiro ponto é a largada e o último é a chegada. Cada ponto é marcado pelo admin, no jogo,
-- parado no lugar. Lógica pura: não chama natives. Compatível com Lua 5.1 (RedLua) e 5.3 (testes).

local routes = {}

local function validPoint(p)
	return type(p) == "table"
		and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"
end

-- Cria uma rota vazia. `slotNames` é a lista de nomes dos pontos, na ordem (largada ... chegada).
function routes.new(id, name, slotNames)
	if type(name) ~= "string" or name == "" then
		error("a rota precisa de um nome", 2)
	end
	if type(slotNames) ~= "table" or #slotNames < 2 then
		error("a rota precisa de pelo menos 2 pontos (largada e chegada)", 2)
	end
	local slots = {}
	for i, slotName in ipairs(slotNames) do
		slots[i] = { name = slotName, point = nil }
	end
	return { id = id, name = name, slots = slots }
end

-- Marca (ou remarca) o ponto `index` da rota.
function routes.setPoint(route, index, point)
	local slot = route.slots[index]
	if slot == nil then
		return { ok = false, reason = "invalid_slot" }
	end
	if not validPoint(point) then
		return { ok = false, reason = "invalid_point" }
	end
	slot.point = { x = point.x, y = point.y, z = point.z }
	return { ok = true }
end

-- Quantos pontos já foram marcados, e o total.
function routes.progress(route)
	local marked = 0
	for _, slot in ipairs(route.slots) do
		if slot.point ~= nil then
			marked = marked + 1
		end
	end
	return marked, #route.slots
end

function routes.isComplete(route)
	local marked, total = routes.progress(route)
	return marked == total
end

-- Lista de pontos na ordem. Só funciona com a rota completa.
function routes.points(route)
	if not routes.isComplete(route) then
		error("a rota ainda tem pontos sem marcar", 2)
	end
	local list = {}
	for i, slot in ipairs(route.slots) do
		list[i] = { x = slot.point.x, y = slot.point.y, z = slot.point.z }
	end
	return list
end

-- Rota inicial: Thieves' Landing > Blackwater > Cattail Pond.
-- Blackwater vem de um comentário de usuário na lista de teleportes do RDR2Mods (não confirmado em jogo).
-- A largada e a chegada ficam sem marcar: coordenadas confiáveis não foram encontradas.
function routes.default()
	local r = routes.new(1, "Thieves Landing > Cattail Pond", { "Thieves Landing", "Blackwater", "Cattail Pond" })
	routes.setPoint(r, 2, { x = -798.984, y = -1247.722, z = 43.425 })
	return { r }
end

-- Texto Lua que recria a lista de rotas (para gravar em arquivo).
function routes.serialize(list)
	local out = { "return {" }
	for _, r in ipairs(list) do
		out[#out + 1] = string.format("\t{ id = %d, name = %q, slots = {", r.id, r.name)
		for _, slot in ipairs(r.slots) do
			if slot.point ~= nil then
				out[#out + 1] = string.format("\t\t{ name = %q, point = { x = %.3f, y = %.3f, z = %.3f } },", slot.name, slot.point.x, slot.point.y, slot.point.z)
			else
				out[#out + 1] = string.format("\t\t{ name = %q },", slot.name)
			end
		end
		out[#out + 1] = "\t} },"
	end
	out[#out + 1] = "}"
	return table.concat(out, "\n")
end

-- Lê o texto gravado por serialize. Devolve a lista, ou nil e o motivo se o texto for inválido.
function routes.parse(src)
	if type(src) ~= "string" then
		return nil, "texto inválido"
	end
	local chunk, err
	if setfenv then
		chunk, err = loadstring(src)
		if chunk then
			setfenv(chunk, {})
		end
	else
		chunk, err = load(src, "rotas", "t", {})
	end
	if not chunk then
		return nil, err
	end
	local ok, data = pcall(chunk)
	if not ok or type(data) ~= "table" then
		return nil, "conteúdo inválido"
	end
	local list = {}
	for _, raw in ipairs(data) do
		if type(raw) ~= "table" or type(raw.name) ~= "string" or type(raw.slots) ~= "table" or #raw.slots < 2 then
			return nil, "rota inválida"
		end
		local names = {}
		for i, s in ipairs(raw.slots) do
			if type(s) ~= "table" or type(s.name) ~= "string" then
				return nil, "ponto inválido"
			end
			names[i] = s.name
		end
		local r = routes.new(raw.id or (#list + 1), raw.name, names)
		for i, s in ipairs(raw.slots) do
			if s.point ~= nil then
				if not validPoint(s.point) then
					return nil, "coordenada inválida"
				end
				routes.setPoint(r, i, s.point)
			end
		end
		list[#list + 1] = r
	end
	return list
end

return routes
