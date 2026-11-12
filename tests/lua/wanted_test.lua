-- Testes do módulo wanted: estrelas de procura, escalonamento na corrida e alerta.

local wanted = require("clandestine.wanted")

local CFG = { escalateEverySeconds = 30, clearOnFinish = true }

T.test("configuração inválida é rejeitada", function()
	T.errors(function() wanted.new({ escalateEverySeconds = 0, clearOnFinish = true }) end, "intervalo zero")
	T.errors(function() wanted.new({ escalateEverySeconds = 30 }) end, "clearOnFinish ausente")
end)

T.test("começa sem estrelas e sem corrida ativa", function()
	local w = wanted.new(CFG)
	T.eq(wanted.stars(w), 0)
	T.falsy(w.raceActive)
end)

T.test("admin define estrelas de 0 a 5", function()
	local w = wanted.new(CFG)
	for n = 0, 5 do
		T.eq(wanted.setStars(w, n).ok, true, "estrelas " .. n)
		T.eq(wanted.stars(w), n)
	end
end)

T.test("valor fora de 0 a 5 é recusado e não muda as estrelas", function()
	local w = wanted.new(CFG)
	wanted.setStars(w, 3)
	T.eq(wanted.setStars(w, 6).reason, "out_of_range")
	T.eq(wanted.setStars(w, -1).reason, "out_of_range")
	T.eq(wanted.setStars(w, 2.5).reason, "out_of_range")
	T.eq(wanted.stars(w), 3)
end)

T.test("admin pode voltar a zero", function()
	local w = wanted.new(CFG)
	wanted.setStars(w, 4)
	wanted.setStars(w, 0)
	T.eq(wanted.stars(w), 0)
end)

T.test("durante a corrida, as estrelas sobem com o tempo", function()
	local w = wanted.new(CFG)
	wanted.setStars(w, 1)
	wanted.startRace(w, 1000)
	T.eq(wanted.update(w, 1000), 1, "no início, sem escalonar")
	T.eq(wanted.update(w, 1029), 1, "antes do primeiro intervalo")
	T.eq(wanted.update(w, 1030), 2, "após 30 s")
	T.eq(wanted.update(w, 1061), 3, "após 61 s")
end)

T.test("escalonamento para em 5 estrelas", function()
	local w = wanted.new(CFG)
	wanted.startRace(w, 0)
	T.eq(wanted.update(w, 100000), 5)
end)

T.test("durante a corrida, as estrelas nunca diminuem sozinhas", function()
	local w = wanted.new(CFG)
	wanted.startRace(w, 0)
	local last = 0
	for t = 0, 300, 7 do
		local now = wanted.update(w, t)
		T.truthy(now >= last, "caiu de " .. last .. " para " .. now .. " em t=" .. t)
		last = now
	end
end)

T.test("admin pode alterar as estrelas no meio da corrida", function()
	local w = wanted.new(CFG)
	wanted.startRace(w, 0)
	wanted.update(w, 90)
	T.eq(wanted.stars(w), 3)
	wanted.setStars(w, 1, 90)
	T.eq(wanted.stars(w), 1, "admin reduz")
	T.eq(wanted.update(w, 90), 1, "sem tempo novo, continua em 1")
	T.eq(wanted.update(w, 120), 2, "volta a escalonar a partir do valor do admin")
end)

T.test("alerta da polícia é emitido uma única vez por corrida", function()
	local w = wanted.new(CFG)
	wanted.startRace(w, 0)
	T.eq(wanted.alert(w), true, "primeiro alerta")
	T.eq(wanted.alert(w), false, "sem alerta repetido")
end)

T.test("nova corrida reinicia o alerta", function()
	local w = wanted.new(CFG)
	wanted.startRace(w, 0)
	wanted.alert(w)
	wanted.stopRace(w)
	wanted.startRace(w, 500)
	T.eq(wanted.alert(w), true)
end)

T.test("fim da corrida zera as estrelas quando clearOnFinish é verdadeiro", function()
	local w = wanted.new({ escalateEverySeconds = 30, clearOnFinish = true })
	wanted.startRace(w, 0)
	wanted.update(w, 60)
	wanted.stopRace(w)
	T.eq(wanted.stars(w), 0)
	T.falsy(w.raceActive)
end)

T.test("fim da corrida mantém as estrelas quando clearOnFinish é falso", function()
	local w = wanted.new({ escalateEverySeconds = 30, clearOnFinish = false })
	wanted.startRace(w, 0)
	wanted.update(w, 60)
	wanted.stopRace(w)
	T.eq(wanted.stars(w), 2)
end)

T.test("atualizar sem corrida ativa não muda as estrelas", function()
	local w = wanted.new(CFG)
	wanted.setStars(w, 2)
	T.eq(wanted.update(w, 9999), 2)
end)
