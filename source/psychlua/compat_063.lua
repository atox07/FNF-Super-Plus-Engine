--[[
  compat_063.lua  (incorporato nell'eseguibile da CompatLayer.hx)
  Layer di compatibilita': script Lua scritti per Psych 0.6.3 -> Psych 1.0.x

  Ogni script Lua ha il PROPRIO stato Lua. Questo codice gira nello stato dello script
  dopo la registrazione delle funzioni native e prima di onCreate: sostituisce alcune
  funzioni globali con versioni che traducono la vecchia chiamata e poi chiamano l'originale.

  COME AGGIUNGERE REGOLE
    - classe spostata            -> CLASS_REDIRECTS
    - funzione con classe        -> CLASS_FUNCTIONS
    - percorso di proprieta'     -> addPropertyRule(...)
    - variabile di gruppo        -> GROUP_PROPERTY_REWRITES
    - altra funzione             -> wrap('nome', builder)

  NOTA: getObjectOrder/setObjectOrder NON sono piu' gestite qui. Il motore le risolve
  gia' in Haxe (getOrderParentGroup + getCompatibleHudOrder in FunkinLua.hx), e l'euristica
  precedente basata su os.clock() era fragile.
]]

if __COMPAT_WRAPPER_LOADED then return end
__COMPAT_WRAPPER_LOADED = true

local CONFIG = {
	-- stampa ogni traduzione; si attiva da solo se lo script ha luaDebugMode = true
	debug = (luaDebugMode == true),

	-- healthBarBG / timeBarBG (rimossi dalla 0.7): 'redirect' -> healthBar.bg / timeBar.bg, 'ignore' -> annulla la chiamata
	bgMode = 'redirect',

	-- camFollowPos (rimosso dalla 0.7) -> camFollow. Da verificare nella tua build.
	redirectCamFollowPos = true,

	-- addHaxeLibrary('MainMenuState') => aggiunge "import states.MainMenuState;" ai runHaxeCode successivi
	rewriteHaxeImports = true,

	-- true = setObjectCamera usa SEMPRE il workaround via setProperty
	forceCameraWorkaround = false,
}

local function log(msg)
	if CONFIG.debug then debugPrint('[compat] ' .. tostring(msg)) end
end

------------------------------------------------------------
-- 1. wrap()
------------------------------------------------------------
-- Sostituisce la funzione globale `name` con builder(original).
-- Se non esiste: la salta, a meno che allowMissing sia true (allora l'originale e' una funzione vuota).
local function wrap(name, builder, allowMissing)
	local original = _G[name]
	if type(original) ~= 'function' then
		if not allowMissing then
			log("wrap: '" .. name .. "' non esiste in questa versione, saltata")
			return false
		end
		original = function() end
	end
	_G[name] = builder(original)
	return true
end

------------------------------------------------------------
-- 2. CLASSI SPOSTATE
------------------------------------------------------------
local CLASS_REDIRECTS = {
	PlayState     = 'states.PlayState',
	MainMenuState = 'states.MainMenuState',
}

local function resolveClass(name)
	if type(name) ~= 'string' or name:find('.', 1, true) then return name end
	local new = CLASS_REDIRECTS[name]
	if new then log('class: ' .. name .. ' -> ' .. new) end
	return new or name
end

local CLASS_FUNCTIONS = {
	'getPropertyFromClass',
	'setPropertyFromClass',
}

for _, fname in ipairs(CLASS_FUNCTIONS) do
	wrap(fname, function(orig)
		return function(class, ...)
			return orig(resolveClass(class), ...)
		end
	end)
end

local haxeImports = {}

wrap('addHaxeLibrary', function(orig)
	return function(lib, pkg, ...)
		local full = CLASS_REDIRECTS[lib]
		if full and (pkg == nil or pkg == '') then
			pkg = full:match('^(.*)%.[^.]+$') or ''
		end
		if full and CONFIG.rewriteHaxeImports then
			haxeImports[full] = true
			log('registered haxe import: ' .. full)
		end
		pcall(orig, lib, pkg or '', ...)
	end
end, true)

wrap('runHaxeCode', function(orig)
	return function(code, ...)
		if CONFIG.rewriteHaxeImports and type(code) == 'string' then
			local header = {}
			for full in pairs(haxeImports) do
				if not code:find('import ' .. full .. ';', 1, true) then
					header[#header + 1] = 'import ' .. full .. ';'
				end
			end
			if #header > 0 then code = table.concat(header, '\n') .. '\n' .. code end
		end
		return orig(code, ...)
	end
end)

------------------------------------------------------------
-- 3. REGOLE SUI PERCORSI DI PROPRIETA' (getProperty / setProperty)
------------------------------------------------------------
-- Ogni regola e' function(path) che ritorna: stringa = nuovo percorso, false = annulla, nil = nessun cambio.
local propertyRules = {}
local function addPropertyRule(fn) propertyRules[#propertyRules + 1] = fn end

local function rewriteProperty(path)
	if type(path) ~= 'string' then return path end
	for _, rule in ipairs(propertyRules) do
		local result = rule(path)
		if result == false then return false end
		if type(result) == 'string' then path = result end
	end
	return path
end

-- A: 'timeBar.color' -> 'timeBar.leftBar.color'
addPropertyRule(function(path)
	local obj, rest = path:match('^([%w_]+)%.(.+)$')
	if obj == 'timeBar' and rest == 'color' then
		log(path .. ' -> timeBar.leftBar.color')
		return 'timeBar.leftBar.color'
	end
end)

-- B: healthBarBG / timeBarBG -> *Bar.bg (oppure ignora)
local BG_REDIRECTS = {
	healthBarBG = 'healthBar.bg',
	timeBarBG   = 'timeBar.bg',
}
addPropertyRule(function(path)
	local obj, rest = path:match('^([%w_]+)(.*)$')
	local target = obj and BG_REDIRECTS[obj]
	if not target then return nil end
	if CONFIG.bgMode == 'ignore' then
		log('ignored: ' .. path)
		return false
	end
	log(path .. ' -> ' .. target .. rest)
	return target .. rest
end)

-- C: camFollowPos.x -> camFollow.x
addPropertyRule(function(path)
	if not CONFIG.redirectCamFollowPos then return nil end
	local obj, rest = path:match('^([%w_]+)(.*)$')
	if obj == 'camFollowPos' then
		log(path .. ' -> camFollow' .. rest)
		return 'camFollow' .. rest
	end
end)

for _, fname in ipairs({ 'setProperty', 'getProperty' }) do
	wrap(fname, function(orig)
		return function(path, ...)
			local newPath = rewriteProperty(path)
			if newPath == false then return nil end
			return orig(newPath, ...)
		end
	end)
end

------------------------------------------------------------
-- 4. NOTE SPLASH (variabili spostate in noteSplashData)
------------------------------------------------------------
local GROUP_PROPERTY_REWRITES = {
	noteSplashDisabled = 'noteSplashData.disabled',
}

wrap('setPropertyFromGroup', function(orig)
	return function(group, index, variable, ...)
		return orig(group, index, GROUP_PROPERTY_REWRITES[variable] or variable, ...)
	end
end)

wrap('getPropertyFromGroup', function(orig)
	return function(group, index, variable, ...)
		return orig(group, index, GROUP_PROPERTY_REWRITES[variable] or variable, ...)
	end
end)

------------------------------------------------------------
-- 5. setObjectCamera (workaround del changelog)
------------------------------------------------------------
local CAMERA_ALIASES = {
	hud   = 'camHUD',
	game  = 'camGame',
	other = 'camOther',
}

wrap('setObjectCamera', function(orig)
	return function(obj, cam, ...)
		if not CONFIG.forceCameraWorkaround then
			local ok, res = pcall(orig, obj, cam, ...)
			if ok then return res end
			log('setObjectCamera nativa fallita, uso il workaround')
		end
		if type(instanceArg) ~= 'function' then return false end
		local camVar = CAMERA_ALIASES[tostring(cam):lower()] or cam
		setProperty(obj .. '.camera', { instanceArg(camVar) }, false, true)
		return true
	end
end)

log('compat layer 0.6.3 attivo')
