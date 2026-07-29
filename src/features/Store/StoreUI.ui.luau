--!strict
-- Pure/dumb React component for the shelf. Takes the already-sorted catalogue,
-- the player's balance and what they own/rented, and calls back with the two
-- intents. It reads nothing, sends nothing and validates nothing — the server
-- re-derives every price and every eligibility check (see docs/game/Store.md).
--
-- The container that wires this to live data is StoreView.client.luau. A
-- separate story (StoreUI.story.luau) feeds it mock items so the shelf renders
-- in UI Labs without a live replica.
--
-- Centred per CLAUDE.md's centre-by-default rule: this is a small window, not a
-- screen-dominating inventory.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local Registry = require(script.Parent.Registry)

local WINDOW_SIZE = UDim2.fromOffset(680, 560)

local ROW_HEIGHT = 108
local ROW_PADDING = 16
local BUTTON_SIZE = UDim2.fromOffset(210, 52)

local NAME_TEXT_SIZE = 28
local DESC_TEXT_SIZE = 17
local PRICE_TEXT_SIZE = 17
local HEADER_TEXT_SIZE = 24
local EMPTY_TEXT_SIZE = 20

local DESC_COLOR = Color3.fromRGB(186, 196, 208)
local PRICE_COLOR = Color3.fromRGB(255, 224, 140)
local LOCKED_COLOR = Color3.fromRGB(170, 180, 195)
local NOTICE_COLOR = Color3.fromRGB(255, 140, 140)
local CLOSED_COLOR = Color3.fromRGB(255, 190, 120)

export type Props = {
	items: { Registry.Item },
	cash: number,
	unlocked: { [string]: boolean },
	rented: { [string]: boolean },
	-- Purchases are staging-only; false greys every button out.
	canBuy: boolean,
	-- Transient rejection message from the server, or nil.
	notice: string?,
	onUnlock: (id: string) -> (),
	onRent: (id: string) -> (),
	onClose: () -> (),
}

-- An item is owned when it ships on the shelf (unlockCost 0) or the profile
-- says so. Mirrors StoreService.isUnlocked — the server is still the authority;
-- this only decides which button to draw.
local function isOwned(def: Registry.Item, unlocked: { [string]: boolean }): boolean
	return def.unlockCost <= 0 or unlocked[def.id] == true
end

local function priceLine(def: Registry.Item, owned: boolean): string
	if not owned then
		return string.format("Unlock %d  ·  then %d per run", def.unlockCost, def.rentCost)
	end
	return string.format("%d per run", def.rentCost)
end

local function itemRow(props: Props, def: Registry.Item, layoutOrder: number): any
	local owned = isOwned(def, props.unlocked)
	local inLoadout = props.rented[def.id] == true and not def.repeatable

	-- Three mutually exclusive button states, resolved once so the render body
	-- stays flat: buy the unlock, take it into the round, or already holding it.
	local buttonText: string
	local buttonVariant: string
	local cost: number
	local onClick: (() -> ())?
	if not owned then
		buttonText, buttonVariant, cost = `UNLOCK  {def.unlockCost}`, "yellow", def.unlockCost
		onClick = function()
			props.onUnlock(def.id)
		end
	elseif inLoadout then
		buttonText, buttonVariant, cost = "IN LOADOUT", "white", 0
		onClick = nil
	else
		buttonText, buttonVariant, cost = `RENT  {def.rentCost}`, "green", def.rentCost
		onClick = function()
			props.onRent(def.id)
		end
	end

	local disabled = inLoadout or not props.canBuy or props.cash < cost

	return React.createElement(ui.Panel, {
		size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		layoutOrder = layoutOrder,
	}, {
		UIPadding = React.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, ROW_PADDING),
			PaddingRight = UDim.new(0, ROW_PADDING),
			PaddingTop = UDim.new(0, ROW_PADDING),
			PaddingBottom = UDim.new(0, ROW_PADDING),
		}),

		Name = React.createElement(ui.Text, {
			text = def.label,
			textSize = NAME_TEXT_SIZE,
			weight = Enum.FontWeight.Bold,
			color = if owned then nil else LOCKED_COLOR,
			xAlignment = Enum.TextXAlignment.Left,
			yAlignment = Enum.TextYAlignment.Top,
			size = UDim2.new(1, -BUTTON_SIZE.X.Offset - 20, 0, NAME_TEXT_SIZE + 4),
			position = UDim2.fromOffset(0, 0),
		}),

		Description = React.createElement(ui.Text, {
			text = def.description or "",
			textSize = DESC_TEXT_SIZE,
			color = DESC_COLOR,
			xAlignment = Enum.TextXAlignment.Left,
			yAlignment = Enum.TextYAlignment.Top,
			size = UDim2.new(1, -BUTTON_SIZE.X.Offset - 20, 0, DESC_TEXT_SIZE + 6),
			position = UDim2.fromOffset(0, NAME_TEXT_SIZE + 8),
		}),

		Price = React.createElement(ui.Text, {
			text = priceLine(def, owned),
			textSize = PRICE_TEXT_SIZE,
			color = PRICE_COLOR,
			xAlignment = Enum.TextXAlignment.Left,
			yAlignment = Enum.TextYAlignment.Bottom,
			size = UDim2.new(1, -BUTTON_SIZE.X.Offset - 20, 0, PRICE_TEXT_SIZE + 4),
			position = UDim2.new(0, 0, 1, 0),
			anchorPoint = Vector2.new(0, 1),
		}),

		Action = React.createElement(ui.Button, {
			variant = buttonVariant :: any,
			text = buttonText,
			textSize = 22,
			size = BUTTON_SIZE,
			position = UDim2.new(1, 0, 0.5, 0),
			anchorPoint = Vector2.new(1, 0.5),
			disabled = disabled,
			onClick = onClick,
		}),
	})
end

return function(props: Props)
	local children: { [string]: any } = {
		Balance = React.createElement(ui.Text, {
			text = `CASH  {props.cash}`,
			textSize = HEADER_TEXT_SIZE,
			weight = Enum.FontWeight.Bold,
			color = PRICE_COLOR,
			xAlignment = Enum.TextXAlignment.Left,
			size = UDim2.new(1, 0, 0, HEADER_TEXT_SIZE + 8),
			layoutOrder = 1,
		}),
	}

	-- Two different reasons a button might be dead. Say which, rather than
	-- leaving the player clicking a greyed-out box.
	if not props.canBuy then
		children.Closed = React.createElement(ui.Text, {
			text = "The shelf closes when the doors open.",
			textSize = DESC_TEXT_SIZE,
			color = CLOSED_COLOR,
			xAlignment = Enum.TextXAlignment.Left,
			size = UDim2.new(1, 0, 0, DESC_TEXT_SIZE + 6),
			layoutOrder = 2,
		})
	end

	if props.notice ~= nil then
		children.Notice = React.createElement(ui.Text, {
			text = props.notice,
			textSize = DESC_TEXT_SIZE,
			color = NOTICE_COLOR,
			xAlignment = Enum.TextXAlignment.Left,
			size = UDim2.new(1, 0, 0, DESC_TEXT_SIZE + 6),
			layoutOrder = 3,
		})
	end

	if #props.items == 0 then
		children.Empty = React.createElement(ui.Text, {
			text = "Nothing on the shelf yet.",
			textSize = EMPTY_TEXT_SIZE,
			color = DESC_COLOR,
			size = UDim2.new(1, 0, 0, 80),
			layoutOrder = 10,
		})
	end

	for i, def in props.items do
		children[`Item_{def.id}`] = itemRow(props, def, 10 + i)
	end

	return React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ZIndex = 90,
	}, {
		Window = React.createElement(ui.Window, {
			title = "SHELF",
			size = WINDOW_SIZE,
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
			onClose = props.onClose,
		}, children),
	})
end
