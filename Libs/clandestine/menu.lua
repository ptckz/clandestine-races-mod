-- Menu visual no estilo do Rampage: cabeçalho vermelho, faixa de página, lista com item
-- selecionado em vermelho, seta para submenus e rodapé com a descrição do item.
-- Só desenha e move o cursor. Não executa ações: isso fica com quem usa o menu.
--
-- Coordenadas validadas no jogo (tela 1920x1080): todas em fração da tela, de 0 a 1.
--   retângulo (DRAW_RECT): x, y é o CENTRO; w, h é o tamanho.
--   texto (_BG_DISPLAY_TEXT): x, y é o canto SUPERIOR ESQUERDO.

local menu = {}

local X, Y, W = 0.06, 0.12, 0.28
local HEADER_H, SUB_H, ROW_H, FOOT_H = 0.11, 0.045, 0.05, 0.05
local MAX_ROWS = 8

local SCALE_TITLE, SCALE_SUB, SCALE_ROW, SCALE_FOOT = 0.9, 0.35, 0.4, 0.3
local FOOT_CHARS = 46 -- caracteres por linha do rodapé

local RED = { 160, 0, 0, 255 }
local BLACK = { 0, 0, 0, 215 }
local WHITE = { 255, 255, 255, 255 }

-- Move o cursor dentro de [1, count], sem sair dos limites.
function menu.move(cursor, delta, count)
	if count <= 0 then
		return 1
	end
	local c = cursor + delta
	if c < 1 then
		c = 1
	end
	if c > count then
		c = count
	end
	return c
end

-- Primeira linha visível para que o cursor apareça.
function menu.top(cursor, count)
	if count <= MAX_ROWS then
		return 1
	end
	local top = cursor - MAX_ROWS + 1
	if top < 1 then
		top = 1
	end
	return top
end

-- Quebra um texto em linhas de até `maxChars` caracteres, sem partir palavras.
function menu.wrap(text, maxChars)
	local lines, current = {}, ""
	for word in tostring(text):gmatch("%S+") do
		if current == "" then
			current = word
		elseif #current + 1 + #word <= maxChars then
			current = current .. " " .. word
		else
			lines[#lines + 1] = current
			current = word
		end
	end
	if current ~= "" then
		lines[#lines + 1] = current
	end
	return lines
end

-- Retângulo pelo canto superior esquerdo (x0, y0), convertido para o centro que o jogo espera.
local function rect(N, x0, y0, w, h, c)
	N.drawRect(x0 + w / 2, y0 + h / 2, w, h, c[1], c[2], c[3], c[4])
end

local function text(N, s, x, y, scale)
	N.drawText(s, x, y, scale, WHITE[1], WHITE[2], WHITE[3], WHITE[4])
end

-- Desenha o menu. `m` = { title, subtitle, counter, items = { {label, arrow} }, cursor, footer }.
function menu.draw(N, m)
	local count = #m.items
	local rows = math.min(count, MAX_ROWS)
	local top = menu.top(m.cursor, count)
	local listH = ROW_H * rows

	-- Cabeçalho vermelho com o título.
	rect(N, X, Y, W, HEADER_H, RED)
	text(N, m.title, X + 0.02, Y + (HEADER_H - 0.05) / 2, SCALE_TITLE)

	-- Faixa preta: nome da página à esquerda, contador à direita.
	local subY = Y + HEADER_H
	rect(N, X, subY, W, SUB_H, BLACK)
	text(N, m.subtitle, X + 0.012, subY + 0.012, SCALE_SUB)
	if m.counter then
		text(N, m.counter, X + W - 0.05, subY + 0.012, SCALE_SUB)
	end

	-- Lista de opções.
	local listY = subY + SUB_H
	for i = 0, rows - 1 do
		local idx = top + i
		if idx > count then
			break
		end
		local item = m.items[idx]
		local rowY = listY + ROW_H * i
		local bg = (idx == m.cursor) and RED or BLACK
		rect(N, X, rowY, W, ROW_H, bg)
		text(N, item.label, X + 0.012, rowY + 0.012, SCALE_ROW)
		if item.arrow then
			text(N, ">", X + W - 0.025, rowY + 0.012, SCALE_ROW)
		end
	end

	-- Indicador de rolagem quando há mais itens.
	local footY = listY + listH
	if count > MAX_ROWS then
		rect(N, X, footY, W, 0.035, BLACK)
		text(N, "v", X + W / 2 - 0.005, footY + 0.006, SCALE_SUB)
		footY = footY + 0.035
	end

	-- Rodapé: linha vermelha e descrição do item selecionado (em várias linhas, se for longa).
	local lines = menu.wrap(m.footer or "", FOOT_CHARS)
	local footH = math.max(FOOT_H, 0.02 + 0.03 * #lines)
	rect(N, X, footY, W, 0.004, RED)
	rect(N, X, footY + 0.004, W, footH, BLACK)
	for i, line in ipairs(lines) do
		text(N, line, X + 0.012, footY + 0.004 + 0.012 + 0.03 * (i - 1), SCALE_FOOT)
	end
end

return menu
