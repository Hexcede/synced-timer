local RunService = game:GetService("RunService")

local Trove = require(script.Parent.Trove)
local Signal = require(script.Parent.Signal)

local function getServerTime()
	return workspace:GetServerTimeNow()
end

local SyncedTimer = {}
SyncedTimer.__index = SyncedTimer

-- Creates a new timer
function SyncedTimer.new(interval: number)
	local self = setmetatable({}, SyncedTimer)
	
	local trove = Trove.new()

	self._interval = interval
	
	-- Events
	self.Tick = trove:Construct(Signal)
	self.PreTick = trove:Construct(Signal)
	self.PausedDurationChanged = trove:Construct(Signal)
	self._update = trove:Construct(Signal)

	self._trove = trove

	-- Pause status
	self._paused = false
	self._pausedDuration = 0

	self._updateBindings = trove:Extend()
	
	self._tickCount = 0
	self._startTime = -1
	self._nextTick = -1

	self._elapsedTime = 0

	return self
end

function SyncedTimer:GetElapsedTime()
	return self._elapsedTime
end

-- Changes the timer's interval
function SyncedTimer:SetInterval(interval: number)
	-- Set the next timer tick time to the last tick plus the new interval
	self._nextTick = self._nextTick - self._interval + interval

	-- Set the new timer start time to what it should be if the timer has been running for the tick count with the new interval
	self._startTime = self._nextTick - (self._tickCount * interval)

	-- Set the new timer interval
	self._interval = interval

	-- Update the timer immediately
	self:Update()
end

-- Updates the timer immediately
function SyncedTimer:Update()
	self._update:Fire()
end

-- Binds to a given event (or heartbeat) and updates the timer on that event being fired
function SyncedTimer:BindUpdate(event)
	self._updateBindings:Connect(event or RunService.Heartbeat, function()
		self:Update()
	end)
end

-- Unbinds all update events
function SyncedTimer:UnbindUpdate()
	self._updateBindings:Clean()
end

function SyncedTimer:Start()
	-- If there is already a thread, call resume instead
	if self._thread then
		self:Resume()
		return
	end

	-- Get the start time, the time of the first tick, and set the tick count to 1
	self._startTime = getServerTime()
	self._trueStartTime = self._startTime
	self._nextTick = self._startTime + self._interval
	self._tickCount = 1

	-- Defer a thread
	self._thread = task.defer(function()
		local thread = coroutine.running()
		repeat
			-- Wait for the timer to update
			self._update:Wait()

			-- Skip if the timer is paused
			if self._paused then
				continue
			end

			-- Get the current time
			local now = getServerTime()

			-- If a tick will occur
			if now >= self._nextTick + self._pausedDuration then
				-- Calculate elapsed time
				self._elapsedTime = now - self._trueStartTime - self._pausedDuration
			end

			-- While the current time is ahead of the tick, fire tick event
			while now >= self._nextTick + self._pausedDuration do
				-- Fire pre-tick event
				self.PreTick:Fire(self._interval)

				-- While the timer is paused, wait for another update
				while self._paused do
					self._update:Wait()
				end

				-- Fire tick event
				self.Tick:Fire(self._interval)

				-- Go to next tick
				self._tickCount += 1
				self._nextTick = self._startTime + (self._tickCount * self._interval)

				-- If the interval is less than or equal to zero, break to avoid an infinite loop
				if self._interval <= 0 then
					break
				end
			end
		until self._thread ~= thread
	end)
end

function SyncedTimer:StartNow()
	-- If there is already a thread, call resume instead
	if self._thread then
		self:Resume()
		return
	end
	
	-- Fire tick event immediately & start the timer
	self.Tick:Fire(self._interval)
	self:Start()
end

function SyncedTimer:SetPausedDuration(pausedDuration: number)
	self._pausedDuration = pausedDuration
	self.PausedDurationChanged:Fire(pausedDuration)
end

function SyncedTimer:ObservePausedDuration(callback: (pausedDuration: number) -> ()): () -> ()
	-- Connect to the PausedDurationchanged event
	local connection = self._trove:Connect(self.PausedDurationChanged, callback)

	-- Call the callback with the paused duration immediately
	task.spawn(callback, self._pausedDuration)

	-- Return unbind function
	return function()
		-- If the connection doesn't exist anymore, cancel
		if not connection then
			return
		end
		
		-- Disconnect the connection & clear it
		connection:Disconnect()
		connection = nil
	end
end

function SyncedTimer:GetPausedDuration()
	return self._pausedDuration
end

function SyncedTimer:Resume()
	-- If there is no thread, start the timer
	if not self._thread then
		self:Start()
		return
	end

	-- Set the timer as no longer paused
	self._paused = false

	-- If there is no paused time, cancel
	if not self._lastPause then
		return
	end

	-- Update the paused duration
	self:SetPausedDuration(self._pausedDuration + getServerTime() - self._lastPause)
	self._lastPause = nil

	-- Update the timer immediately
	self:Update()
end
function SyncedTimer:Pause()
	-- If the timer is already paused, cancel
	if self._paused then
		return
	end

	-- Set the timer as paused and store the pause time
	self._paused = true
	self._lastPause = getServerTime()
end

function SyncedTimer:Stop()
	-- If there is no active timer thread, cancel
	if not self._thread then
		return
	end

	-- Cancel the active timer thread & clear it
	task.cancel(self._thread)
	self._thread = nil

	-- Reset the timer
	self:Reset()
end

function SyncedTimer:Reset()
	-- Reset pause state
	self._paused = false
	self._lastPause = nil
	self._pauseDuration = 0
end

function SyncedTimer:Destroy()
	self._trove:Clean()
end

return SyncedTimer