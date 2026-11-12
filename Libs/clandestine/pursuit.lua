-- Perseguição policial: quantos policiais aparecem e quem cada um persegue.
-- Lógica pura: recebe posições e devolve uma atribuição. Não chama natives.

local course = require("clandestine.course")

local pursuit = {}

local function isStarLevel(n)
	return type(n) == "number" and n % 1 == 0 and n >= 0 and n <= 5
end

-- cfg.pursuersPerStar: policiais por estrela de procura.
-- cfg.maxPursuers: teto de policiais ao mesmo tempo.
-- cfg.maxRange: distância máxima, em unidades do jogo, para a polícia considerar um corredor.
function pursuit.new(cfg)
	if type(cfg.pursuersPerStar) ~= "number" or cfg.pursuersPerStar <= 0 then
		error("policiais por estrela precisa ser maior que zero", 2)
	end
	if type(cfg.maxPursuers) ~= "number" or cfg.maxPursuers <= 0 then
		error("o máximo de policiais precisa ser maior que zero", 2)
	end
	if type(cfg.maxRange) ~= "number" or cfg.maxRange <= 0 then
		error("o alcance da polícia precisa ser maior que zero", 2)
	end
	return {
		pursuersPerStar = cfg.pursuersPerStar,
		maxPursuers = cfg.maxPursuers,
		maxRange = cfg.maxRange,
	}
end

-- Quantos policiais devem estar na perseguição para este nível de procura.
function pursuit.desiredCount(stars, cfg)
	if not isStarLevel(stars) then
		error("estrelas precisam ser um inteiro de 0 a 5", 2)
	end
	local n = stars * cfg.pursuersPerStar
	if n > cfg.maxPursuers then
		n = cfg.maxPursuers
	end
	return n
end

-- Decide quem persegue quem.
-- `pursuers`: lista de ids de policiais, todos saindo de `base`.
-- `racers`: lista de corredores ({ id, finished }).
-- `positions`: posição atual de cada corredor, indexada pelo id.
-- Retorna uma tabela pursuerId -> racerId. Policiais sem alvo ficam de fora.
function pursuit.assign(cfg, pursuers, racers, positions, base)
	-- Candidatos: corredores ainda na pista, com posição conhecida e dentro do alcance.
	local candidates = {}
	for _, r in ipairs(racers) do
		local pos = positions[r.id]
		if not r.finished and pos ~= nil then
			local d = course.distance(base, pos)
			if d <= cfg.maxRange then
				candidates[#candidates + 1] = { id = r.id, dist = d }
			end
		end
	end
	if #candidates == 0 then
		return {}
	end
	table.sort(candidates, function(a, b)
		if a.dist ~= b.dist then
			return a.dist < b.dist
		end
		return tostring(a.id) < tostring(b.id)
	end)

	-- Cada policial vai para o corredor com menos perseguidores; em empate, o mais próximo.
	local count = {}
	for _, c in ipairs(candidates) do
		count[c.id] = 0
	end
	local map = {}
	local limit = math.min(#pursuers, cfg.maxPursuers)
	for i = 1, limit do
		local best = nil
		for _, c in ipairs(candidates) do
			if best == nil or count[c.id] < count[best.id] then
				best = c
			end
		end
		map[pursuers[i]] = best.id
		count[best.id] = count[best.id] + 1
	end
	return map
end

return pursuit
