-- Testes do módulo course: checkpoints em ordem, chegada única e ranking.

local course = require("clandestine.course")

local CPS = {
	{ x = 0, y = 0, z = 0 },
	{ x = 100, y = 0, z = 0 },
	{ x = 200, y = 0, z = 0 },
}

local function at(x)
	return { x = x, y = 0, z = 0 }
end

T.test("distância 3D entre dois pontos", function()
	T.near(course.distance({ x = 0, y = 0, z = 0 }, { x = 3, y = 4, z = 0 }), 5)
end)

T.test("novo corredor começa no primeiro checkpoint, não finalizado", function()
	local r = course.newRacer("A")
	T.eq(r.nextIndex, 1)
	T.falsy(r.finished)
end)

T.test("corredor só avança ao chegar perto do checkpoint esperado", function()
	local c = course.new(CPS, 5)
	local r = course.newRacer("A")
	T.eq(course.advance(c, r, at(50)), "none", "longe do checkpoint 1")
	T.eq(r.nextIndex, 1)
	T.eq(course.advance(c, r, at(2)), "checkpoint")
	T.eq(r.nextIndex, 2)
end)

T.test("checkpoints fora de ordem não contam", function()
	local c = course.new(CPS, 5)
	local r = course.newRacer("A")
	-- Passa pelo checkpoint 2 sem ter passado pelo 1: não deve avançar.
	T.eq(course.advance(c, r, at(100)), "none")
	T.eq(r.nextIndex, 1)
end)

T.test("chegada é detectada uma única vez", function()
	local c = course.new(CPS, 5)
	local r = course.newRacer("A")
	course.advance(c, r, at(0))
	course.advance(c, r, at(100))
	T.eq(course.advance(c, r, at(200)), "finished")
	T.truthy(r.finished)
	T.eq(course.advance(c, r, at(200)), "none", "não deve finalizar de novo")
	T.eq(r.finishOrder, 1)
end)

T.test("ordem de chegada é registrada em sequência", function()
	local c = course.new(CPS, 5)
	local a = course.newRacer("A")
	local b = course.newRacer("B")
	for _, p in ipairs(CPS) do course.advance(c, a, p) end
	for _, p in ipairs(CPS) do course.advance(c, b, p) end
	T.eq(a.finishOrder, 1)
	T.eq(b.finishOrder, 2)
end)

T.test("ranking: finalizados vêm antes, na ordem de chegada", function()
	local c = course.new(CPS, 5)
	local a = course.newRacer("A")
	local b = course.newRacer("B")
	local d = course.newRacer("C")
	for _, p in ipairs(CPS) do course.advance(c, b, p) end
	for _, p in ipairs(CPS) do course.advance(c, a, p) end
	course.advance(c, d, CPS[1])
	local pos = { A = at(200), B = at(200), C = at(0) }
	local rank = course.ranking(c, { a, b, d }, pos)
	T.eq(rank[1].id, "B", "primeiro a chegar")
	T.eq(rank[2].id, "A", "segundo a chegar")
	T.eq(rank[3].id, "C", "ainda na pista")
end)

T.test("ranking de quem está na pista: mais checkpoints primeiro", function()
	local c = course.new(CPS, 5)
	local a = course.newRacer("A")
	local b = course.newRacer("B")
	course.advance(c, a, CPS[1])
	course.advance(c, b, CPS[1])
	course.advance(c, b, CPS[2])
	local rank = course.ranking(c, { a, b }, { A = at(10), B = at(150) })
	T.eq(rank[1].id, "B")
	T.eq(rank[2].id, "A")
end)

T.test("empate no mesmo checkpoint: quem está mais perto do próximo fica na frente", function()
	local c = course.new(CPS, 5)
	local a = course.newRacer("A")
	local b = course.newRacer("B")
	course.advance(c, a, CPS[1])
	course.advance(c, b, CPS[1])
	-- Os dois esperam o checkpoint 2 (x = 100). A está a 10, B a 90.
	local rank = course.ranking(c, { b, a }, { A = at(90), B = at(10) })
	T.eq(rank[1].id, "A", "A está a 10 do próximo checkpoint")
	T.eq(rank[2].id, "B")
end)

T.test("ranking com lista vazia não falha", function()
	local c = course.new(CPS, 5)
	T.eq(#course.ranking(c, {}, {}), 0)
end)

T.test("course.new rejeita menos de 2 checkpoints", function()
	T.errors(function() course.new({ CPS[1] }, 5) end)
end)

T.test("course.new rejeita raio não positivo", function()
	T.errors(function() course.new(CPS, 0) end)
	T.errors(function() course.new(CPS, -1) end)
end)

T.test("passar pelo checkpoint ignora a diferença de altura (terreno varia)", function()
	local c = course.new(CPS, 5)
	local r = course.newRacer("A")
	T.eq(course.advance(c, r, { x = 0, y = 0, z = 40 }), "checkpoint", "40 m acima, mas na mesma posição horizontal")
end)

T.test("distância horizontal ignora a altura", function()
	T.near(course.distance2d({ x = 0, y = 0, z = 0 }, { x = 3, y = 4, z = 100 }), 5)
end)

T.test("o corredor precisa passar por todos os checkpoints em ordem para chegar", function()
	local c = course.new(CPS, 5)
	local r = course.newRacer("A")
	T.eq(course.advance(c, r, { x = 200, y = 0, z = 0 }), "none", "chegada sem ter passado pelos anteriores")
	T.falsy(r.finished)
end)
