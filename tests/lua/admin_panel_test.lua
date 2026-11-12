-- Testes do painel de admin: navegação por teclas e ações geradas.
-- O painel não desenha nada: recebe teclas e devolve (novo estado, ação).

local panel = require("clandestine.admin_panel")

local function readySpot(id, name)
	return { id = id, name = name, point = { x = 0, y = 0, z = 0 }, route = { {}, {} } }
end

local function unreadySpot(id, name)
	return { id = id, name = name, point = { x = 0, y = 0, z = 0 }, route = { {} } }
end

local function ctx(spotList, stars)
	return { spots = spotList or {}, currentStars = stars or 0 }
end

T.test("painel começa no menu principal, com cursor no primeiro item", function()
	local s = panel.new()
	T.eq(s.page, "menu")
	T.eq(s.cursor, 1)
end)

T.test("menu tem 4 opções", function()
	T.eq(panel.itemCount(panel.new(), ctx()), 4)
end)

T.test("cursor sobe e desce sem sair dos limites", function()
	local s = panel.new()
	s = panel.handle(s, "up", ctx())
	T.eq(s.cursor, 1, "não sobe além do primeiro")
	s = panel.handle(s, "down", ctx())
	s = panel.handle(s, "down", ctx())
	T.eq(s.cursor, 3)
	for _ = 1, 10 do s = panel.handle(s, "down", ctx()) end
	T.eq(s.cursor, 4, "não desce além do último")
end)

T.test("enter em Locais de largada abre a página de locais", function()
	local s = panel.new()
	s = panel.handle(s, "enter", ctx())
	T.eq(s.page, "spots")
	T.eq(s.cursor, 1)
end)

T.test("enter em Nível de procura abre a página de estrelas, começando no valor atual", function()
	local s = panel.new()
	s = panel.handle(s, "down", ctx())
	local r = panel.handle(s, "enter", ctx({}, 3))
	T.eq(r.page, "stars")
	T.eq(r.targetStars, 3)
end)

T.test("enter em Fechar emite ação close", function()
	local s = panel.new()
	s = panel.handle(s, "down", ctx())
	s = panel.handle(s, "down", ctx())
	s = panel.handle(s, "down", ctx())
	local r, action = panel.handle(s, "enter", ctx())
	T.eq(action.type, "close")
	T.eq(r.page, "menu")
end)

T.test("back no menu principal fecha o painel", function()
	local _, action = panel.handle(panel.new(), "back", ctx())
	T.eq(action.type, "close")
end)

T.test("back em outra página volta ao menu sem fechar", function()
	local s = panel.handle(panel.new(), "enter", ctx())
	local r, action = panel.handle(s, "back", ctx())
	T.eq(r.page, "menu")
	T.eq(action, nil)
end)

T.test("tecla add na página de locais emite add_spot_here", function()
	local s = panel.handle(panel.new(), "enter", ctx())
	local _, action = panel.handle(s, "add", ctx())
	T.eq(action.type, "add_spot_here")
end)

T.test("tecla delete remove o local selecionado", function()
	local list = { readySpot(7, "Valentine"), readySpot(9, "Strawberry") }
	local s = panel.handle(panel.new(), "enter", ctx(list))
	s = panel.handle(s, "down", ctx(list))
	local _, action = panel.handle(s, "delete", ctx(list))
	T.eq(action.type, "remove_spot")
	T.eq(action.id, 9)
end)

T.test("delete sem nenhum local não emite ação", function()
	local s = panel.handle(panel.new(), "enter", ctx({}))
	local _, action = panel.handle(s, "delete", ctx({}))
	T.eq(action, nil)
end)

T.test("enter em um local abre a página do local com o id selecionado", function()
	local list = { readySpot(7, "Valentine") }
	local s = panel.handle(panel.new(), "enter", ctx(list))
	local r = panel.handle(s, "enter", ctx(list))
	T.eq(r.page, "spot")
	T.eq(r.selectedSpotId, 7)
end)

T.test("enter em Adicionar checkpoint emite add_checkpoint para o local", function()
	local list = { readySpot(7, "Valentine") }
	local s = panel.handle(panel.new(), "enter", ctx(list))
	s = panel.handle(s, "enter", ctx(list))
	local _, action = panel.handle(s, "enter", ctx(list))
	T.eq(action.type, "add_checkpoint")
	T.eq(action.id, 7)
end)

T.test("setas na página de estrelas ajustam de 0 a 5", function()
	local s = panel.handle(panel.new(), "down", ctx())
	s = panel.handle(s, "enter", ctx({}, 4))
	s = panel.handle(s, "up", ctx({}, 4))
	T.eq(s.targetStars, 5)
	s = panel.handle(s, "up", ctx({}, 4))
	T.eq(s.targetStars, 5, "não passa de 5")
	for _ = 1, 10 do s = panel.handle(s, "down", ctx({}, 4)) end
	T.eq(s.targetStars, 0, "não desce abaixo de 0")
end)

T.test("enter na página de estrelas emite set_stars com o valor escolhido", function()
	local s = panel.handle(panel.new(), "down", ctx())
	s = panel.handle(s, "enter", ctx({}, 0))
	s = panel.handle(s, "up", ctx({}, 0))
	s = panel.handle(s, "up", ctx({}, 0))
	local _, action = panel.handle(s, "enter", ctx({}, 0))
	T.eq(action.type, "set_stars")
	T.eq(action.stars, 2)
end)

T.test("iniciar corrida com percurso pronto emite start_race", function()
	local list = { readySpot(7, "Valentine") }
	local s = panel.handle(panel.new(), "down", ctx(list))
	s = panel.handle(s, "down", ctx(list))
	s = panel.handle(s, "enter", ctx(list))
	T.eq(s.page, "race")
	local _, action = panel.handle(s, "enter", ctx(list))
	T.eq(action.type, "start_race")
	T.eq(action.id, 7)
end)

T.test("iniciar corrida com percurso incompleto não emite ação e mostra aviso", function()
	local list = { unreadySpot(7, "Valentine") }
	local s = panel.handle(panel.new(), "down", ctx(list))
	s = panel.handle(s, "down", ctx(list))
	s = panel.handle(s, "enter", ctx(list))
	local r, action = panel.handle(s, "enter", ctx(list))
	T.eq(action, nil)
	T.truthy(r.message ~= "", "aviso para o admin")
end)

T.test("página de corrida sem locais não emite ação", function()
	local s = panel.handle(panel.new(), "down", ctx({}))
	s = panel.handle(s, "down", ctx({}))
	s = panel.handle(s, "enter", ctx({}))
	local _, action = panel.handle(s, "enter", ctx({}))
	T.eq(action, nil)
end)

T.test("tecla desconhecida não muda o estado", function()
	local s = panel.new()
	local r, action = panel.handle(s, "xyz", ctx())
	T.eq(r.page, "menu")
	T.eq(r.cursor, 1)
	T.eq(action, nil)
end)

T.test("painel não altera o estado original (é funcional)", function()
	local s = panel.new()
	panel.handle(s, "down", ctx())
	T.eq(s.cursor, 1)
end)

