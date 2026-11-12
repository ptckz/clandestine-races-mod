-- Testes do módulo dialogue: conversa com o negociador, escolhas, recusas e saída.

local dialogue = require("clandestine.dialogue")

local CTX = { routeName = "Thieves Landing > Cattail Pond" }

T.test("a conversa começa na saudação, com o cursor na primeira opção", function()
	local s = dialogue.new()
	T.eq(s.node, "greet")
	T.eq(s.cursor, 1)
end)

T.test("a saudação cita o nome da rota e quem fala é o negociador", function()
	local v = dialogue.view(dialogue.new(), CTX)
	T.eq(v.speaker, "Negociador")
	T.truthy(v.text:find("Thieves Landing > Cattail Pond", 1, true), "texto com o nome da rota")
end)

T.test("a saudação oferece perguntar as regras, correr ou sair", function()
	local v = dialogue.view(dialogue.new(), CTX)
	T.eq(#v.options, 3)
	T.eq(v.options[1].label, "Quais são as regras?")
	T.eq(v.options[3].label, "Agora não.")
end)

T.test("o cursor se move sem sair das opções", function()
	local s = dialogue.new()
	s = dialogue.move(s, -1, CTX)
	T.eq(s.cursor, 1, "não passa do primeiro")
	for _ = 1, 10 do s = dialogue.move(s, 1, CTX) end
	T.eq(s.cursor, 3, "não passa do último")
end)

T.test("mover o cursor não altera o estado original", function()
	local s = dialogue.new()
	dialogue.move(s, 1, CTX)
	T.eq(s.cursor, 1)
end)

T.test("perguntar as regras leva ao nó das regras, sem ação", function()
	local s, action = dialogue.choose(dialogue.new(), CTX)
	T.eq(s.node, "rules")
	T.eq(s.cursor, 1)
	T.eq(action, nil)
	T.truthy(dialogue.view(s, CTX).text:find("ordem", 1, true), "as regras falam da ordem dos pontos")
end)

T.test("aceitar correr devolve a ação start", function()
	local s = dialogue.move(dialogue.new(), 1, CTX)
	local _, action = dialogue.choose(s, CTX)
	T.eq(action, "start")
end)

T.test("dizer 'agora não' devolve a ação close", function()
	local s = dialogue.move(dialogue.move(dialogue.new(), 1, CTX), 1, CTX)
	local _, action = dialogue.choose(s, CTX)
	T.eq(action, "close")
end)

T.test("das regras dá para aceitar correr ou voltar", function()
	local rules = dialogue.choose(dialogue.new(), CTX)
	local _, start = dialogue.choose(rules, CTX)
	T.eq(start, "start")
	local back = dialogue.move(rules, 1, CTX)
	local greet, action = dialogue.choose(back, CTX)
	T.eq(greet.node, "greet")
	T.eq(action, nil)
end)

T.test("cada motivo de recusa tem uma resposta própria do negociador", function()
	local reasons = { "need_horse", "route_incomplete", "too_far", "busy" }
	local seen = {}
	for _, reason in ipairs(reasons) do
		local s = dialogue.refuse(dialogue.new(), reason)
		T.eq(s.node, reason)
		local text = dialogue.view(s, CTX).text
		T.truthy(#text > 0, "texto para " .. reason)
		T.falsy(seen[text], "resposta repetida para " .. reason)
		seen[text] = true
	end
end)

T.test("depois de uma recusa, o jogador pode voltar à saudação", function()
	local s = dialogue.refuse(dialogue.new(), "need_horse")
	local back, action = dialogue.choose(s, CTX)
	T.eq(back.node, "greet")
	T.eq(action, nil)
end)

T.test("motivo de recusa desconhecido é rejeitado", function()
	T.errors(function() dialogue.refuse(dialogue.new(), "inventado") end)
end)

T.test("voltar na saudação encerra a conversa", function()
	local _, action = dialogue.back(dialogue.new())
	T.eq(action, "close")
end)

T.test("voltar em outro nó leva à saudação sem encerrar", function()
	local s = dialogue.refuse(dialogue.new(), "busy")
	local back, action = dialogue.back(s)
	T.eq(back.node, "greet")
	T.eq(action, nil)
end)

T.test("o texto da saudação muda com o nome da rota", function()
	local a = dialogue.view(dialogue.new(), { routeName = "Rota A" }).text
	local b = dialogue.view(dialogue.new(), { routeName = "Rota B" }).text
	T.falsy(a == b)
end)
