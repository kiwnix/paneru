local M = {
  sbar = nil,
  theme = nil,
  network = nil,
  details = {},
}

local function set_detail(name, label, color)
  local item = M.details[name]
  if not item then
    return
  end
  item:set({
    label = {
      string = label ~= "" and label or "-",
      color = color,
    },
    icon = {
      color = color,
    },
    background = {
      drawing = "off",
    },
  })
end

function M.refresh()
  if not M.sbar or not M.network then
    return
  end

  local command = [=[
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

latency="$(/sbin/ping -q -c 1 -W 1000 1.1.1.1 2>/dev/null | /usr/bin/awk -F/ '/round-trip|rtt/ { printf "%.0f", $5 }')"
wifi="$(/usr/sbin/ipconfig getsummary en0 2>/dev/null | /usr/bin/awk '
  /^[[:space:]]*SSID[[:space:]]*:/ {
    sub(/^[^:]*:[[:space:]]*/, "")
    if ($0 != "" && $0 != "<redacted>") {
      print
      exit
    }
  }
')"
if [ -z "$wifi" ] || [ "$wifi" = "<redacted>" ]; then
  wifi="$(/usr/sbin/networksetup -getairportnetwork en0 2>/dev/null | /usr/bin/sed -nE 's/^Current Wi-Fi Network: //p' | /usr/bin/head -n 1)"
fi
if [ -z "$wifi" ] || [ "$wifi" = "<redacted>" ]; then
  wifi="$(/usr/sbin/system_profiler SPAirPortDataType -json 2>/dev/null | jq -r '.SPAirPortDataType[]?.spairport_airport_interfaces[]?.spairport_current_network_information? | select(type == "object") | ._name // empty' 2>/dev/null | /usr/bin/head -n 1)"
fi
if [ "$wifi" = "<redacted>" ]; then
  wifi=""
fi

private_ip="$(
  iface="$(/usr/sbin/route -n get default 2>/dev/null | /usr/bin/awk '/interface:/ { print $2; exit }')"
  if [ -n "$iface" ]; then
    /usr/sbin/ipconfig getifaddr "$iface" 2>/dev/null
  fi
)"
if [ -z "$private_ip" ]; then
  private_ip="$(/sbin/ifconfig 2>/dev/null | /usr/bin/awk '/^[a-z0-9]+:/{ iface=$1; sub(":", "", iface) } /^[[:space:]]*inet / && iface != "lo0" && $2 !~ /^127\./ { print $2; exit }')"
fi

public_ip="$(/usr/bin/curl -fsS --max-time 2 https://api.ipify.org 2>/dev/null || true)"
if [ -z "$public_ip" ]; then
  public_ip="$(/usr/bin/curl -fsS --max-time 2 https://ifconfig.me/ip 2>/dev/null || true)"
fi

tailscale="$(
  json="$(tailscale status --json 2>/dev/null)" &&
    printf "%s" "$json" | jq -e . >/dev/null 2>&1 &&
    printf "%s" "$json" | jq -r 'if (.BackendState // "Stopped") == "Running" then "on\t" + (.Self.TailscaleIPs[0] // "") else "off\t" end' 2>/dev/null ||
    {
      route="$(/usr/sbin/netstat -rn -f inet 2>/dev/null | /usr/bin/sed -nE 's/^100\.100\.100\.100[[:space:]].*[[:space:]](utun[0-9]+)[[:space:]]*$/\1/p' | /usr/bin/head -n 1)"
      ip=""
      if [ -n "$route" ]; then
        ip="$(/sbin/ifconfig "$route" 2>/dev/null | /usr/bin/sed -nE 's/^[[:space:]]*inet ([0-9.]+).*/\1/p' | /usr/bin/head -n 1)"
      fi
      if [ -n "$route" ]; then
        printf "on\t%s\n" "$ip"
      else
        printf "off\t\n"
      fi
    }
)"

netbird="$(
  json="$(netbird status --json 2>/dev/null)" &&
    printf "%s" "$json" | jq -e . >/dev/null 2>&1 &&
    printf "%s" "$json" | jq -r 'if (((.daemonStatus // .status // "") | ascii_downcase) == "connected") or (.management.connected // false) or (.signal.connected // false) then "on\t" + (.netbirdIp // .netbird_ip // "") else "off\t" end' 2>/dev/null ||
    {
      if netbird status 2>/dev/null | /usr/bin/grep -Eiq 'daemon status:[[:space:]]*connected([[:space:]]|$)|^connected([[:space:]]|$)'; then
        printf "on\t\n"
      else
        printf "off\t\n"
      fi
    }
)"

printf "%s\n%s\n%s\n%s\n%s\n%s\n" "$latency" "${wifi:-sin Wi-Fi}" "$private_ip" "$public_ip" "$tailscale" "$netbird"
]=]

  M.sbar.exec(command, function(result)
    local output = type(result) == "string" and result or ""
    local lines = {}
    for line in output:gmatch("([^\n]*)\n?") do
      table.insert(lines, line)
      if #lines >= 6 then
        break
      end
    end

    local latency = lines[1] or ""
    local wifi = lines[2] ~= "" and lines[2] or "sin Wi-Fi"
    local private_ip = lines[3] or ""
    local public_ip = lines[4] or ""
    local tailscale_state, tailscale_ip = (lines[5] or "off\t"):match("([^\t]*)\t?(.*)")
    local netbird_state, netbird_ip = (lines[6] or "off\t"):match("([^\t]*)\t?(.*)")
    tailscale_state = tailscale_state ~= "" and tailscale_state or "off"
    netbird_state = netbird_state ~= "" and netbird_state or "off"

    local online = latency ~= ""
    local label = online and (latency .. "ms") or "offline"
    local status = online and "warn" or "critical"
    local tailscale_color = M.theme.status_color("critical")
    local netbird_color = M.theme.status_color("critical")

    if online and tailscale_state == "on" then
      label = label .. " TS"
      tailscale_color = M.theme.status_color("ok")
    end
    if online and netbird_state == "on" then
      label = label .. " NB"
      netbird_color = M.theme.status_color("ok")
    end
    if online and tailscale_state == "on" and netbird_state == "on" then
      status = "ok"
    end

    M.network:set({
      icon = {
        string = "NET",
        color = M.theme.status_color(status),
      },
      label = {
        string = label,
        color = M.theme.colors.text,
      },
      background = {
        color = M.theme.colors.surface_alt,
      },
      popup = {
        align = "right",
        background = {
          color = M.theme.colors.surface,
          border_width = 0,
        },
      },
    })

    set_detail("internet", online and "online" or "offline")
    set_detail("ping", online and (latency .. "ms") or "sin respuesta")
    set_detail("wifi", wifi)
    set_detail("private_ip", private_ip)
    set_detail("public_ip", public_ip)
    set_detail("tailscale", tailscale_state .. (tailscale_ip ~= "" and (" / " .. tailscale_ip) or ""), tailscale_color)
    set_detail("netbird", netbird_state .. (netbird_ip ~= "" and (" / " .. netbird_ip) or ""), netbird_color)
  end)
end

local function toggle_popup(item)
  item:set({
    popup = {
      align = "right",
      drawing = "toggle",
    },
  })
end

function M.setup(sbar, theme)
  M.sbar = sbar
  M.theme = theme

  M.network = sbar.add("item", "network", {
    position = "right",
    icon = {
      string = "NET",
    },
    label = {
      string = "...",
    },
    background = {
      color = theme.colors.surface_alt,
    },
    popup = {
      align = "right",
      background = {
        color = theme.colors.surface,
        border_width = 0,
      },
    },
    updates = "on",
    update_freq = 60,
  })
  M.network:subscribe({
    "wifi_change",
    "system_woke",
  }, function()
    M.refresh()
  end)
  M.network:subscribe("mouse.clicked", function()
    toggle_popup(M.network)
  end)

  for _, detail in ipairs({
    { "internet", "Internet" },
    { "ping", "Ping" },
    { "wifi", "Wi-Fi" },
    { "private_ip", "IP privada" },
    { "public_ip", "IP publica" },
    { "tailscale", "Tailscale" },
    { "netbird", "NetBird" },
  }) do
    M.details[detail[1]] = sbar.add("item", "network.detail." .. detail[1], {
      position = "popup.network",
      icon = {
        string = detail[2],
        color = theme.colors.muted,
      },
      label = {
        string = "-",
      },
      background = {
        drawing = "off",
      },
    })
  end

  sbar.add("bracket", "network_block", { "network" }, {
    background = {
      color = theme.colors.surface,
      border_width = 0,
    },
  })
end

return M
