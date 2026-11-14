--!strict
-- Английские подсказки «не тот инструмент» с анти-спамом.

local ToolHints = {}

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))

local HINT_COOLDOWN = 1.5
local MSG_AXE = "Use an Axe!"
local MSG_PICKAXE = "Use a Pickaxe!"

local lastHintAt: { [Player]: number } = {}
local remote: RemoteEvent? = nil

local function getRemote(): RemoteEvent
	if remote and remote.Parent then
		return remote
	end
	remote = InventoryService.EnsureRemote("ToolHint")
	return remote
end

local function tell(player: Player, message: string)
	local now = os.clock()
	local last = lastHintAt[player] or 0
	if now - last < HINT_COOLDOWN then
		return
	end
	lastHintAt[player] = now
	getRemote():FireClient(player, message)
end

function ToolHints.NeedAxe(player: Player)
	tell(player, MSG_AXE)
end

function ToolHints.NeedPickaxe(player: Player)
	tell(player, MSG_PICKAXE)
end

function ToolHints.Start()
	getRemote()
end

Players.PlayerRemoving:Connect(function(player)
	lastHintAt[player] = nil
end)

return ToolHints
