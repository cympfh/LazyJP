local M = {}

local _plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

M.config = {
  cmd = { "python", _plugin_dir .. "/engine/main.py" },
  style = "casual",
  languages = { "ja", "en", "zh" },
  verbose = false,
  keymap = "<C-j>",
  num_contexts = 2,
  reasoning_effort = nil,
}

-- pending[bufnr][hash] = count
local pending = {}

-- log entries
local logs = {}

-- lazyjp mode active buffers
local mode_bufs = {}

local function log_append(msg)
  local ts = os.date("%H:%M:%S")
  table.insert(logs, string.format("[%s] %s", ts, msg))
end

local function line_hash(text)
  return vim.fn.sha256(text)
end

local function get_context(bufnr)
  return vim.b[bufnr].lazyjp_context or {}
end

local function push_context(bufnr, text)
  local ctx = vim.b[bufnr].lazyjp_context or {}
  table.insert(ctx, text)
  if #ctx > M.config.num_contexts then
    table.remove(ctx, 1)
  end
  vim.b[bufnr].lazyjp_context = ctx
end

local function cancel_pending(bufnr, hash)
  if pending[bufnr] then
    local cnt = pending[bufnr][hash]
    if cnt and cnt > 1 then
      pending[bufnr][hash] = cnt - 1
    else
      pending[bufnr][hash] = nil
    end
  end
end

local function on_convert_result(bufnr, original_text, original_hash, result_text)
  if not (pending[bufnr] and pending[bufnr][original_hash]) then
    log_append(string.format("cancel (not pending): %s", original_text))
    return
  end
  cancel_pending(bufnr, original_hash)

  local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(all_lines) do
    if line == original_text then
      vim.api.nvim_buf_set_lines(bufnr, i - 1, i, false, { result_text })
      push_context(bufnr, result_text)
      log_append(string.format("converted lnum=%d => %s", i, result_text))
      return
    end
  end
  log_append(string.format("cancel (line not found): %s", original_text))
end

local function send_to_engine(bufnr, text)
  local hash = line_hash(text)
  pending[bufnr] = pending[bufnr] or {}
  pending[bufnr][hash] = (pending[bufnr][hash] or 0) + 1
  log_append(string.format("request: %s", text))

  local cmd = {}
  for _, v in ipairs(M.config.cmd) do
    table.insert(cmd, v)
  end
  table.insert(cmd, "convert")
  table.insert(cmd, "--style")
  table.insert(cmd, M.config.style)
  table.insert(cmd, "--languages")
  table.insert(cmd, table.concat(M.config.languages, ","))
  if M.config.verbose then
    table.insert(cmd, "--verbose")
  end
  if M.config.reasoning_effort then
    table.insert(cmd, "--reasoning-effort")
    table.insert(cmd, M.config.reasoning_effort)
  end
  for _, ctx in ipairs(get_context(bufnr)) do
    table.insert(cmd, "--context")
    table.insert(cmd, ctx)
  end

  local job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      local result = table.concat(data, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
      if result == "" then return end
      vim.schedule(function()
        on_convert_result(bufnr, text, hash, result)
      end)
    end,
    on_stderr = function(_, data)
      local msg = table.concat(data, "")
      if msg ~= "" then
        vim.schedule(function()
          log_append(string.format("engine error: %s", msg))
          vim.notify("[LazyJP] engine error: " .. msg, vim.log.levels.ERROR)
        end)
      end
    end,
  })
  vim.fn.chansend(job_id, text .. "\n")
  vim.fn.chanclose(job_id, "stdin")
end

function M.trigger()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lnum = cursor[1]
  local col = cursor[2]  -- 0-indexed byte offset
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""

  if col >= #line then
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes("<CR>", true, false, true),
      "n",
      false
    )
  else
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes("<Down>", true, false, true),
      "n",
      false
    )
  end

  if line ~= "" then
    send_to_engine(bufnr, line)
  end
end


function M.info()
  local lines = vim.list_extend({ "LazyJP log:" }, logs)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local width = math.min(math.max(60, vim.o.columns - 10), vim.o.columns - 4)
  local height = math.min(#lines + 1, vim.o.lines - 6)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " LazyJP Info ",
    title_pos = "center",
  })
  vim.wo[win].wrap = false
  vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf, silent = true })
end

function M.start(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if mode_bufs[bufnr] then return end
  mode_bufs[bufnr] = true
  vim.keymap.set("i", "<CR>", M.trigger, { buffer = bufnr, desc = "LazyJP: convert on Enter" })
  log_append(string.format("mode started buf=%d", bufnr))
  vim.notify("[LazyJP] mode started", vim.log.levels.INFO)
end

function M.stop(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not mode_bufs[bufnr] then return end
  mode_bufs[bufnr] = nil
  pcall(vim.keymap.del, "i", "<CR>", { buffer = bufnr })
  log_append(string.format("mode stopped buf=%d", bufnr))
  vim.notify("[LazyJP] mode stopped", vim.log.levels.INFO)
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  vim.keymap.set("i", M.config.keymap, M.trigger, { desc = "LazyJP: convert current line" })
  vim.api.nvim_create_user_command("LazyJpInfo", function() M.info() end, { desc = "LazyJP: show log" })
  vim.api.nvim_create_user_command("LazyJpStart", function() M.start() end, { desc = "LazyJP: start persistent mode" })
  vim.api.nvim_create_user_command("LazyJpStop", function() M.stop() end, { desc = "LazyJP: stop persistent mode" })
end

return M
