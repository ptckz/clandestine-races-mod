-- Testes do módulo menu: movimento do cursor, janela de itens e quebra de texto do rodapé.

local menu = require("clandestine.menu")

T.test("o cursor sobe e desce sem sair de 1 até a quantidade de itens", function()
	T.eq(menu.move(1, -1, 4), 1)
	T.eq(menu.move(1, 1, 4), 2)
	T.eq(menu.move(4, 1, 4), 4)
	T.eq(menu.move(3, 5, 4), 4)
end)

T.test("sem itens, o cursor fica em 1", function()
	T.eq(menu.move(1, 1, 0), 1)
	T.eq(menu.move(3, -1, 0), 1)
end)

T.test("com poucos itens, a lista começa na primeira linha", function()
	T.eq(menu.top(1, 5), 1)
	T.eq(menu.top(5, 5), 1)
end)

T.test("com muitos itens, a janela acompanha o cursor", function()
	T.eq(menu.top(8, 12), 1, "cursor ainda visível")
	T.eq(menu.top(9, 12), 2, "cursor passa da janela: rola uma linha")
	T.eq(menu.top(12, 12), 5, "no fim da lista")
end)

T.test("wrap: texto curto fica em uma linha", function()
	local lines = menu.wrap("Olá, forasteiro", 46)
	T.eq(#lines, 1)
	T.eq(lines[1], "Olá, forasteiro")
end)

T.test("wrap: texto longo é quebrado sem passar do limite", function()
	local text = "Passe por todos os pontos, na ordem, até o fim. Quem pular um ponto não vale."
	local lines = menu.wrap(text, 30)
	T.truthy(#lines > 1, "mais de uma linha")
	for i, line in ipairs(lines) do
		T.truthy(#line <= 30, "linha " .. i .. " passou do limite: " .. #line)
	end
end)

T.test("wrap: não perde nem repete palavras e mantém a ordem", function()
	local text = "um dois três quatro cinco seis sete oito nove dez"
	local lines = menu.wrap(text, 12)
	T.eq(table.concat(lines, " "), text)
end)

T.test("wrap: palavra maior que o limite fica sozinha na linha", function()
	local lines = menu.wrap("pequena anticonstitucionalissimamente fim", 10)
	T.eq(lines[2], "anticonstitucionalissimamente")
end)

T.test("wrap: texto vazio ou só espaços não gera linhas", function()
	T.eq(#menu.wrap("", 20), 0)
	T.eq(#menu.wrap("     ", 20), 0)
end)

T.test("wrap: espaços repetidos são normalizados", function()
	local lines = menu.wrap("a    b     c", 20)
	T.eq(lines[1], "a b c")
end)
