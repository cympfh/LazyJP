local M = {}

M.config = {
  cmd = "lazyjp",
  style = "casual",
  languages = { "ja", "en", "zh" },
}

-- pending[bufnr][lnum] = {hash, text}
local pending = {}

local function line_hash(text)
  return vim.fn.sha256(text)
end

local function get_context(bufnr)
  return vim.b[bufnr].lazyjp_context or {}
end

local function push_context(bufnr, text)
  local ctx = vim.b[bufnr].lazyjp_context or {}
  table.insert(ctx, text)
  if #ctx > 2 then
    table.remove(ctx, 1)
  end
  vim.b[bufnr].lazyjp_context = ctx
end

local function cancel_pending(bufnr, lnum)
  if pending[bufnr] then
    pending[bufnr][lnum] = nil
  end
end

local function on_convert_result(bufnr, lnum, original_hash, result_text)
  local p = pending[bufnr] and pending[bufnr][lnum]
  if not p or p.hash ~= original_hash then
    return
  end
  cancel_pending(bufnr, lnum)

  local current = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
  if not current or line_hash(current) ~= original_hash then
    return
  end

  vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { result_text })
  push_context(bufnr, result_text)
end

local function send_to_engine(bufnr, lnum, text)
  local hash = line_hash(text)
  pending[bufnr] = pending[bufnr] or {}
  pending[bufnr][lnum] = { hash = hash, text = text }

  local cmd = {
    M.config.cmd, "convert",
    "--style", M.config.style,
    "--languages", table.concat(M.config.languages, ","),
  }
  for _, ctx in ipairs(get_context(bufnr)) do
    table.insert(cmd, "--context")
    table.insert(cmd, ctx)
  end

  vim.fn.jobstart(cmd, {
    stdin = text,
    stdout_buffered = true,
    on_stdout = function(_, data)
      local result = table.concat(data, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
      if result == "" then return end
      vim.schedule(function()
        on_convert_result(bufnr, lnum, hash, result)
      end)
    end,
    on_stderr = function(_, data)
      local msg = table.concat(data, "")
      if msg ~= "" then
        vim.schedule(function()
          vim.notify("[LazyJP] engine error: " .. msg, vim.log.levels.ERROR)
        end)
      end
    end,
  })
end

function M.trigger()
  local bufnr = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""

  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes("<CR>", true, false, true),
    "n",
    false
  )

  if line ~= "" then
    send_to_engine(bufnr, lnum, line)
  end
end

local function watch_changes(bufnr)
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = bufnr,
    callback = function()
      if not pending[bufnr] then return end
      for lnum, p in pairs(pending[bufnr]) do
        local current = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
        if current == nil or line_hash(current) ~= p.hash then
          cancel_pending(bufnr, lnum)
        end
      end
    end,
  })
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  vim.api.nvim_create_autocmd("BufEnter", {
    callback = function(ev)
      watch_changes(ev.buf)
    end,
  })

  vim.keymap.set("i", "<C-m>", M.trigger, { desc = "LazyJP: convert current line" })
end

return M
