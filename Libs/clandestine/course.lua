-- Lógica pura de corrida: sequência de checkpoints, chegada e ranking.
-- Não chama natives. Compatível com Lua 5.1 (RedLua) e 5.3 (fengari nos testes).

local course = {}

-- Distância 3D entre dois pontos {x, y, z}.
function course.distance(a, b)
	local dx = a.x - b.x
	local dy = a.y - b.y
	local dz = a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Distância horizontal (ignora a altura). O terreno varia, então checkpoints usam esta.
function course.distance2d(a, b)
	local dx = a.x - b.x
	local dy = a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end

-- Cria uma corrida. `checkpoints` é uma lista ordenada de pontos; o último é a chegada.
-- `radius` é a distância em metros para considerar que o corredor passou pelo checkpoint.
function course.new(checkpoints, radius)
	if type(checkpoints) ~= "table" or #checkpoints < 2 then
		error("a corrida precisa de pelo menos 2 checkpoints (largada e chegada)", 2)
	end
	if type(radius) ~= "number" or radius <= 0 then
		error("o raio do checkpoint precisa ser maior que zero", 2)
	end
	return {
		checkpoints = checkpoints,
		radius = radius,
		finishCount = 0,
	}
end

-- Estado de um corredor. Começa no primeiro checkpoint, ainda não finalizado.
function course.newRacer(id)
	return {
		id = id,
		nextIndex = 1,
		finished = false,
		finishOrder = nil,
	}
end

-- Registra a posição atual de um corredor.
-- Retorna "none" (nada aconteceu), "checkpoint" (passou por um checkpoint intermediário)
-- ou "finished" (cruzou a chegada; acontece uma única vez por corredor).
function course.advance(c, racer, pos)
	if racer.finished then
		return "none"
	end
	local target = c.checkpoints[racer.nextIndex]
	if course.distance2d(pos, target) > c.radius then
		return "none"
	end
	if racer.nextIndex == #c.checkpoints then
		racer.finished = true
		c.finishCount = c.finishCount + 1
		racer.finishOrder = c.finishCount
		return "finished"
	end
	racer.nextIndex = racer.nextIndex + 1
	return "checkpoint"
end

-- Ordena os corredores do primeiro ao último.
-- `positions[id]` é a posição atual de cada corredor (usada para quem ainda está na pista).
-- Finalizados vêm primeiro, na ordem de chegada. Na pista: mais checkpoints primeiro;
-- em empate, quem está mais perto do próximo checkpoint; por último, o id.
function course.ranking(c, racers, positions)
	local list = {}
	for i, r in ipairs(racers) do
		list[i] = r
	end

	local function distToNext(r)
		local pos = positions[r.id]
		if pos == nil then
			return math.huge
		end
		return course.distance2d(pos, c.checkpoints[r.nextIndex])
	end

	table.sort(list, function(a, b)
		if a.finished ~= b.finished then
			return a.finished
		end
		if a.finished then
			return a.finishOrder < b.finishOrder
		end
		if a.nextIndex ~= b.nextIndex then
			return a.nextIndex > b.nextIndex
		end
		local da, db = distToNext(a), distToNext(b)
		if da ~= db then
			return da < db
		end
		return tostring(a.id) < tostring(b.id)
	end)

	return list
end

return course
