--!strict
-- Всплывающая английская подсказка ToolHint (Use an Axe! / Use a Pickaxe!).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local gui = Instance.new("ScreenGui")
gui.Name = "ToolHintGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 90
gui.Parent = playerGui

local label = Instance.new("TextLabel")
label.Name = "Hint"
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.new(0.5, 0, 0.14, 0)
label.Size = UDim2.fromOffset(320, 36)
label.BackgroundColor3 = Color3.fromRGB(232, 220, 196)
label.BackgroundTransparency = 0.15
label.BorderSizePixel = 0
label.Font = Enum.Font.GothamBold
label.TextSize = 18
label.TextColor3 = Color3.fromRGB(60, 44, 28)
label.Text = ""
label.Visible = false
label.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = label

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(110, 88, 58)
stroke.Thickness = 2
stroke.Parent = label

local hideToken = 0

local function showHint(message: string)
	hideToken += 1
	local token = hideToken
	label.Text = message
	label.TextTransparency = 0
	label.BackgroundTransparency = 0.15
	stroke.Transparency = 0
	label.Visible = true

	task.delay(1.2, function()
		if token ~= hideToken then
			return
		end
		local fade = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(label, fade, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
		task.delay(0.4, function()
			if token == hideToken then
				label.Visible = false
			end
		end)
	end)
end

task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 60)
	if not remotes then
		warn("ToolHint client: нет Remotes")
		return
	end
	local remote = remotes:WaitForChild("ToolHint", 60)
	if not (remote and remote:IsA("RemoteEvent")) then
		warn("ToolHint client: нет ToolHint")
		return
	end
	remote.OnClientEvent:Connect(function(message: any)
		if typeof(message) == "string" and message ~= "" then
			showHint(message)
		end
	end)
end)
