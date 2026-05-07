local theme = require("lib.theme")
local paneru = require("items.paneru")
local network = require("items.network")

local M = {}

function M.setup(sbar, config_dir)
	local plugin_dir = config_dir .. "/plugins"
	local paneru_subscriber = plugin_dir .. "/paneru_subscribe.sh"

	sbar.bar({
		position = "bottom",
		height = 44,
		color = theme.colors.bar,
		margin = 0,
		padding_left = 10,
		padding_right = 10,
		display = "all",
		sticky = "on",
		topmost = "on",
		shadow = "on",
	})

	sbar.default({
		updates = "when_shown",
		icon = {
			font = theme.fonts.mono .. ":Bold:12.5",
			color = theme.colors.text,
			padding_left = 10,
			padding_right = 6,
		},
		label = {
			font = theme.fonts.text .. ":Semibold:12.5",
			color = theme.colors.text,
			padding_left = 4,
			padding_right = 10,
		},
		background = {
			height = 30,
			corner_radius = 10,
			color = theme.colors.surface,
			border_width = 0,
		},
		popup = {
			background = {
				color = theme.colors.surface,
				border_width = 0,
			},
		},
	})

	paneru.setup(sbar, theme)
	network.setup(sbar, theme)

	sbar.exec('pkill -f "' .. paneru_subscriber .. '" >/dev/null 2>&1 || true')
	sbar.exec('"' .. paneru_subscriber .. '" >/dev/null 2>&1 &')
	sbar.exec("sketchybar --update")
end

function M.refresh()
	paneru.refresh()
	network.refresh()
end

return M
