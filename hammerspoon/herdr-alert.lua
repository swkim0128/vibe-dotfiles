local config = assert(hs.json.read(hs.configdir .. "/herdr-alert.json"), "Herdr alert config missing")
local previous
local expiry
local log = hs.logger.new("herdr-alert")

local function fit(canvas, text, available, suffix)
    if canvas:minimumTextSize(text .. suffix).w <= available then return text .. suffix end
    local low, high = 0, utf8.len(text)
    while low < high do
        local middle = math.ceil((low + high) / 2)
        local candidate = text:sub(1, (utf8.offset(text, middle + 1) or #text + 1) - 1) .. "…" .. suffix
        if canvas:minimumTextSize(candidate).w <= available then low = middle else high = middle - 1 end
    end
    return text:sub(1, (utf8.offset(text, low + 1) or #text + 1) - 1) .. "…" .. suffix
end

return function(payload)
    local state = config.states[payload.status]
    if not state then return end
    if expiry then expiry:stop() end
    if previous then previous:delete() end
    local style = config.style
    local title, suffix = "● " .. state.label, ""
    if payload.status == "done" and payload.subject ~= nil then
        title = payload.subject == "" and "● 작업 완료" or "● " .. payload.subject
        if payload.subject ~= "" then suffix = " 작업 완료" end
    end
    local text = tostring(payload.text or ""):gsub("%s+", " ")
    local canvas = hs.canvas.new({ x = 0, y = 0, w = 100, h = 100 })
    canvas:canvasDefaultFor("textSize", style.textSize)
    canvas:canvasDefaultFor("textFont", ".AppleSystemUIFont")
    local screen = hs.screen.mainScreen():frame()
    local inset = style.padding + style.strokeWidth
    local width = math.min(style.maxWidth, screen.w - style.padding * 2,
        math.ceil(math.max(canvas:minimumTextSize(title .. suffix).w, canvas:minimumTextSize(text).w)) + inset * 2)
    local available = width - inset * 2
    title = fit(canvas, title, available, suffix)
    text = fit(canvas, text, available, "")
    local titleHeight = math.ceil(canvas:minimumTextSize(title).h)
    local bodyHeight = text == "" and 0 or math.ceil(canvas:minimumTextSize(text).h)
    local gap = bodyHeight == 0 and 0 or style.lineGap
    local height = titleHeight + bodyHeight + gap + inset * 2
    local frame = { x = screen.x + (screen.w - width) / 2,
        y = screen.y + config.position.topMargin, w = width, h = height }
    canvas:frame(frame)
    canvas:appendElements(
        { type = "rectangle", action = "strokeAndFill",
            frame = { x = style.strokeWidth, y = style.strokeWidth,
                w = width - style.strokeWidth * 2, h = height - style.strokeWidth * 2 },
            roundedRectRadii = { xRadius = style.radius, yRadius = style.radius },
            fillColor = style.fillColor, strokeColor = style.strokeColor,
            strokeWidth = style.strokeWidth },
        { type = "text", text = title, textColor = { hex = state.color },
            textAlignment = "left",
            frame = { x = inset, y = inset, w = available, h = titleHeight } },
        { type = "text", text = text, textColor = style.textColor,
            textAlignment = "left",
            frame = { x = inset, y = inset + titleHeight + gap, w = available, h = bodyHeight } })
    canvas:behavior({ "canJoinAllSpaces", "fullScreenAuxiliary" })
    if type(payload.focus_executable) == "string" and type(payload.focus_target) == "string" then
        canvas:canvasMouseEvents(false, true, false, false)
        local clicked = false
        canvas:mouseCallback(function(_, message)
            if message ~= "mouseUp" or clicked then return end
            local task = hs.task.new(payload.focus_executable, function(code, _, err)
                if code ~= 0 then log.w(err) end
            end, { "focus-alert", payload.focus_target })
            if task and task:start() then clicked = true end
        end)
    end
    canvas:level("overlay"):clickActivating(false):show()
    previous = canvas
    expiry = hs.timer.doAfter(state.seconds, function()
        canvas:delete()
        if previous == canvas then previous = nil end
    end)
    return hs.host.uuid(), canvas:frame()
end
