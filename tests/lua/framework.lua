-- Mini framework de testes em Lua 5.1/5.3 (roda dentro do fengari).
-- Cada teste roda com pcall; o resultado vira uma linha "PASS|nome" ou "FAIL|nome|erro".

T = {}
local results = {}

local function record(status, name, detail)
	results[#results + 1] = status .. "|" .. name .. "|" .. (detail or "")
end

function T.test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		record("PASS", name, "")
	else
		record("FAIL", name, tostring(err))
	end
end

function T.eq(actual, expected, msg)
	if actual ~= expected then
		error((msg and (msg .. ": ") or "") .. "esperado " .. tostring(expected) .. ", obtido " .. tostring(actual), 2)
	end
end

function T.truthy(value, msg)
	if not value then
		error(msg or "esperado verdadeiro, obtido falso", 2)
	end
end

function T.falsy(value, msg)
	if value then
		error(msg or "esperado falso, obtido verdadeiro", 2)
	end
end

function T.near(actual, expected, tolerance, msg)
	tolerance = tolerance or 1e-6
	if math.abs(actual - expected) > tolerance then
		error((msg and (msg .. ": ") or "") .. "esperado ~" .. tostring(expected) .. ", obtido " .. tostring(actual), 2)
	end
end

function T.errors(fn, msg)
	local ok = pcall(fn)
	if ok then
		error(msg or "esperava erro, nenhum ocorreu", 2)
	end
end

function T.report()
	return table.concat(results, "\n")
end
