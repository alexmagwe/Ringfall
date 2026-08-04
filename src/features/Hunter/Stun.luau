--!strict
-- "Hunters can be switched off for a few seconds." The MECHANISM lives here,
-- in the feature that owns hunters; the reason one gets switched off belongs to
-- whoever calls `pulse`.
--
-- This is the same seam `HunterAlert` already is. GunService raises the alert on
-- every unsilenced shot and HunterService consumes it, and neither file names
-- the other's feature. A stun is the mirror image of that — one feature acting
-- on hunters without either of them learning what the other is — so it gets the
-- same treatment rather than an EMP-shaped branch inside the AI loop.
--
-- The state is a plain attribute on the hunter model, not a table in here, so it
-- survives this module being required from either realm and is visible in the
-- Explorer while you are debugging a stun that did not land.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Hunter.Stun.

local Stun = {}

-- Set by HunterService on every model it builds, so `pulse` never has to guess
-- what is and isn't a hunter from names or class alone.
Stun.TAG_ATTRIBUTE = "IsHunter"
Stun.ATTRIBUTE = "StunnedUntil"

-- `workspace:GetServerTimeNow()`, NOT `os.clock()`. The value rides on a
-- replicated attribute, and os.clock is wall time since each peer's own process
-- started — a client comparing the server's number against its own would get an
-- answer that is wrong by however long the two have been running. Server time is
-- the one clock both realms agree on.
local function now(): number
	return workspace:GetServerTimeNow()
end

-- Switch off every hunter within `radius` of `position` for `seconds`.
-- Returns how many were hit, which is what a caller needs to decide whether the
-- shot deserves a "3 DISABLED" readout or a miss.
--
-- Stacking rule: a pulse only ever EXTENDS a stun, never shortens one. Two
-- overlapping pulses should not leave a hunter less disabled than the first
-- one did.
function Stun.pulse(position: Vector3, radius: number, seconds: number): number
	local expiry = now() + seconds
	local count = 0
	for _, model in workspace:GetChildren() do
		if not model:IsA("Model") or model:GetAttribute(Stun.TAG_ATTRIBUTE) ~= true then
			continue
		end
		local root = model.PrimaryPart
		if not root or (root.Position - position).Magnitude > radius then
			continue
		end
		local current = model:GetAttribute(Stun.ATTRIBUTE)
		if typeof(current) == "number" and current >= expiry then
			continue
		end
		model:SetAttribute(Stun.ATTRIBUTE, expiry)
		count += 1
	end
	return count
end

function Stun.isStunned(model: Instance): boolean
	local expiry = model:GetAttribute(Stun.ATTRIBUTE)
	return typeof(expiry) == "number" and expiry > now()
end

return Stun
