-- Conversa com o negociador: nós de diálogo, opções e respostas quando algo impede a corrida.
-- Lógica pura e imutável: cada função devolve um estado novo. Não chama natives.
--
-- Estado: { node = "greet", cursor = 1 }.
-- Ações devolvidas por choose/back: "start" (o jogador aceitou correr) e "close" (encerrar a conversa).

local dialogue = {}

local SPEAKER = "Negociador"

-- Cada nó tem `text` (texto ou função de ctx) e `options`. Uma opção tem `next` (outro nó) ou `action`.
local NODES = {
	greet = {
		text = function(ctx)
			return "Ei, forasteiro. Dizem que você monta bem. Quer correr na rota " .. ctx.routeName .. "? Aqui não tem juiz nem lei."
		end,
		options = {
			{ label = "Quais são as regras?", next = "rules" },
			{ label = "Estou dentro. Vamos correr!", action = "start" },
			{ label = "Agora não.", action = "close" },
		},
	},
	rules = {
		text = "Passe por todos os pontos, na ordem, até o fim. Quem pular um ponto não vale. Se a polícia ouvir falar, ela vai atrás de todo mundo.",
		options = {
			{ label = "Entendi. Vamos correr!", action = "start" },
			{ label = "Voltar", next = "greet" },
		},
	},
	need_horse = {
		text = "Sem cavalo não tem corrida. Volte montado no seu cavalo.",
		options = { { label = "Entendi", next = "greet" } },
	},
	route_incomplete = {
		text = "Essa rota ainda não está pronta. Os pontos precisam ser marcados antes.",
		options = { { label = "Entendi", next = "greet" } },
	},
	too_far = {
		text = "Você está longe demais da largada. Chegue mais perto e fale comigo de novo.",
		options = { { label = "Entendi", next = "greet" } },
	},
	busy = {
		text = "Já tem uma corrida acontecendo. Espere ela terminar.",
		options = { { label = "Entendi", next = "greet" } },
	},
}

-- Motivos que o jogo pode usar para recusar o início da corrida.
local REFUSALS = { need_horse = true, route_incomplete = true, too_far = true, busy = true }

function dialogue.new()
	return { node = "greet", cursor = 1 }
end

local function resolve(state, ctx)
	local node = NODES[state.node]
	local text = node.text
	if type(text) == "function" then
		text = text(ctx)
	end
	return node, text
end

-- O que mostrar na tela: quem fala, o texto e as opções.
function dialogue.view(state, ctx)
	local node, text = resolve(state, ctx)
	local options = {}
	for i, opt in ipairs(node.options) do
		options[i] = { label = opt.label }
	end
	return { speaker = SPEAKER, text = text, options = options }
end

-- Move o cursor entre as opções, sem sair dos limites.
function dialogue.move(state, delta, ctx)
	local node = NODES[state.node]
	local c = state.cursor + delta
	if c < 1 then
		c = 1
	end
	if c > #node.options then
		c = #node.options
	end
	return { node = state.node, cursor = c }
end

-- Escolhe a opção do cursor. Devolve (novo estado, ação ou nil).
function dialogue.choose(state, ctx)
	local node = NODES[state.node]
	local opt = node.options[state.cursor]
	if opt == nil then
		return state, nil
	end
	if opt.next ~= nil then
		return { node = opt.next, cursor = 1 }, nil
	end
	return state, opt.action
end

-- O jogo recusou iniciar a corrida: o negociador explica o motivo.
function dialogue.refuse(state, reason)
	if not REFUSALS[reason] then
		error("motivo de recusa desconhecido: " .. tostring(reason), 2)
	end
	return { node = reason, cursor = 1 }
end

-- Voltar: sai de qualquer nó para a saudação; na saudação, encerra a conversa.
function dialogue.back(state)
	if state.node == "greet" then
		return state, "close"
	end
	return { node = "greet", cursor = 1 }, nil
end

return dialogue
