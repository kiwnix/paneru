local M = {}

local function first_value(values)
	for _, value in ipairs(values) do
		if value ~= nil and value ~= "" then
			return tostring(value)
		end
	end
	return ""
end

M.first_value = first_value

function M.normalize_rows(state)
	if type(state) ~= "table" then
		return {}
	end

	if type(state.virtual_workspaces) == "table" then
		return state.virtual_workspaces
	end

	local rows = {}
	if type(state.workspaces) ~= "table" then
		return rows
	end

	for _, workspace in ipairs(state.workspaces) do
		for _, strip in ipairs(workspace.strips or {}) do
			table.insert(rows, {
				number = (strip.virtual_index or strip.virtualIndex or 0) + 1,
				windows = strip.windows or {},
			})
		end
	end

	return rows
end

function M.current_virtual_number(state, env)
	if env and env.PANERU_VIRTUAL_WORKSPACE_NUMBER and env.PANERU_VIRTUAL_WORKSPACE_NUMBER ~= "" then
		return tonumber(env.PANERU_VIRTUAL_WORKSPACE_NUMBER)
	end

	if type(state) ~= "table" then
		return nil
	end

	if type(state.active) == "table" and state.active.virtual_workspace_number then
		return tonumber(state.active.virtual_workspace_number)
	end

	for _, row in ipairs(M.normalize_rows(state)) do
		if row.active == true then
			return tonumber(row.number)
		end
	end

	return nil
end

function M.app_name(window)
	if type(window) ~= "table" then
		return ""
	end

	return first_value({
		window.app_name,
		window.appName,
		window.bundle_id,
		window.bundleId,
		window.identifier,
	})
end

function M.window_app_ref(window)
	if type(window) ~= "table" then
		return nil
	end

	local ref = {
		bundle_id = first_value({
			window.bundle_id,
			window.bundleId,
			window.identifier,
		}),
		app_name = first_value({
			window.app_name,
			window.appName,
			window.name,
		}),
		title = first_value({
			window.title,
			window.window_title,
			window.windowTitle,
		}),
	}

	if ref.bundle_id == "" and ref.app_name == "" then
		return nil
	end

	return ref
end

function M.virtual_row_apps(rows, virtual_number)
	local apps = {}

	for _, row in ipairs(rows or {}) do
		if tostring(row.number or "") == tostring(virtual_number) then
			for _, window in ipairs(row.windows or {}) do
				local app = M.app_name(window)
				if app ~= "" then
					table.insert(apps, app)
				end
			end
		end
	end

	return apps
end

function M.virtual_row_app_refs(rows, virtual_number)
	local apps = {}

	for _, row in ipairs(rows or {}) do
		if tostring(row.number or "") == tostring(virtual_number) then
			for _, window in ipairs(row.windows or {}) do
				local app = M.window_app_ref(window)
				if app then
					table.insert(apps, app)
				end
			end
		end
	end

	return apps
end

function M.focused_app_from_state(state)
	if type(state) ~= "table" or type(state.active) ~= "table" then
		return "", ""
	end

	local active = state.active
	local app = first_value({ active.focused_app_name, active.focused_bundle_id })
	local title = first_value({ active.focused_window_title, active.focused_app_name })
	return app, title
end

function M.focused_app_ref_from_state(state)
	if type(state) ~= "table" or type(state.active) ~= "table" then
		return nil, ""
	end

	local active = state.active
	local ref = {
		bundle_id = first_value({ active.focused_bundle_id, active.bundle_id }),
		app_name = first_value({ active.focused_app_name, active.app_name }),
		title = first_value({ active.focused_window_title, active.title }),
	}
	local title = first_value({ ref.title, ref.app_name })

	if ref.bundle_id == "" and ref.app_name == "" then
		return nil, title
	end

	return ref, title
end

local function unescape_json_string(value)
	return (value:gsub('\\(["\\/bfnrt])', {
		['"'] = '"',
		["\\"] = "\\",
		["/"] = "/",
		b = "\b",
		f = "\f",
		n = "\n",
		r = "\r",
		t = "\t",
	}))
end

local function json_string_field(json, key)
	local _, value_start = json:find('"' .. key .. '"%s*:%s*"')
	if value_start == nil then
		return ""
	end

	local value = {}
	local escaped = false
	for index = value_start + 1, #json do
		local char = json:sub(index, index)
		if escaped then
			table.insert(value, "\\" .. char)
			escaped = false
		elseif char == "\\" then
			escaped = true
		elseif char == '"' then
			return unescape_json_string(table.concat(value))
		else
			table.insert(value, char)
		end
	end

	return ""
end

local function json_number_field(json, key)
	return json:match('"' .. key .. '"%s*:%s*(-?%d+)') or ""
end

local function json_field(json, key)
	return first_value({
		json_string_field(json, key),
		json_number_field(json, key),
	})
end

local function active_json(event_json)
	return event_json:match('"active"%s*:%s*(%b{})') or ""
end

function M.parse_event_json(event_json)
	if type(event_json) ~= "string" or event_json == "" then
		return nil
	end

	local active = active_json(event_json)
	local event_name = json_string_field(event_json, "event")
	if event_name == "" then
		return nil
	end

	local bundle_id = first_value({
		active ~= "" and json_string_field(active, "focused_bundle_id") or "",
		json_string_field(event_json, "bundle_id"),
	})
	local app_name = first_value({
		active ~= "" and json_string_field(active, "focused_app_name") or "",
		json_string_field(event_json, "focused_app_name"),
	})
	local focused_app = first_value({
		app_name,
		bundle_id,
	})

	return {
		event_name = event_name,
		virtual_number = first_value({
			active ~= "" and json_field(active, "virtual_workspace_number") or "",
			json_field(event_json, "virtual_workspace_number"),
		}),
		focused_app = focused_app,
		focused_app_ref = {
			bundle_id = bundle_id,
			app_name = app_name,
		},
		focused_title = first_value({
			active ~= "" and json_string_field(active, "focused_window_title") or "",
			json_string_field(event_json, "title"),
		}),
		raw = event_json,
	}
end

return M
