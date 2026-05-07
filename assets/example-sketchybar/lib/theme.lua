local M = {}

M.colors = {
  bar = os.getenv("SKETCHYBAR_COLOR_BAR") or "0xe61a1b26",
  base = os.getenv("SKETCHYBAR_COLOR_BASE") or "0xe61a1b26",
  surface = os.getenv("SKETCHYBAR_COLOR_SURFACE") or "0x44272a3a",
  surface_alt = os.getenv("SKETCHYBAR_COLOR_SURFACE_ALT") or "0x66343a4f",
  text = os.getenv("SKETCHYBAR_COLOR_TEXT") or "0xffd9e0ee",
  muted = os.getenv("SKETCHYBAR_COLOR_MUTED") or "0xff8f99b3",
  ok = os.getenv("SKETCHYBAR_COLOR_OK") or "0xffa6e3a1",
  warn = os.getenv("SKETCHYBAR_COLOR_WARN") or "0xfff9e2af",
  critical = os.getenv("SKETCHYBAR_COLOR_CRITICAL") or "0xfff38ba8",
  accent = os.getenv("SKETCHYBAR_COLOR_ACCENT") or "0xffb4befe",
  dark_text = os.getenv("SKETCHYBAR_COLOR_DARK_TEXT") or "0xff11111b",
}

M.fonts = {
  text = "Work Sans",
  mono = "Monaspace Neon",
  app = "sketchybar-app-font",
}

function M.status_color(status)
  if status == "ok" then
    return M.colors.ok
  end
  if status == "warn" then
    return M.colors.warn
  end
  if status == "critical" then
    return M.colors.critical
  end
  if status == "accent" then
    return M.colors.accent
  end
  return M.colors.muted
end

return M
