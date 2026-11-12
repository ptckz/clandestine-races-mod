-- Lógica pura de apostas: validação, débito e pagamento.
-- Não chama natives. O saldo é recebido e devolvido como número (o débito real é feito pelo adaptador).

local betting = {}

-- Valida a configuração de limites e pagamento.
function betting.newConfig(cfg)
	if type(cfg.minBet) ~= "number" or cfg.minBet <= 0 then
		error("aposta mínima precisa ser maior que zero", 2)
	end
	if type(cfg.maxBet) ~= "number" or cfg.maxBet < cfg.minBet then
		error("aposta máxima precisa ser maior ou igual à mínima", 2)
	end
	if type(cfg.payoutMultiplier) ~= "number" or cfg.payoutMultiplier <= 1 then
		error("o multiplicador de pagamento precisa ser maior que 1", 2)
	end
	return {
		minBet = cfg.minBet,
		maxBet = cfg.maxBet,
		payoutMultiplier = cfg.payoutMultiplier,
	}
end

-- Retorna { ok = true } ou { ok = false, reason = "..." }.
-- Ordem das checagens: corrida já começou, cavalo, valor, limites e saldo.
function betting.validate(cfg, bet, balance, raceStarted)
	if raceStarted then
		return { ok = false, reason = "race_started" }
	end
	if bet.horseId == nil then
		return { ok = false, reason = "no_horse" }
	end
	local amount = bet.amount
	if type(amount) ~= "number" or amount % 1 ~= 0 then
		return { ok = false, reason = "not_integer" }
	end
	if amount < cfg.minBet then
		return { ok = false, reason = "below_min" }
	end
	if amount > cfg.maxBet then
		return { ok = false, reason = "above_max" }
	end
	if amount > balance then
		return { ok = false, reason = "insufficient_funds" }
	end
	return { ok = true }
end

-- Tenta registrar uma aposta. `state` = { balance = n, bets = { ... } }.
-- Se recusada, devolve o próprio `state` sem alterações.
function betting.place(cfg, state, bet, raceStarted)
	local check = betting.validate(cfg, bet, state.balance, raceStarted)
	if not check.ok then
		return { ok = false, reason = check.reason, state = state }
	end
	local bets = {}
	for i, b in ipairs(state.bets) do
		bets[i] = b
	end
	bets[#bets + 1] = { horseId = bet.horseId, amount = bet.amount }
	return {
		ok = true,
		state = { balance = state.balance - bet.amount, bets = bets },
	}
end

-- Calcula o pagamento depois da corrida. Vencedor recebe valor x multiplicador.
-- `netProfit` = crédito menos o valor apostado no vencedor.
function betting.settle(cfg, bets, winnerId)
	local credit = 0
	local staked = 0
	for _, b in ipairs(bets) do
		if b.horseId == winnerId then
			credit = credit + b.amount * cfg.payoutMultiplier
			staked = staked + b.amount
		end
	end
	return { credit = credit, netProfit = credit - staked }
end

return betting
