--!strict
-- Сессия инвентаря: слоты со стаками, InvState, DataStore.

local InventoryService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemsConfig = require(ServerScriptService:WaitForChild("ItemsConfig"))

export type SlotStack = {
	id: string,
	count: number,
}

export type Session = {
	slots: { [number]: SlotStack },
	equipped: number,
}

local SLOT_COUNT = 20
local STORE_NAME = "R1_Inventory_v1"
local DEFAULT_ITEM = "FistWeapon"
local ATTR_COUNT = "Count"

local ATTR_SLOT = "InvSlot"
local ATTR_ITEM = "ItemId"

local session: { [Player]: Session } = {}
local store: DataStore? = nil
local toolSync: ((Player) -> ())? = nil
local dropSpawner: ((Player, string) -> boolean)? = nil
local visualCleanup: ((Player) -> ())? = nil

if not RunService:IsStudio() then
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	end
end

local function ensureRemotes(): Folder
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not (remotes and remotes:IsA("Folder")) then
		if remotes then
			remotes:Destroy()
		end
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end
	return remotes
end

local function ensureRemote(name: string): RemoteEvent
	local remotes = ensureRemotes()
	local remote = remotes:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	if remote then
		remote:Destroy()
	end
	local created = Instance.new("RemoteEvent")
	created.Name = name
	created.Parent = remotes
	return created
end

local function clampCount(itemId: string, count: number): number
	local maxStack = ItemsConfig.MaxStack(itemId)
	return math.clamp(math.floor(count), 1, maxStack)
end

local function makeStack(itemId: string, count: number?): SlotStack
	return {
		id = itemId,
		count = clampCount(itemId, count or 1),
	}
end

function InventoryService.SlotCount(): number
	return SLOT_COUNT
end

function InventoryService.AttrSlot(): string
	return ATTR_SLOT
end

function InventoryService.AttrItem(): string
	return ATTR_ITEM
end

function InventoryService.EnsureRemote(name: string): RemoteEvent
	return ensureRemote(name)
end

function InventoryService.SetToolSync(callback: (Player) -> ())
	toolSync = callback
end

function InventoryService.SetDropSpawner(callback: (Player, string) -> boolean)
	dropSpawner = callback
end

function InventoryService.SetVisualCleanup(callback: (Player) -> ())
	visualCleanup = callback
end

function InventoryService.GetSession(player: Player): Session?
	return session[player]
end

function InventoryService.GetSlotItemId(player: Player, slot: number): string?
	local data = session[player]
	local stack = data and data.slots[slot]
	return if stack then stack.id else nil
end

local function ensureInvState(player: Player): Folder
	local folder = player:FindFirstChild("InvState")
	if folder and folder:IsA("Folder") then
		return folder
	end
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "InvState"
	folder.Parent = player

	local equipped = Instance.new("IntValue")
	equipped.Name = "Equipped"
	equipped.Value = 0
	equipped.Parent = folder
	return folder
end

function InventoryService.WriteState(player: Player)
	local data = session[player]
	local folder = ensureInvState(player)
	local equipped = folder:FindFirstChild("Equipped")
	if equipped and equipped:IsA("IntValue") then
		equipped.Value = if data then data.equipped else 0
	end

	for i = 1, SLOT_COUNT do
		local name = "Slot" .. i
		local value = folder:FindFirstChild(name)
		local stack = data and data.slots[i] or nil
		if stack then
			if not (value and value:IsA("StringValue")) then
				if value then
					value:Destroy()
				end
				value = Instance.new("StringValue")
				value.Name = name
				value.Parent = folder
			end
			local sv = value :: StringValue
			sv.Value = stack.id
			sv:SetAttribute(ATTR_COUNT, stack.count)
		elseif value then
			value:Destroy()
		end
	end
end

local function defaultSlots(): { [number]: SlotStack }
	return { [1] = makeStack(DEFAULT_ITEM, 1) }
end

local function parseSlotEntry(raw: any): SlotStack?
	if typeof(raw) == "string" then
		if ItemsConfig.IsKnown(raw) then
			return makeStack(raw, 1)
		end
		return nil
	end
	if typeof(raw) ~= "table" then
		return nil
	end
	local id = (raw :: any).id or (raw :: any).itemId
	local count = tonumber((raw :: any).count) or 1
	if typeof(id) == "string" and ItemsConfig.IsKnown(id) then
		return makeStack(id, count)
	end
	return nil
end

local function loadSlots(player: Player): Session
	if not store then
		return { slots = defaultSlots(), equipped = 1 }
	end
	local ok, data = pcall(function()
		return store:GetAsync("u_" .. player.UserId)
	end)
	if not ok or typeof(data) ~= "table" then
		return { slots = defaultSlots(), equipped = 1 }
	end
	local slots: { [number]: SlotStack } = {}
	local raw = (data :: any).slots
	if typeof(raw) == "table" then
		for key, entry in pairs(raw) do
			local slotNum = tonumber(key)
			if slotNum and slotNum >= 1 and slotNum <= SLOT_COUNT then
				local stack = parseSlotEntry(entry)
				if stack then
					slots[slotNum] = stack
				end
			end
		end
	end
	if next(slots) == nil then
		slots = defaultSlots()
	end
	local equipped = tonumber((data :: any).equipped) or 1
	if not slots[equipped] then
		equipped = 0
		for i = 1, SLOT_COUNT do
			if slots[i] then
				equipped = i
				break
			end
		end
	end
	return { slots = slots, equipped = equipped }
end

function InventoryService.Save(player: Player)
	local data = session[player]
	if not data then
		return
	end
	if not store then
		return
	end
	local payload = { slots = {}, equipped = data.equipped }
	for slot, stack in pairs(data.slots) do
		payload.slots[tostring(slot)] = { id = stack.id, count = stack.count }
	end
	pcall(function()
		store:SetAsync("u_" .. player.UserId, payload)
	end)
end

function InventoryService.FindFreeSlot(player: Player): number?
	local data = session[player]
	if not data then
		return nil
	end
	for i = 1, SLOT_COUNT do
		if data.slots[i] == nil then
			return i
		end
	end
	return nil
end

local function findStackSlot(player: Player, itemId: string): number?
	local data = session[player]
	if not data then
		return nil
	end
	local maxStack = ItemsConfig.MaxStack(itemId)
	for i = 1, SLOT_COUNT do
		local stack = data.slots[i]
		if stack and stack.id == itemId and stack.count < maxStack then
			return i
		end
	end
	return nil
end

local function destroyToolInSlot(player: Player, slot: number)
	-- Сначала снять с рук: иначе Destroy на экипированном Tool не чистит weld-визуал кастетов.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and humanoid then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute(ATTR_SLOT) == slot then
				humanoid:UnequipTools()
				break
			end
		end
	end

	local function scan(container: Instance?)
		if not container then
			return
		end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute(ATTR_SLOT) == slot then
				child:Destroy()
			end
		end
	end
	scan(player:FindFirstChildOfClass("Backpack"))
	scan(player.Character)

	if visualCleanup then
		visualCleanup(player)
	end
end

function InventoryService.SyncTools(player: Player)
	if toolSync then
		toolSync(player)
	end
end

function InventoryService.AddItem(player: Player, itemId: string, amount: number?): number?
	if not ItemsConfig.IsKnown(itemId) then
		return nil
	end
	local data = session[player]
	if not data then
		return nil
	end
	local left = math.max(1, math.floor(amount or 1))
	local lastSlot: number? = nil

	while left > 0 do
		local stackSlot = findStackSlot(player, itemId)
		if stackSlot then
			local stack = data.slots[stackSlot]
			local maxStack = ItemsConfig.MaxStack(itemId)
			local space = maxStack - stack.count
			local add = math.min(space, left)
			stack.count += add
			left -= add
			lastSlot = stackSlot
		else
			local free = InventoryService.FindFreeSlot(player)
			if not free then
				break
			end
			local maxStack = ItemsConfig.MaxStack(itemId)
			local add = math.min(maxStack, left)
			data.slots[free] = makeStack(itemId, add)
			left -= add
			lastSlot = free
		end
	end

	if not lastSlot then
		return nil
	end

	InventoryService.WriteState(player)
	InventoryService.SyncTools(player)
	return lastSlot
end

function InventoryService.RemoveSlot(player: Player, slot: number): string?
	local data = session[player]
	if not data then
		return nil
	end
	if slot < 1 or slot > SLOT_COUNT then
		return nil
	end
	local stack = data.slots[slot]
	if not stack then
		return nil
	end
	local itemId = stack.id
	data.slots[slot] = nil
	if data.equipped == slot then
		data.equipped = 0
	end
	destroyToolInSlot(player, slot)
	InventoryService.WriteState(player)
	InventoryService.SyncTools(player)
	return itemId
end

function InventoryService.TakeOne(player: Player, slot: number): string?
	local data = session[player]
	if not data then
		return nil
	end
	local stack = data.slots[slot]
	if not stack then
		return nil
	end
	local itemId = stack.id
	if stack.count <= 1 then
		return InventoryService.RemoveSlot(player, slot)
	end
	stack.count -= 1
	InventoryService.WriteState(player)
	return itemId
end

function InventoryService.MoveSlot(player: Player, fromSlot: number, toSlot: number): boolean
	local data = session[player]
	if not data then
		return false
	end
	if fromSlot < 1 or fromSlot > SLOT_COUNT or toSlot < 1 or toSlot > SLOT_COUNT then
		return false
	end
	if fromSlot == toSlot then
		return true
	end
	local fromStack = data.slots[fromSlot]
	if not fromStack then
		return false
	end
	local toStack = data.slots[toSlot]

	if toStack and toStack.id == fromStack.id then
		local maxStack = ItemsConfig.MaxStack(fromStack.id)
		local space = maxStack - toStack.count
		if space <= 0 then
			-- Полные стаки — просто swap.
			data.slots[fromSlot] = toStack
			data.slots[toSlot] = fromStack
		else
			local moved = math.min(space, fromStack.count)
			toStack.count += moved
			fromStack.count -= moved
			if fromStack.count <= 0 then
				data.slots[fromSlot] = nil
			end
		end
	else
		data.slots[fromSlot] = toStack
		data.slots[toSlot] = fromStack
	end

	destroyToolInSlot(player, fromSlot)
	destroyToolInSlot(player, toSlot)

	if data.equipped == fromSlot then
		data.equipped = if data.slots[toSlot] then toSlot else 0
	elseif data.equipped == toSlot then
		data.equipped = if data.slots[fromSlot] then fromSlot else 0
	end

	InventoryService.WriteState(player)
	InventoryService.SyncTools(player)
	return true
end

function InventoryService.DropSlot(player: Player, slot: number): boolean
	local data = session[player]
	if not data then
		return false
	end
	local stack = data.slots[slot]
	if not stack then
		return false
	end
	if not dropSpawner then
		warn("InventoryService: нет dropSpawner")
		return false
	end
	if not dropSpawner(player, stack.id) then
		return false
	end
	InventoryService.TakeOne(player, slot)
	return true
end

function InventoryService.SetEquipped(player: Player, slot: number)
	local data = session[player]
	if not data then
		return
	end
	data.equipped = slot
	InventoryService.WriteState(player)
end

function InventoryService.HookPlayer(player: Player)
	if session[player] then
		InventoryService.WriteState(player)
		InventoryService.SyncTools(player)
		return
	end
	session[player] = loadSlots(player)
	InventoryService.WriteState(player)
	InventoryService.SyncTools(player)
end

function InventoryService.ClearPlayer(player: Player)
	InventoryService.Save(player)
	session[player] = nil
end

local dropRemote = ensureRemote("DropSlot")
local moveRemote = ensureRemote("MoveSlot")

dropRemote.OnServerEvent:Connect(function(player: Player, slotAny: any)
	if typeof(slotAny) ~= "number" then
		return
	end
	local slot = math.floor(slotAny)
	InventoryService.DropSlot(player, slot)
end)

moveRemote.OnServerEvent:Connect(function(player: Player, fromAny: any, toAny: any)
	if typeof(fromAny) ~= "number" or typeof(toAny) ~= "number" then
		return
	end
	InventoryService.MoveSlot(player, math.floor(fromAny), math.floor(toAny))
end)

Players.PlayerAdded:Connect(function(player)
	InventoryService.HookPlayer(player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(InventoryService.HookPlayer, player)
end

Players.PlayerRemoving:Connect(function(player)
	InventoryService.ClearPlayer(player)
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		InventoryService.Save(player)
	end
end)

return InventoryService
