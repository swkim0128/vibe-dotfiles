local config = assert(hs.json.read(hs.configdir .. "/herdr-alert.json"), "Herdr alert config missing")
local previous

return function(payload)
    local state = config.states[payload.status]
    if not state then return end
    local style = {}
    for key, value in pairs(config.style) do style[key] = value end
    style.textColor = { hex = state.color }
    style.strokeColor = { hex = state.color }
    if previous then hs.alert.closeSpecific(previous, 0) end
    previous = hs.alert.show("Herdr · " .. state.label .. "\n" .. payload.text,
        style, hs.screen.mainScreen(), state.seconds)
    return previous
end
