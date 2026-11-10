--!strict
-- Кастеты + слоты. Handle невидимый; кастеты Weld к рукам.
-- Стойка/блок — клиентские анимации; сервер только IsBlocking + WalkSpeed.
-- Экип слота — RemoteEvent (клиентский EquipTool после Unequip глючит).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

-- === Посадка на кулаки (можно чуть утопить внутрь руки) ===
local RIGHT_FIST_POSITION = Vector3.new(0, 0.1, 0)
local RIGHT_FIST_ROTATION_DEG = Vector3.new(0, 0, -90)

local LEFT_FIST_POSITION = Vector3.new(0, 0.1, 0)
local LEFT_FIST_ROTATION_DEG = Vector3.new(0, 90, -90)

local BLOCK_WALK_SPEED = 10
local DEFAULT_WALK_SPEED = 16
-- ===

local TOOL_NAME = "FistWeapon"
local ITEM_ID = "FistWeapon"
local TEMPLATE_NAME = "fistweapon_A"
local RIGHT_VISUAL = "FistWeapon_Right"
local LEFT_VISUAL = "FistWeapon_Left"
local SLOT_COUNT = 20
local STORE_NAME = "R1_Inventory_v1"
local ATTR_SLOT = "InvSlot"
local ATTR_ITEM = "ItemId"

local function anglesFromDeg(rot: Vector3): CFrame
	return CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
end

local function offsetCFrame(pos: Vector3, rotDeg: Vector3): CFrame
	return CFrame.new(pos) * anglesFromDeg(rotDeg)
end

local function preparePart(part: BasePart)
	part.CanCollide = false
	part.Anchored = false
	part.Massless = true
end

local function resolveTemplate(): BasePart?
	local assets = ReplicatedStorage:WaitForChild("assets", 30)
	if not assets then
		warn("FistWeapon: нет ReplicatedStorage.assets")
		return nil
	end
	local template = assets:WaitForChild(TEMPLATE_NAME, 30)
	if not template then
		warn("FistWeapon: нет assets." .. TEMPLATE_NAME)
		return nil
	end
	if template:IsA("BasePart") then
		return template
	end
	local nested = template:FindFirstChildWhichIsA("BasePart", true)
	if nested then
		return nested
	end
	warn("FistWeapon: шаблон не BasePart (" .. template.ClassName .. ")")
	return nil
end

local template = resolveTemplate()
if not template then
	return
end

-- Remotes
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not (remotes and remotes:IsA("Folder")) then
	if remotes then
		remotes:Destroy()
	end
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end
local function ensureRemote(name: string): RemoteEvent
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

local equipRemote = ensureRemote("EquipSlot")
local blockRemote = ensureRemote("FistBlock")

-- DataStore только вне Studio (иначе спам StudioAccessToApisNotAllowed).
local store: DataStore? = nil
if not RunService:IsStudio() then
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	end
end

local session: { [Player]: { slots: { [number]: string }, equipped: number } } = {}

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

local function writeInvState(player: Player)
	local data = session[player]
	local folder = ensureInvState(player)
	local equipped = folder:FindFirstChild("Equipped")
	if equipped and equipped:IsA("IntValue") then
		equipped.Value = if data then data.equipped else 0
	end

	for i = 1, SLOT_COUNT do
		local name = "Slot" .. i
		local value = folder:FindFirstChild(name)
		local itemId = data and data.slots[i] or nil
		if itemId then
			if not (value and value:IsA("StringValue")) then
				if value then
					value:Destroy()
				end
				value = Instance.new("StringValue")
				value.Name = name
				value.Parent = folder
			end
			(value :: StringValue).Value = itemId
		elseif value then
			value:Destroy()
		end
	end
end

local function findArm(character: Model, side: "Left" | "Right"): BasePart?
	if side == "Left" then
		local hand = character:FindFirstChild("LeftHand")
		if hand and hand:IsA("BasePart") then
			return hand
		end
		local arm = character:FindFirstChild("Left Arm")
		if arm and arm:IsA("BasePart") then
			return arm
		end
	else
		local hand = character:FindFirstChild("RightHand")
		if hand and hand:IsA("BasePart") then
			return hand
		end
		local arm = character:FindFirstChild("Right Arm")
		if arm and arm:IsA("BasePart") then
			return arm
		end
	end
	return nil
end

local function clearVisuals(character: Model)
	for _, name in { RIGHT_VISUAL, LEFT_VISUAL } do
		local inst = character:FindFirstChild(name)
		if inst then
			inst:Destroy()
		end
	end
end

local function weldFist(character: Model, side: "Left" | "Right")
	local arm = findArm(character, side)
	if not arm then
		return
	end
	local name = if side == "Left" then LEFT_VISUAL else RIGHT_VISUAL
	local existing = character:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end

	local fist = template:Clone()
	fist.Name = name
	preparePart(fist)
	fist.Parent = character

	local pos = if side == "Left" then LEFT_FIST_POSITION else RIGHT_FIST_POSITION
	local rot = if side == "Left" then LEFT_FIST_ROTATION_DEG else RIGHT_FIST_ROTATION_DEG

	local weld = Instance.new("Weld")
	weld.Name = name .. "Weld"
	weld.Part0 = arm
	weld.Part1 = fist
	weld.C0 = offsetCFrame(pos, rot)
	weld.C1 = CFrame.new()
	weld.Parent = fist
end

local function clearBlocking(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	character:SetAttribute("IsBlocking", false)
	if humanoid then
		local base = character:GetAttribute("BaseWalkSpeed")
		if typeof(base) == "number" then
			humanoid.WalkSpeed = base
		else
			humanoid.WalkSpeed = DEFAULT_WALK_SPEED
		end
	end
end

local function setBlocking(character: Model, active: boolean)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if active then
		if typeof(character:GetAttribute("BaseWalkSpeed")) ~= "number" then
			character:SetAttribute("BaseWalkSpeed", humanoid.WalkSpeed)
		end
		character:SetAttribute("IsBlocking", true)
		humanoid.WalkSpeed = BLOCK_WALK_SPEED
	else
		clearBlocking(character)
	end
end

local function hasFistEquipped(character: Model): boolean
	local tool = character:FindFirstChild(TOOL_NAME)
	return tool ~= nil and tool:IsA("Tool")
end

local function createTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = TOOL_NAME
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = "Fists"
	tool.Grip = CFrame.new()

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.2)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Massless = true
	handle.CastShadow = false
	handle.Parent = tool

	tool.Equipped:Connect(function()
		local character = tool.Parent
		if not character or not character:IsA("Model") then
			return
		end
		weldFist(character, "Right")
		weldFist(character, "Left")

		local player = Players:GetPlayerFromCharacter(character)
		if player and session[player] then
			local slot = tool:GetAttribute(ATTR_SLOT)
			if typeof(slot) == "number" then
				session[player].equipped = slot
				writeInvState(player)
			end
		end
	end)

	tool.Unequipped:Connect(function()
		local backpack = tool.Parent
		if not (backpack and backpack:IsA("Backpack")) then
			return
		end
		local player = backpack.Parent
		if not (player and player:IsA("Player")) then
			return
		end
		local character = player.Character
		if character then
			clearVisuals(character)
			clearBlocking(character)
		end
		if session[player] then
			session[player].equipped = 0
			writeInvState(player)
		end
	end)

	return tool
end

local function findTool(player: Player, pred: (Tool) -> boolean): Tool?
	local function scan(container: Instance?): Tool?
		if not container then
			return nil
		end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and pred(child) then
				return child
			end
		end
		return nil
	end
	return scan(player:FindFirstChildOfClass("Backpack")) or scan(player.Character)
end

local function ensureTools(player: Player)
	local data = session[player]
	if not data then
		return
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end

	for slot, itemId in pairs(data.slots) do
		if itemId == ITEM_ID then
			local existing = findTool(player, function(tool)
				return tool:GetAttribute(ATTR_SLOT) == slot or tool.Name == TOOL_NAME
			end)
			if existing then
				existing:SetAttribute(ATTR_SLOT, slot)
				existing:SetAttribute(ATTR_ITEM, ITEM_ID)
			else
				local tool = createTool()
				tool:SetAttribute(ATTR_SLOT, slot)
				tool:SetAttribute(ATTR_ITEM, ITEM_ID)
				tool.Parent = backpack
			end
		end
	end
end

local function equipSlot(player: Player, slot: number)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if slot < 1 then
		humanoid:UnequipTools()
		return
	end

	local tool = findTool(player, function(t)
		return t:GetAttribute(ATTR_SLOT) == slot or (slot == 1 and t.Name == TOOL_NAME)
	end)
	if tool then
		humanoid:EquipTool(tool)
	end
end

local function defaultSlots(): { [number]: string }
	return { [1] = ITEM_ID }
end

local function loadSlots(player: Player): ({ [number]: string }, number)
	if not store then
		return defaultSlots(), 1
	end
	local ok, data = pcall(function()
		return store:GetAsync("u_" .. player.UserId)
	end)
	if not ok or typeof(data) ~= "table" then
		return defaultSlots(), 1
	end
	local slots: { [number]: string } = {}
	local raw = (data :: any).slots
	if typeof(raw) == "table" then
		for key, itemId in pairs(raw) do
			local slotNum = tonumber(key)
			if slotNum and slotNum >= 1 and slotNum <= SLOT_COUNT and itemId == ITEM_ID then
				slots[slotNum] = ITEM_ID
			end
		end
	end
	if next(slots) == nil then
		slots = defaultSlots()
	end
	local equipped = tonumber((data :: any).equipped) or 1
	if not slots[equipped] then
		equipped = 1
	end
	return slots, equipped
end

local function saveSlots(player: Player)
	local data = session[player]
	if not data then
		return
	end
	local live: { [number]: string } = {}
	local function ingest(container: Instance?)
		if not container then
			return
		end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") then
				local slot = child:GetAttribute(ATTR_SLOT)
				local itemId = child:GetAttribute(ATTR_ITEM)
				if typeof(slot) == "number" and typeof(itemId) == "string" then
					live[slot] = itemId
				elseif child.Name == TOOL_NAME then
					live[1] = ITEM_ID
				end
			end
		end
	end
	ingest(player:FindFirstChildOfClass("Backpack"))
	ingest(player.Character)
	if next(live) ~= nil then
		data.slots = live
	end

	if not store then
		return
	end
	local payload = { slots = {}, equipped = data.equipped }
	for slot, itemId in pairs(data.slots) do
		payload.slots[tostring(slot)] = itemId
	end
	pcall(function()
		store:SetAsync("u_" .. player.UserId, payload)
	end)
end

local function hookPlayer(player: Player)
	local slots, equipped = loadSlots(player)
	session[player] = { slots = slots, equipped = equipped }
	writeInvState(player)

	player.CharacterAdded:Connect(function(character)
		task.defer(function()
			if not player.Parent or player.Character ~= character then
				return
			end
			character:WaitForChild("Humanoid", 10)
			ensureTools(player)
			writeInvState(player)
			local data = session[player]
			if data and data.equipped > 0 then
				equipSlot(player, data.equipped)
			end
		end)

		character.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				clearVisuals(character)
				clearBlocking(character)
			end
		end)
	end)

	if player.Character then
		task.defer(function()
			local character = player.Character
			if not character then
				return
			end
			ensureTools(player)
			writeInvState(player)
			local data = session[player]
			if data and data.equipped > 0 then
				equipSlot(player, data.equipped)
			end
		end)
	end
end

equipRemote.OnServerEvent:Connect(function(player: Player, slot: any)
	if typeof(slot) ~= "number" then
		return
	end
	slot = math.floor(slot)
	if slot < 0 or slot > SLOT_COUNT then
		return
	end
	local data = session[player]
	if not data then
		return
	end
	if slot >= 1 and not data.slots[slot] then
		-- Пустой слот → снять.
		equipSlot(player, 0)
		return
	end
	equipSlot(player, slot)
end)

blockRemote.OnServerEvent:Connect(function(player: Player, active: any)
	if typeof(active) ~= "boolean" then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	if active then
		if not hasFistEquipped(character) then
			return
		end
		setBlocking(character, true)
	else
		setBlocking(character, false)
	end
end)

Players.PlayerAdded:Connect(hookPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(hookPlayer, player)
end

Players.PlayerRemoving:Connect(function(player)
	saveSlots(player)
	session[player] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveSlots(player)
	end
end)

print("FistWeapon: готов (" .. template:GetFullName() .. ")")
