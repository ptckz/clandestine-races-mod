-- Estrelas de procura (0 a 5): ajuste pelo admin, escalonamento durante a corrida e alerta.
-- Lógica pura: o tempo (em segundos) é recebido como parâmetro. Não chama natives.

local wanted = {}

local MAX_STARS = 5

local function isValidStars(n)
	return type(n) == "number" and n % 1 == 0 and n >= 0 and n <= MAX_STARS
end

-- Cria o estado de procura.
-- cfg.escalateEverySeconds: a cada quantos segundos a polícia sobe 1 estrela na corrida.
-- cfg.clearOnFinish: se verdadeiro, as estrelas voltam a zero quando a corrida termina.
function wanted.new(cfg)
	if type(cfg.escalateEverySeconds) ~= "number" or cfg.escalateEverySeconds <= 0 then
		error("o intervalo de escalonamento precisa ser maior que zero", 2)
	end
	if type(cfg.clearOnFinish) ~= "boolean" then
		error("clearOnFinish precisa ser verdadeiro ou falso", 2)
	end
	return {
		cfg = cfg,
		current = 0,
		base = 0,
		raceActive = false,
		raceStartedAt = nil,
		alerted = false,
	}
end

function wanted.stars(w)
	return w.current
end

-- Admin define as estrelas. Se houver corrida ativa, o escalonamento recomeça a partir de `now`.
function wanted.setStars(w, n, now)
	if not isValidStars(n) then
		return { ok = false, reason = "out_of_range" }
	end
	w.current = n
	w.base = n
	if w.raceActive and now ~= nil then
		w.raceStartedAt = now
	end
	return { ok = true }
end

-- Começa a corrida: a partir daqui a polícia escalona e o alerta pode ser emitido.
function wanted.startRace(w, now)
	w.raceActive = true
	w.raceStartedAt = now
	w.base = w.current
	w.alerted = false
end

-- Atualiza as estrelas com base no tempo atual. Durante a corrida só sobe, nunca passa de 5.
function wanted.update(w, now)
	if not w.raceActive then
		return w.current
	end
	local steps = math.floor((now - w.raceStartedAt) / w.cfg.escalateEverySeconds)
	local computed = w.base + steps
	if computed > MAX_STARS then
		computed = MAX_STARS
	end
	if computed > w.current then
		w.current = computed
	end
	return w.current
end

-- Retorna true na primeira vez em cada corrida, para emitir o alerta da polícia uma única vez.
function wanted.alert(w)
	if not w.raceActive or w.alerted then
		return false
	end
	w.alerted = true
	return true
end

-- Termina a corrida. Conforme a configuração, zera as estrelas.
function wanted.stopRace(w)
	w.raceActive = false
	w.raceStartedAt = nil
	if w.cfg.clearOnFinish then
		w.current = 0
		w.base = 0
	end
end

return wanted
