local M = {}

local function is_bundle_like(value)
  return type(value) == "string" and value:match("^[%w%-]+%.") ~= nil
end

local function normalize_name(value)
  if not value or value == "" then
    return ""
  end
  return tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalize_app_ref(app_ref)
  if type(app_ref) == "table" then
    local bundle_id = normalize_name(app_ref.bundle_id or app_ref.bundleId or app_ref.identifier)
    local app_name = normalize_name(app_ref.app_name or app_ref.appName or app_ref.name)
    if bundle_id == "" and is_bundle_like(app_name) then
      bundle_id = app_name
    end
    return {
      bundle_id = bundle_id,
      app_name = app_name,
    }
  end

  local raw = normalize_name(app_ref)
  if raw == "" then
    return {
      bundle_id = "",
      app_name = "",
    }
  end

  if is_bundle_like(raw) then
    return {
      bundle_id = raw,
      app_name = "",
    }
  end

  return {
    bundle_id = "",
    app_name = raw,
  }
end

function M.app_display_name(app_name)
  if type(app_name) == "table" then
    local ref = normalize_app_ref(app_name)
    if ref.app_name ~= "" then
      return ref.app_name
    end
    app_name = ref.bundle_id
  end

  if not app_name or app_name == "" then
    return ""
  end

  local last = app_name:match("([^%.]+)$")
  if last and last ~= "" and last ~= app_name then
    return (last:gsub("[-_]", " "))
  end

  return app_name
end

function M.app_image_string(app_ref)
  local ref = normalize_app_ref(app_ref)

  if ref.bundle_id ~= "" then
    return "app." .. ref.bundle_id
  end

  return ""
end

function M.app_identity_key(app_ref)
  local ref = normalize_app_ref(app_ref)

  if ref.bundle_id ~= "" then
    return "bundle:" .. ref.bundle_id:lower()
  end

  return ""
end

return M
