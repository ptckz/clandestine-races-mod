-- Testes do próprio framework: garantem que as asserções falham quando devem falhar.

T.test("T.eq aceita valores iguais", function()
	T.eq(2 + 2, 4)
end)

T.test("T.eq falha em valores diferentes", function()
	T.errors(function() T.eq(1, 2) end, "T.eq deveria falhar com 1 e 2")
end)

T.test("T.truthy e T.falsy", function()
	T.truthy(true)
	T.falsy(false)
	T.errors(function() T.truthy(false) end)
	T.errors(function() T.falsy(true) end)
end)

T.test("T.near aceita dentro da tolerância e falha fora", function()
	T.near(0.1 + 0.2, 0.3, 1e-9)
	T.errors(function() T.near(1, 2, 0.1) end)
end)
