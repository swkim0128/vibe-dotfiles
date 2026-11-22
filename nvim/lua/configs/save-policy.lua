local M = {}

-- 버퍼에서 확인된 인코딩만 판정한다. UTF-8 PHP의 대상 버전은 추정하지 않는다.
function M.is_legacy_encoding(bufnr)
  local encoding = vim.bo[bufnr].fileencoding:lower():gsub("[-_]", "")
  return encoding == "cp949" or encoding == "euckr"
end

return M
