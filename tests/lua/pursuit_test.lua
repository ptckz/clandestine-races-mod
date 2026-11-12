-- Testes do módulo pursuit: quantos policiais, quem persegue quem e quando a perseguição para.

local pursuit = require("clandestine.pursuit")

local CFG = { pursuersPerStar = 1, maxPursuers = 4, maxRange = 1000 }

local function at(x)
	return { x = x, y = 0, z = 0 }
end

local function racer(id, finished)
	return { id = id, finished = finished or false }
end

T.test("sem estrelas, não há policiais", function()
	T.eq(pursuit.desiredCount(0, CFG), 0)
end)

T.test("quantidade de policiais cresce com as estrelas", function()
	T.eq(pursuit.desiredCount(1, CFG), 1)
	T.eq(pursuit.desiredCount(3, CFG), 3)
end)

T.test("quantidade de policiais respeita o limite máximo", function()
	local cfg = { pursuersPerStar = 2, maxPursuers = 4, maxRange = 1000 }
	T.eq(pursuit.desiredCount(5, cfg), 4)
end)

T.test("estrelas fora de 0 a 5 são rejeitadas", function()
	T.errors(function() pursuit.desiredCount(6, CFG) end)
	T.errors(function() pursuit.desiredCount(-1, CFG) end)
end)

T.test("configuração inválida é rejeitada", function()
	T.errors(function() pursuit.new({ pursuersPerStar = 0, maxPursuers = 4, maxRange = 1000 }) end)
	T.errors(function() pursuit.new({ pursuersPerStar = 1, maxPursuers = 0, maxRange = 1000 }) end)
	T.errors(function() pursuit.new({ pursuersPerStar = 1, maxPursuers = 4, maxRange = 0 }) end)
end)

T.test("policial persegue o corredor mais próximo", function()
	local racers = { racer("A"), racer("B") }
	local pos = { A = at(500), B = at(100) }
	local map = pursuit.assign(CFG, { "P1" }, racers, pos, at(0))
	T.eq(map.P1, "B")
end)

T.test("corredores finalizados não são alvo", function()
	local racers = { racer("A", true), racer("B") }
	local pos = { A = at(10), B = at(300) }
	local map = pursuit.assign(CFG, { "P1" }, racers, pos, at(0))
	T.eq(map.P1, "B", "A já chegou")
end)

T.test("sem corredores na pista, não há perseguição (fim da corrida)", function()
	local racers = { racer("A", true), racer("B", true) }
	local pos = { A = at(10), B = at(20) }
	local map = pursuit.assign(CFG, { "P1", "P2" }, racers, pos, at(0))
	T.eq(next(map), nil, "nenhum policial atribuído")
end)

T.test("corredores fora do alcance são ignorados", function()
	local racers = { racer("A") }
	local pos = { A = at(5000) }
	local map = pursuit.assign(CFG, { "P1" }, racers, pos, at(0))
	T.eq(next(map), nil)
end)

T.test("corredor sem posição conhecida não é alvo", function()
	local racers = { racer("A"), racer("B") }
	local pos = { B = at(400) }
	local map = pursuit.assign(CFG, { "P1" }, racers, pos, at(0))
	T.eq(map.P1, "B")
end)

T.test("policiais se distribuem entre corredores quando há opção", function()
	local racers = { racer("A"), racer("B") }
	local pos = { A = at(100), B = at(120) }
	local map = pursuit.assign(CFG, { "P1", "P2" }, racers, pos, at(0))
	T.truthy(map.P1 ~= nil and map.P2 ~= nil, "os dois têm alvo")
	T.truthy(map.P1 ~= map.P2, "e alvos diferentes")
end)

T.test("mais policiais que corredores: o excedente vai para o mais próximo", function()
	local racers = { racer("A") }
	local pos = { A = at(100) }
	local map = pursuit.assign(CFG, { "P1", "P2", "P3" }, racers, pos, at(0))
	T.eq(map.P1, "A")
	T.eq(map.P2, "A")
	T.eq(map.P3, "A")
end)

T.test("a atribuição é determinística", function()
	local racers = { racer("A"), racer("B") }
	local pos = { A = at(100), B = at(120) }
	local m1 = pursuit.assign(CFG, { "P1", "P2" }, racers, pos, at(0))
	local m2 = pursuit.assign(CFG, { "P1", "P2" }, racers, pos, at(0))
	T.eq(m1.P1, m2.P1)
	T.eq(m1.P2, m2.P2)
end)
