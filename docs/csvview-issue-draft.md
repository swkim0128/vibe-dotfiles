# Inconsistent rendering after `:%!cmd` buffer mutation on large CSVs

## Environment

- Neovim: v0.12.2 (macOS Tahoe 26.3 arm64)
- csvview.nvim: commit `5c22774` (feat(view): support left and right column spacing, 2026-05-03)
- File: ~216 rows, mixed Korean/ASCII, quoted fields containing commas

## Summary

After running an external filter that replaces buffer content (e.g. `:%!mlr --csv sort -f <col>`), the csvview rendering becomes partial/inconsistent on large files:

- Some rows are rendered with column padding (`│` separators, aligned columns)
- Other rows show raw CSV (commas visible)
- Toggling via `:CsvViewDisable` then `:CsvViewEnable` does not fully restore alignment

On a small reproducer (5 rows), metrics remain correct after `:%!mlr`. The issue manifests on larger files (200+ rows) with complex content (Korean text, long quoted fields).

## Steps to Reproduce

1. Open a CSV with 200+ rows where the longest first-column value appears in the middle of the file (e.g. row 7 of an alphabetically sorted file)
2. Allow csvview to render initial view
3. Run an external filter that replaces buffer content:
   ```
   :%!mlr --csv sort -f category
   ```
4. Observe: rendering becomes inconsistent across rows in the buffer

## Expected

After the buffer change, all visible (and subsequently scrolled-to) rows should be rendered with consistent column widths computed from the global maximum across the entire updated buffer.

## Actual

Subset of rows rendered with one set of column widths, other rows rendered raw or with different widths. `<leader>cv` (CsvViewToggle) re-enable produces the same partial state.

## Root-Cause Hypothesis (from source reading)

Two design points appear to combine into the observed behavior:

### 1. `nvim_buf_attach(bufnr, false, ...)` in `util.buf_attach`

`util.lua` line 159:

```lua
vim.api.nvim_buf_attach(bufnr, false, { on_lines = ..., on_reload = ..., ... })
```

The second argument `false` (`send_buffer`) means the initial buffer contents are **not** sent to `on_lines` on attach. Therefore `M.enable()` registers listeners but has no metrics until subsequent edits.

### 2. `M.enable()` does not call `metrics:compute_buffer()`

`init.lua` `M.enable` creates fresh `parser`, `metrics`, `view` objects and registers `buf_attach`, but never calls `metrics:compute_buffer()`. The only place `compute_buffer` is invoked is in the `on_reload` callback (line 118-132).

As a result:

- On initial file open, metrics accumulate via subsequent `on_lines` and `on_win` (decoration provider) calls — works correctly when the entire file is small enough to fit in the initial render pass.
- After `:%!cmd` on a large buffer, the partial `on_lines` events update metrics incrementally but may not visit every row; rendering of unvisited rows uses partial metrics.

### 3. `View:dispose()` only clears extmarks tracked by `self._extmarks`

`view.lua` `View:clear` iterates only `self._extmarks` — extmarks the current `View` instance recorded via `_add_extmark`. The `csv_extmark` namespace is shared, so any extmarks created from other code paths (or orphaned by enable/disable cycles, sticky_header rendering, inccommand preview restore, etc.) remain in the buffer after `:CsvViewDisable`.

Measured on a 216-row CSV that had been through one mlr sort cycle:

```vim
:lua local ns = vim.api.nvim_create_namespace("csv_extmark"); print(#vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}))
```

Output before disable: thousands. Output after `:CsvViewDisable`: **3650 extmarks still present**. These orphan extmarks render the visual `│` separators / padding on screen even though `is_enabled()` returns `false`, giving the user the impression that csvview is still active.

Suggested fix (one line):

```lua
-- In View:clear or View:dispose, in addition to per-instance cleanup:
vim.api.nvim_buf_clear_namespace(self.bufnr, EXTMARK_NS, 0, -1)
```

User-side workaround we currently apply:

```lua
csvview.disable(bufnr)
vim.api.nvim_buf_clear_namespace(bufnr, vim.api.nvim_create_namespace("csv_extmark"), 0, -1)
vim.cmd("redraw!")
```

## Verification

Headless reproducer with small file shows metrics correct after `:%!mlr`:

```bash
# 5 rows, all visible in default 80x24 window
nvim --headless small.csv -c "lua ..." # col[1].max_width preserved
```

User-side larger file (216 rows): metrics incomplete, mixed render. (Diagnostics available if requested.)

## Suggested Fix

Option A — eager full parse on `enable()`:

```lua
-- In M.enable, after creating metrics:
metrics:compute_buffer(function() ...end)
```

Option B — accept `{ eager = true }` option to opt in to eager parsing on enable, preserving current lazy behavior as default.

Option C — fire a synthetic full-range `on_lines` to the new `buf_attach` registration so the existing incremental path covers the full buffer.

## Related

- This affects any tool that replaces buffer content via `:%!cmd` (mlr, awk, sed, sort, etc.) before users interact with the buffer enough to trigger incremental parsing of all rows.
- Also affects `:CsvViewToggle` (off then on) on large files for the same reason.

## Reproducer Snippet (sanitized)

```bash
# Generate a 250-row CSV with varied first-column widths
python3 -c '
import csv, sys
w = csv.writer(sys.stdout)
w.writerow(["category","id","reason"])
for i in range(250):
    cat = "complex_3_mallCompanyNumber_mallName_mallType" if i == 7 else ("mallCompanyNumber" if i % 3 else "mallType")
    w.writerow([cat, f"T{i}", "한글 메시지 - " + "필드 불일치 " * 5])
' > /tmp/csvbug.csv
nvim /tmp/csvbug.csv
# After buffer loads with csvview rendering:
:%!mlr --csv sort -f category
# Observe partial rendering
```
