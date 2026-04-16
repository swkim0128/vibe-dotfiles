-- This file needs to have same structure as nvconfig.lua
-- https://github.com/NvChad/ui/blob/v3.0/lua/nvconfig.lua
-- Please read that file to know all available options :(

---@type ChadrcConfig
local M = {}

M.base46 = {
	theme = "catppuccin",
  transparency = true,

	hl_override = {
		Comment = { italic = true },
		["@comment"] = { italic = true },

    -- 비주얼 모드 글자색/배경색 명확화
    Visual = { bg = "#4C566A", fg = "#FFFFFF", bold = true },
	},
}

-- M.nvdash = { load_on_startup = true }
-- M.ui = {
--       tabufline = {
--          lazyload = false
--      }
-- }

return M
