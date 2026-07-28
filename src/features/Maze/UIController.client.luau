--!strict
-- Client surface for the Maze escape round: owns its own ScreenGui + React
-- root (independent of the framework's BoilRoot — this slice needs no
-- UIRegistry/UIShell plumbing, just a full-screen overlay + a timer label).
--
-- Listens for RunStarted (start the top-center timer) and Escaped (stop the
-- timer, show WinScreen). RUN IT BACK sends Restart and resets local state;
-- the actual teleport/unfreeze is server-authoritative (EscapeService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local Net = require(ReplicatedStorage.Features.Maze.Net)
-- WinScreen is a `.ui.luau`, so the splitter routes it to ReplicatedStorage,
-- not alongside this client script in PlayerScripts.
local WinScreen = require(ReplicatedStorage.Features.Maze.WinScreen)
local EscapeCinematic = require(script.Parent.EscapeCinematicController)

local UIController = {}

local TIMER_TEXT_SIZE = 40
local TIMER_FONT = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)

-- "M:SS.d" — matches WinScreen's format so the frozen final time and the
-- live timer read consistently.
local function formatTimer(totalSeconds: number): string
	local minutes = math.floor(totalSeconds / 60)
	local remainder = totalSeconds - minutes * 60
	local wholeSeconds = math.floor(remainder)
	local tenths = math.floor((remainder - wholeSeconds) * 10)
	return string.format("%d:%02d.%d", minutes, wholeSeconds, tenths)
end

local function App()
	local running, setRunning = React.useState(false)
	local elapsed, setElapsed = React.useState(0)
	local startClock, setStartClock = React.useState(nil :: number?)
	local results, setResults =
		React.useState(nil :: { winnerName: string, hauls: { { name: string, haul: number } } }?)
	local countdown, setCountdown = React.useState(nil :: number?)

	-- One-time packet subscriptions. ByteNet's `listen` has no unsubscribe,
	-- but App mounts exactly once for the client's whole session, so a
	-- single registration is correct (not a leak).
	React.useEffect(function()
		Net.RunStarted.listen(function()
			setElapsed(0)
			setStartClock(os.clock())
			setRunning(true)
		end)
		-- Staging countdown, and the cue to clear the previous round's board.
		Net.RoundState.listen(function(payload: { state: string, secondsRemaining: number })
			if payload.state ~= "Staging" then
				setCountdown(nil)
				return
			end
			setResults(nil)
			setRunning(false)
			setElapsed(0)
			setStartClock(nil)
			setCountdown(payload.secondsRemaining)
			EscapeCinematic.stop()
		end)
		-- Round over: play the pull-back over the maze, then show the board.
		Net.RoundEnded.listen(function(payload: { winnerName: string, hauls: { { name: string, haul: number } } })
			setRunning(false)
			task.spawn(function()
				EscapeCinematic.play()
				setResults(payload)
			end)
		end)
		return nil
	end, {} :: { any })

	-- Live-tick the timer while running. Purely cosmetic — the authoritative
	-- time comes from the server's Escaped payload, not this client clock.
	React.useEffect(function()
		if not running or startClock == nil then
			return nil
		end
		local runStartClock = startClock :: number
		local connection = RunService.Heartbeat:Connect(function()
			setElapsed(os.clock() - runStartClock)
		end)
		return function()
			connection:Disconnect()
		end
	end, { running, startClock } :: { any })

	return React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Timer = React.createElement("TextLabel", {
			Size = UDim2.fromOffset(240, TIMER_TEXT_SIZE + 10),
			Position = UDim2.new(0.5, 0, 0, 12),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			Text = formatTimer(elapsed),
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = TIMER_TEXT_SIZE,
			FontFace = TIMER_FONT,
			ZIndex = 50,
		}, {
			UIStroke = React.createElement("UIStroke", {
				Thickness = 2,
			}),
		}),

		-- Staging countdown. Without this the player stands in a sealed room
		-- with no idea the door is about to open.
		Countdown = if countdown ~= nil
			then React.createElement("TextLabel", {
				Size = UDim2.fromOffset(520, 60),
				Position = UDim2.fromScale(0.5, 0.42),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Text = if countdown > 0
					then string.format("DOORS OPEN IN %d", countdown)
					else "GO",
				TextColor3 = Color3.fromRGB(255, 235, 190),
				TextSize = 44,
				FontFace = TIMER_FONT,
				ZIndex = 60,
			}, {
				UIStroke = React.createElement("UIStroke", { Thickness = 2 }),
			})
			else nil,

		ResultsHost = if results ~= nil
			then React.createElement(WinScreen, {
				winnerName = results.winnerName,
				hauls = results.hauls,
				localName = Players.LocalPlayer.Name,
			})
			else nil,
	})
end

function UIController.Start()
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "MazeRoot"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = playerGui

	local root = ReactRoblox.createRoot(screen)
	root:render(React.createElement(App))
end

return UIController
