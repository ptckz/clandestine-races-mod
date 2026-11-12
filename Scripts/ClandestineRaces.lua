-- ClandestineRaces: teste de carregamento (etapa 0).
-- Só registra que o script carregou. Não altera nada no jogo.

local t = {}
local LOG_FILE = 'RedLua\\ClandestineRaces.log'

local function writeLog(msg)
	print('[ClandestineRaces] ' .. msg)
	local ok, err = pcall(function()
		local f = io.open(LOG_FILE, 'a')
		if f then
			f:write(msg .. '\n')
			f:close()
		end
	end)
	if not ok then
		print('[ClandestineRaces] falha ao gravar log: ' .. tostring(err))
	end
end

function t.OnLoad()
	writeLog('OnLoad executado: script carregado.')
end

function t.OnTick(buildMenu)
	-- Sem menu nesta etapa.
end

function t.OnStop()
	writeLog('OnStop executado: script descarregado.')
end

t.OnReload = t.OnStop

return t
