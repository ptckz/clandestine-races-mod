-- Testes do módulo betting: validação de aposta, saldo e pagamento.

local betting = require("clandestine.betting")

local CONFIG = { minBet = 10, maxBet = 500, payoutMultiplier = 2 }

local function state(balance)
	return { balance = balance, bets = {} }
end

T.test("configuração válida é aceita", function()
	local cfg = betting.newConfig(CONFIG)
	T.eq(cfg.minBet, 10)
	T.eq(cfg.maxBet, 500)
end)

T.test("configuração inválida é rejeitada", function()
	T.errors(function() betting.newConfig({ minBet = 0, maxBet = 500, payoutMultiplier = 2 }) end, "mínimo zero")
	T.errors(function() betting.newConfig({ minBet = 100, maxBet = 50, payoutMultiplier = 2 }) end, "máximo menor que mínimo")
	T.errors(function() betting.newConfig({ minBet = 10, maxBet = 500, payoutMultiplier = 1 }) end, "pagamento não maior que 1")
end)

T.test("aposta válida é aceita", function()
	local r = betting.validate(CONFIG, { horseId = 2, amount = 50 }, 1000)
	T.eq(r.ok, true)
end)

T.test("valor abaixo do mínimo é rejeitado", function()
	T.eq(betting.validate(CONFIG, { horseId = 2, amount = 9 }, 1000).reason, "below_min")
end)

T.test("valor acima do máximo é rejeitado", function()
	T.eq(betting.validate(CONFIG, { horseId = 2, amount = 501 }, 1000).reason, "above_max")
end)

T.test("valor não inteiro ou não numérico é rejeitado", function()
	T.eq(betting.validate(CONFIG, { horseId = 2, amount = 12.5 }, 1000).reason, "not_integer")
	T.eq(betting.validate(CONFIG, { horseId = 2, amount = "50" }, 1000).reason, "not_integer")
	T.eq(betting.validate(CONFIG, { horseId = 2 }, 1000).reason, "not_integer")
end)

T.test("saldo insuficiente é rejeitado", function()
	T.eq(betting.validate(CONFIG, { horseId = 2, amount = 100 }, 99).reason, "insufficient_funds")
end)

T.test("aposta sem cavalo é rejeitada", function()
	T.eq(betting.validate(CONFIG, { amount = 50 }, 1000).reason, "no_horse")
end)

T.test("não é possível apostar depois que a corrida começou", function()
	T.eq(betting.validate(CONFIG, { horseId = 1, amount = 20 }, 1000, true).reason, "race_started")
end)

T.test("place debita o valor e registra a aposta", function()
	local r = betting.place(CONFIG, state(1000), { horseId = 3, amount = 50 })
	T.eq(r.ok, true)
	T.eq(r.state.balance, 950, "saldo depois do débito")
	T.eq(#r.state.bets, 1)
	T.eq(r.state.bets[1].horseId, 3)
	T.eq(r.state.bets[1].amount, 50)
end)

T.test("place recusado não muda o estado nem o saldo", function()
	local s = state(99)
	local r = betting.place(CONFIG, s, { horseId = 2, amount = 100 })
	T.eq(r.ok, false)
	T.eq(s.balance, 99, "saldo original intacto")
	T.eq(#s.bets, 0, "nenhuma aposta registrada")
end)

T.test("saldo nunca fica negativo após várias apostas", function()
	local s = state(100)
	local r1 = betting.place(CONFIG, s, { horseId = 1, amount = 60 })
	local r2 = betting.place(CONFIG, r1.state, { horseId = 2, amount = 60 })
	T.eq(r1.ok, true)
	T.eq(r2.ok, false, "segunda aposta excede o saldo restante de 40")
	T.truthy(r2.state.balance >= 0)
end)

T.test("pagamento: vencedor recebe valor vezes o multiplicador", function()
	local r = betting.place(CONFIG, state(1000), { horseId = 3, amount = 50 })
	local s = betting.settle(CONFIG, r.state.bets, 3)
	T.eq(s.credit, 100, "50 apostados, multiplicador 2")
end)

T.test("pagamento: perdedor não recebe nada", function()
	local r = betting.place(CONFIG, state(1000), { horseId = 3, amount = 50 })
	T.eq(betting.settle(CONFIG, r.state.bets, 4).credit, 0)
end)

T.test("pagamento soma várias apostas, só nas do vencedor", function()
	local s = state(1000)
	s = betting.place(CONFIG, s, { horseId = 1, amount = 20 }).state
	s = betting.place(CONFIG, s, { horseId = 2, amount = 30 }).state
	s = betting.place(CONFIG, s, { horseId = 1, amount = 10 }).state
	local r = betting.settle(CONFIG, s.bets, 1)
	T.eq(r.credit, 60, "(20 + 10) x 2")
	T.eq(r.netProfit, 30, "lucro = crédito - valor apostado no vencedor")
end)

T.test("sem apostas, o pagamento é zero", function()
	T.eq(betting.settle(CONFIG, {}, 1).credit, 0)
end)
