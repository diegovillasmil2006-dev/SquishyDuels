--!strict
-- ReminderOptIn (client only; not a controller: no init or start, the bootstrap does not load it). Come-back reminders
-- (2026-10-30, Config.Reminders): offer() asks once per session, right after a reward that comes back later
-- (DailyController's claim, PenController's "while you were away" pop-up closing), and only while a reminder is set
-- up (a message id in Config.Reminders). When Roblox allows its opt-in box (CanPromptOptInAsync: 13+, not on yet, not
-- shown in the last 30 days) the ask line shows as a toast, then Roblox's own box opens (its text is fixed). Nothing
-- in the game needs the reminders on.

local ExperienceNotificationService = game:GetService("ExperienceNotificationService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local REMINDERS = require(Shared.Config.Reminders)
local Strings = require(Shared.Strings)
local UIController = require(script.Parent.UIController)

local ReminderOptIn = {}

local asked = false

function ReminderOptIn.offer()
	if asked or (REMINDERS.penMessageId == "" and REMINDERS.dailyMessageId == "") then
		return
	end
	asked = true
	task.spawn(function()
		local ok, can = pcall(ExperienceNotificationService.CanPromptOptInAsync, ExperienceNotificationService)
		if not ok or can ~= true then
			return
		end
		UIController.toast(Strings.reminders.ask, "info")
		task.wait(REMINDERS.askDelaySeconds)
		pcall(ExperienceNotificationService.PromptOptIn, ExperienceNotificationService)
	end)
end

return ReminderOptIn
