--!strict
-- Прочность блока (defence): при IsBlocking урон сначала в щит, потом в HP.
-- После любого урона по щиту — через RECHARGE_TIME полное восстановление (таймер сбрасывается новым ударом).

local ServerScriptService = game:GetService("ServerScriptService")

local ItemsConfig = require(ServerScriptService:WaitForChild("ItemsConfig"))

local CombatDefence = {}

local ATTR_DEFENCE = "Defence"
local ATTR_MAX_DEFENCE = "MaxDefence"

local RECHARGE_TIME = 3

local restoreToken: { [Model]: number } = {}

export type ApplyOptions = {
	-- Явный блок (PvP с block_dot). nil → читать IsBlocking.
	blocked: boolean?,
}

local function getHumanoid(character: Model): Humanoid?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function readDefence(character: Model): (number, number)
	local cur = character:GetAttribute(ATTR_DEFENCE)
	local maxD = character:GetAttribute(ATTR_MAX_DEFENCE)
	local c = if typeof(cur) == "number" then cur else 0
	local m = if typeof(maxD) == "number" then maxD else 0
	return c, m
end

-- Через 3с вернуть щит на MaxDefence. Новый удар по щиту перезапускает таймер.
local function scheduleRestore(character: Model)
	local _, maxD = readDefence(character)
	if maxD <= 0 then
		return
	end
	restoreToken[character] = (restoreToken[character] or 0) + 1
	local token = restoreToken[character]
	task.delay(RECHARGE_TIME, function()
		if restoreToken[character] ~= token then
			return
		end
		if not character.Parent then
			return
		end
		local _, stillMax = readDefence(character)
		if stillMax <= 0 then
			return
		end
		character:SetAttribute(ATTR_DEFENCE, stillMax)
	end)
end

function CombatDefence.Clear(character: Model)
	restoreToken[character] = (restoreToken[character] or 0) + 1
	character:SetAttribute(ATTR_DEFENCE, 0)
	character:SetAttribute(ATTR_MAX_DEFENCE, 0)
end

-- Выставить запас щита по экипированному melee (defence из items_config).
function CombatDefence.SyncFromItem(character: Model, itemId: string?)
	restoreToken[character] = (restoreToken[character] or 0) + 1
	if not itemId then
		CombatDefence.Clear(character)
		return
	end
	local stats = ItemsConfig.GetMelee(itemId)
	local maxD = if stats then ItemsConfig.Defence(stats) else 0
	if maxD <= 0 then
		CombatDefence.Clear(character)
		return
	end
	character:SetAttribute(ATTR_MAX_DEFENCE, maxD)
	character:SetAttribute(ATTR_DEFENCE, maxD)
end

-- Нанести урон: при блоке с defence>0 — в щит; остаток / без щита — в HP.
-- Возвращает сколько ушло в Health.
function CombatDefence.ApplyDamage(character: Model, damage: number, opts: ApplyOptions?): number
	local humanoid = getHumanoid(character)
	if not humanoid then
		return 0
	end
	local amount = math.max(0, damage)
	if amount <= 0 then
		return 0
	end

	local blocking = if opts and opts.blocked ~= nil
		then opts.blocked
		else character:GetAttribute("IsBlocking") == true

	if blocking then
		local cur, maxD = readDefence(character)
		if maxD > 0 and cur > 0 then
			local absorbed = math.min(cur, amount)
			local newDef = cur - absorbed
			character:SetAttribute(ATTR_DEFENCE, newDef)
			-- Любой урон по щиту → полный реген через 3с (таймер сбрасывается).
			scheduleRestore(character)
			local remain = amount - absorbed
			if remain > 0 then
				humanoid:TakeDamage(remain)
				return remain
			end
			return 0
		end
	end

	humanoid:TakeDamage(amount)
	return amount
end

function CombatDefence.AttrDefence(): string
	return ATTR_DEFENCE
end

function CombatDefence.AttrMaxDefence(): string
	return ATTR_MAX_DEFENCE
end

function CombatDefence.RechargeTime(): number
	return RECHARGE_TIME
end

return CombatDefence
