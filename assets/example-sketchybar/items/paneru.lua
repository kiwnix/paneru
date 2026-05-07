local icons = require("lib.icons")
local paneru = require("lib.libpaneru")

local M = {
	sbar = nil,
	theme = nil,
	workspaces = {},
	workspace_apps = {},
	workspace_brackets = {},
	front_app = nil,
	paneru_sync = nil,
	last_state = nil,
	query_delay_seconds = "0.1",
}

local function bool_string(value)
	return value and "on" or "off"
end

local function apps_for_row(rows, virtual_number)
	local apps = {}
	local seen = {}

	for _, app in ipairs(paneru.virtual_row_app_refs(rows, virtual_number)) do
		local key = icons.app_identity_key(app)
		local image = icons.app_image_string(app)
		if key ~= "" and image ~= "" and not seen[key] then
			seen[key] = true
			table.insert(apps, {
				ref = app,
				key = key,
				image = image,
			})
		end
		if #apps >= 4 then
			break
		end
	end

	return apps
end

local function app_matches(left, right)
	local left_key = icons.app_identity_key(left)
	local right_key = icons.app_identity_key(right)

	if left_key == "" or right_key == "" then
		return false
	end

	return left_key == right_key
end

function M.apply_state(state, env)
	if type(state) ~= "table" then
		return
	end

	local rows = paneru.normalize_rows(state)
	local current = paneru.current_virtual_number(state, env)
	local focused_app = paneru.first_value({
		env and env.INFO,
		env and env.PANERU_APP_NAME,
	})
	if focused_app == "" then
		focused_app = paneru.focused_app_ref_from_state(state)
	end

	for virtual_index = 0, 8 do
		local display_id = virtual_index + 1
		local item = M.workspaces[display_id]
		local row_apps = apps_for_row(rows, display_id)
		local active = current == display_id

		item:set({
			icon = {
				string = tostring(display_id),
				color = active and M.theme.colors.dark_text or M.theme.colors.muted,
			},
			label = {
				drawing = "off",
			},
			background = {
				drawing = bool_string(not active),
				color = M.theme.colors.surface,
				border_width = 0,
			},
		})

		for slot = 1, 4 do
			local app_item = M.workspace_apps[display_id][slot]
			local app = row_apps[slot]
			local focused = active and app and app_matches(app.ref, focused_app)
			local has_image = app and app.image ~= ""

			app_item:set({
				drawing = bool_string(app ~= nil),
				icon = {
					font = M.theme.fonts.app .. ":Regular:17.0",
					drawing = "off",
					color = focused and M.theme.colors.accent
						or (active and M.theme.colors.dark_text or M.theme.colors.muted),
				},
				label = {
					drawing = "off",
				},
				background = {
					drawing = bool_string(focused or has_image),
					color = M.theme.colors.surface_alt,
					border_width = 0,
					image = {
						drawing = bool_string(has_image),
						string = has_image and app.image or "",
						scale = 0.55,
						padding_left = 2,
						padding_right = 2,
					},
				},
			})
		end

		M.workspace_brackets[display_id]:set({
			background = {
				drawing = bool_string(active),
				color = active and M.theme.colors.accent or M.theme.colors.surface_alt,
				border_width = 0,
			},
		})
	end
end

local function delayed_refresh(env)
	if env == nil then
		return false
	end

	local paneru_event = env.PANERU_EVENT or ""
	return paneru_event == "windows_changed"
		or paneru_event == "virtual_workspace_changed"
		or paneru_event == "display_changed"
		or (paneru_event == "" and env.PANERU_VIRTUAL_WORKSPACE_NUMBER ~= nil)
end

local function query_state_command(env)
	if delayed_refresh(env) then
		return "sleep " .. M.query_delay_seconds .. "; paneru query state --json"
	end

	return "paneru query state --json"
end

function M.refresh(env)
	if not M.sbar then
		return
	end

	M.sbar.exec(query_state_command(env), function(result, exit_code)
		if exit_code ~= 0 or type(result) ~= "table" then
			return
		end

		M.last_state = result
		M.apply_state(result, env)
		M.refresh_front_app_from_state(result, env)
	end)
end

function M.apply_cached_state(env)
	if type(M.last_state) ~= "table" then
		return
	end

	M.apply_state(M.last_state, env)
end

function M.refresh_front_app_from_state(state, env)
	if not M.front_app then
		return
	end

	local app = paneru.first_value({
		env and env.INFO,
		env and env.PANERU_APP_NAME,
	})
	local app_ref = app
	local title = env and env.PANERU_WINDOW_TITLE or ""

	if app == "" or title == "" then
		local state_ref, state_title = paneru.focused_app_ref_from_state(state)
		local state_app = icons.app_display_name(state_ref)
		if app == "" then
			app = state_app
			app_ref = state_ref
		end
		if title == "" then
			title = state_title
		end
	end

	local display_name = icons.app_display_name(app_ref)
	local image = icons.app_image_string(app_ref)
	local has_image = image ~= ""
	M.front_app:set({
		icon = {
			font = M.theme.fonts.app .. ":Regular:16.0",
			drawing = "off",
			color = M.theme.colors.accent,
		},
		label = {
			string = title ~= "" and title or display_name,
			max_chars = 64,
			padding_left = has_image and 30 or 10,
			padding_right = 10,
			color = M.theme.colors.text,
		},
		background = {
			color = M.theme.colors.surface_alt,
			image = {
				drawing = bool_string(has_image),
				string = image,
				scale = 0.6,
				padding_left = 5,
				padding_right = 6,
			},
		},
	})
end

local function workspace_click(display_id, env)
	local operation = env and env.MODIFIER == "shift" and "virtualsendnum" or "virtualnum"
	M.sbar.exec("paneru send-cmd window " .. operation .. " " .. tostring(display_id), function()
		M.sbar.trigger("paneru_workspace_changed", {
			PANERU_VIRTUAL_WORKSPACE_NUMBER = tostring(display_id),
		})
	end)
end

function M.setup(sbar, theme)
	M.sbar = sbar
	M.theme = theme

	sbar.add("event", "paneru_workspace_changed")
	sbar.add("event", "paneru_windows_changed")
	sbar.add("event", "paneru_front_app_changed")

	local members = {}
	for workspace_id = 0, 8 do
		local display_id = workspace_id + 1
		local name = "paneru_workspace_" .. tostring(workspace_id)
		local item = sbar.add("item", name, {
			icon = {
				string = tostring(display_id),
				font = theme.fonts.mono .. ":Bold:12.5",
			},
			label = {
				string = " ",
				font = theme.fonts.app .. ":Regular:17.0",
				padding_left = 7,
				padding_right = 10,
			},
			background = {
				drawing = "on",
			},
		})

		item:subscribe("mouse.clicked", function(env)
			workspace_click(display_id, env)
		end)

		M.workspaces[display_id] = item
		table.insert(members, name)

		M.workspace_apps[display_id] = {}
		local workspace_members = { name }
		for slot = 1, 4 do
			local app_name = name .. "_app_" .. tostring(slot)
			local app_item = sbar.add("item", app_name, {
				drawing = "off",
				icon = {
					font = theme.fonts.app .. ":Regular:17.0",
					padding_left = 2,
					padding_right = 2,
				},
				label = {
					drawing = "off",
				},
				background = {
					height = 24,
					corner_radius = 8,
					border_width = 0,
					image = {
						drawing = "off",
					},
				},
			})

			app_item:subscribe("mouse.clicked", function(env)
				workspace_click(display_id, env)
			end)

			M.workspace_apps[display_id][slot] = app_item
			table.insert(members, app_name)
			table.insert(workspace_members, app_name)
		end

		M.workspace_brackets[display_id] = sbar.add("bracket", name .. "_block", workspace_members, {
			background = {
				drawing = "off",
				color = theme.colors.surface_alt,
				border_width = 0,
			},
		})
	end

	M.paneru_sync = sbar.add("item", "paneru_sync", {
		drawing = "on",
		icon = { drawing = "off" },
		label = { drawing = "off" },
		background = { drawing = "off" },
		width = 0,
		padding_left = 0,
		padding_right = 0,
		updates = "on",
	})
	M.paneru_sync:subscribe({ "system_woke", "display_change" }, function(env)
		M.refresh(env)
	end)
	M.paneru_sync:subscribe("paneru_workspace_changed", function(env)
		M.apply_cached_state(env)
		M.refresh(env)
	end)
	M.paneru_sync:subscribe("paneru_windows_changed", function(env)
		M.refresh(env)
	end)
	M.paneru_sync:subscribe("paneru_front_app_changed", function(env)
		M.apply_cached_state(env)
	end)

	M.front_app = sbar.add("item", "front_app", {
		position = "center",
		icon = {
			font = theme.fonts.app .. ":Regular:16.0",
			color = theme.colors.accent,
		},
		label = {
			max_chars = 64,
			color = theme.colors.text,
		},
		background = {
			color = theme.colors.surface_alt,
		},
	})
	M.front_app:subscribe({
		"paneru_workspace_changed",
		"paneru_front_app_changed",
	}, function(env)
		if env and (env.INFO or env.PANERU_WINDOW_TITLE) then
			M.refresh_front_app_from_state({}, env)
		else
			M.refresh(env)
		end
	end)

	table.insert(members, "front_app")
	sbar.add("bracket", "paneru_block", members, {
		background = {
			color = theme.colors.surface,
			border_width = 0,
		},
	})
end

return M
