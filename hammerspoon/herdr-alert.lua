local config = assert(hs.json.read(hs.configdir .. "/herdr-alert.json"), "Herdr alert config missing")
local previous
local expiry

return function(payload)
    local state = config.states[payload.status]
    if not state then return end
    if expiry then expiry:stop() end
    if previous then previous:delete() end
    local style = config.style
    local text = "Herdr · " .. state.label .. "\n" .. payload.text
    local canvas = hs.canvas.new({ x = 0, y = 0, w = 100, h = 100 })
    canvas:canvasDefaultFor("textSize", style.textSize)
    canvas:canvasDefaultFor("textFont", ".AppleSystemUIFont")
    local size = canvas:minimumTextSize(text)
    local width = math.ceil(size.w) + style.padding * 2 + style.strokeWidth
    local height = math.ceil(size.h) + style.padding * 2 + style.strokeWidth
    local screen = hs.screen.mainScreen():frame()
    local frame = { x = screen.x + (screen.w - width) / 2,
        y = screen.y + config.position.topMargin, w = width, h = height }
    canvas:frame(frame)
    canvas:appendElements(
        { type = "rectangle", action = "strokeAndFill",
            frame = { x = style.strokeWidth, y = style.strokeWidth,
                w = width - style.strokeWidth * 2, h = height - style.strokeWidth * 2 },
            roundedRectRadii = { xRadius = style.radius, yRadius = style.radius },
            fillColor = style.fillColor, strokeColor = { hex = state.color },
            strokeWidth = style.strokeWidth },
        { type = "text", text = text, textColor = { hex = state.color },
            textAlignment = "center",
            frame = { x = style.padding, y = style.padding,
                w = width - style.padding * 2, h = height - style.padding * 2 } })
    canvas:behavior({ "canJoinAllSpaces", "fullScreenAuxiliary" })
    canvas:level("overlay"):clickActivating(false):show()
    previous = canvas
    expiry = hs.timer.doAfter(state.seconds, function()
        canvas:delete()
        if previous == canvas then previous = nil end
    end)
    return hs.host.uuid(), canvas:frame()
end
