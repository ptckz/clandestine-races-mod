-- Percurso aleatório da corrida: sorteia checkpoints encadeados a partir do ponto de largada.
-- Lógica pura. O gerador de números é injetado (rng) para que o sorteio seja reproduzível.

local route = {}

local TWO_PI = 2 * math.pi
local MAX_TRIES_PER_POINT = 20

local function inside(p, bounds)
	return p.x >= bounds.minX and p.x <= bounds.maxX
		and p.y >= bounds.minY and p.y <= bounds.maxY
end

-- Sorteia `count` checkpoints a partir de `start`. Cada passo tem distância entre
-- `minStep` e `maxStep` e direção aleatória. O último ponto é a chegada.
-- Devolve a lista de pontos, ou nil se não conseguir sortear dentro dos limites.
function route.generate(start, bounds, rng, opts)
	local count = opts.count
	local minStep = opts.minStep
	local maxStep = opts.maxStep
	if count < 1 or minStep <= 0 or maxStep < minStep then
		error("parâmetros do percurso inválidos", 2)
	end

	local points = {}
	local prev = start
	for _ = 1, count do
		local placed = nil
		for _ = 1, MAX_TRIES_PER_POINT do
			local angle = rng() * TWO_PI
			local dist = minStep + rng() * (maxStep - minStep)
			local p = {
				x = prev.x + math.cos(angle) * dist,
				y = prev.y + math.sin(angle) * dist,
				z = start.z,
			}
			if inside(p, bounds) then
				placed = p
				break
			end
		end
		if placed == nil then
			return nil
		end
		points[#points + 1] = placed
		prev = placed
	end
	return points
end

return route
