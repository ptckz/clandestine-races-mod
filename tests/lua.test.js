// Executa os testes Lua de tests/lua/*_test.lua dentro do fengari (Lua 5.3 em JS)
// e expõe cada teste Lua como um teste do node:test.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

const ROOT = path.resolve(__dirname, '..');
const LUA_DIR = path.join(__dirname, 'lua');
const LIBS_PATTERN = path.join(ROOT, 'Libs', '?.lua').split(path.sep).join('/');

function lastError(L) {
	return to_jsstring(lua.lua_tostring(L, -1));
}

// Executa um chunk e devolve o valor de retorno como string (ou lança com a mensagem Lua).
function runChunk(L, code, chunkName) {
	if (lauxlib.luaL_loadbuffer(L, to_luastring(code), code.length, to_luastring(chunkName)) !== lua.LUA_OK) {
		throw new Error(lastError(L));
	}
	if (lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
		throw new Error(lastError(L));
	}
	const out = to_jsstring(lua.lua_tostring(L, -1) || to_luastring(''));
	lua.lua_settop(L, 0);
	return out;
}

function newState() {
	const L = lauxlib.luaL_newstate();
	lualib.luaL_openlibs(L);
	runChunk(L, `package.path = "${LIBS_PATTERN};" .. package.path`, '=setup');
	return L;
}

function runLuaFile(file) {
	const L = newState();
	const framework = fs.readFileSync(path.join(LUA_DIR, 'framework.lua'), 'utf8');
	const body = fs.readFileSync(file, 'utf8');
	// O framework é carregado primeiro; o arquivo de teste roda em seguida; no fim devolvemos o relatório.
	const report = runChunk(L, `${framework}\n${body}\nreturn T.report()`, '@' + path.basename(file));
	return report.split('\n').filter((line) => line.length > 0).map((line) => {
		const [status, name, ...rest] = line.split('|');
		return { status, name, detail: rest.join('|') };
	});
}

const luaTestFiles = fs
	.readdirSync(LUA_DIR)
	.filter((f) => f.endsWith('_test.lua'))
	.sort();

for (const file of luaTestFiles) {
	const suite = path.basename(file, '_test.lua');
	const results = runLuaFile(path.join(LUA_DIR, file));

	test(`${suite}: suíte Lua não vazia`, () => {
		assert.ok(results.length > 0, `nenhum teste Lua encontrado em ${file}`);
	});

	for (const r of results) {
		test(`${suite}: ${r.name}`, () => {
			if (r.status !== 'PASS') {
				assert.fail(r.detail || 'falhou sem mensagem');
			}
		});
	}
}

module.exports = { runLuaFile, newState, runChunk };
