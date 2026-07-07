---@module 'opencode.ui.ask.cmp'

local M = {}

local hl_ns = vim.api.nvim_create_namespace("OpencodeAskHL")

vim.api.nvim_set_hl(0, "OpencodeBackdrop", { default = true, bg = "#000000" })

---@param opts table
---@return Promise<string>
function M.input(opts)
  local Promise = require("opencode.promise")

  return Promise.new(function(resolve, reject)
    local buf = vim.api.nvim_create_buf(false, true)
    local cfg = require("opencode.config")
    local cur_win = vim.api.nvim_get_current_win()
    local saved_view = vim.api.nvim_win_call(cur_win, function()
      return vim.fn.winsaveview()
    end)

    local function close_all(backdrop_buf, backdrop_win, win, buf)
      pcall(vim.cmd, "stopinsert")
      pcall(vim.api.nvim_win_close, backdrop_win, true)
      pcall(vim.api.nvim_buf_delete, backdrop_buf, { force = true })
      pcall(vim.api.nvim_win_close, win, true)
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
      if vim.api.nvim_win_is_valid(cur_win) then
        pcall(vim.api.nvim_win_call, cur_win, function()
          pcall(vim.fn.winrestview, saved_view)
        end)
      end
    end

    if cfg.opts.ask.snacks and cfg.opts.ask.snacks.win and cfg.opts.ask.snacks.win.bo then
      for k, v in pairs(cfg.opts.ask.snacks.win.bo) do
        vim.bo[buf][k] = v
      end
    end
    vim.bo[buf].bufhidden = "wipe"

    if opts.default then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(opts.default, "\n", { plain = true }))
    end

    local row_offset = 1
    local title_pos = "left"

    if cfg.opts.ask.snacks and cfg.opts.ask.snacks.win then
      local w = cfg.opts.ask.snacks.win
      if w.row ~= nil then row_offset = w.row end
      if w.title_pos then title_pos = w.title_pos end
    end

    local count = vim.api.nvim_buf_line_count(buf)
    local float_height = math.max(count, 1) + 1
    local float_width = math.floor(vim.o.columns * 0.6)

    local cursor = vim.api.nvim_win_get_cursor(cur_win)
    local win_pos = vim.api.nvim_win_get_position(cur_win)
    local win_width = vim.api.nvim_win_get_width(cur_win)
    local screen_pos = vim.fn.screenpos(cur_win, cursor[1], cursor[2] + 1)

    local float_col = win_pos[2] + math.max(0, math.floor((win_width - float_width) / 2))
    local total_visual_height = float_height + 2
    local rows_below = vim.fn.line("w$", cur_win) - cursor[1]
    local rows_above = screen_pos.row - 1

    local float_row
    if rows_below >= total_visual_height then
      float_row = (screen_pos.row + 3) + row_offset
    elseif rows_above >= total_visual_height + row_offset then
      -- float_row = screen_pos.row - total_visual_height - row_offset
      float_row = (screen_pos.row - 3) + row_offset
    else
      float_row = (screen_pos.row + 3) + row_offset
    end

    local win_config = {
      relative = "editor",
      row = float_row,
      col = float_col,
      width = float_width,
      style = "minimal",
      border = "rounded",
      title_pos = title_pos,
    }

    local title = (opts.prompt or "Input"):gsub(":?%s*$", "")
    if cfg.opts.ask.snacks and cfg.opts.ask.snacks.icon then
      title = cfg.opts.ask.snacks.icon .. title
    end
    win_config.title = title
    win_config.height = float_height

    local backdrop_buf = vim.api.nvim_create_buf(false, true)
    local backdrop_win = vim.api.nvim_open_win(backdrop_buf, false, {
      relative = "editor",
      width = vim.o.columns,
      height = vim.o.lines,
      row = 0,
      col = 0,
      style = "minimal",
      focusable = false,
      zindex = 48,
      border = "none",
    })
    vim.wo[backdrop_win].winhl = "Normal:OpencodeBackdrop"
    vim.wo[backdrop_win].winblend = 60
    vim.bo[backdrop_buf].buftype = "nofile"
    vim.bo[backdrop_buf].bufhidden = "wipe"

    local win = vim.api.nvim_open_win(buf, true, win_config)
    vim.wo[win].winhighlight = "Normal:NormalFloat"

    local done = false

    local cleanup = function()
      if done then return end
      done = true
      close_all(backdrop_buf, backdrop_win, win, buf)
    end

    vim.api.nvim_create_autocmd("InsertLeave", {
      buffer = buf,
      once = true,
      callback = function()
        if not done then
          done = true
          close_all(backdrop_buf, backdrop_win, win, buf)
          reject()
        end
      end,
    })

    vim.api.nvim_create_autocmd("BufLeave", {
      buffer = buf,
      once = true,
      callback = function()
        if not done then
          done = true
          close_all(backdrop_buf, backdrop_win, win, buf)
          reject()
        end
      end,
    })

    vim.lsp.start(require("opencode.ui.ask.cmp"), { bufnr = buf })

    if opts.context and opts.server then
      local update_hl = function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local text = table.concat(lines, "\n")
        local rendered = opts.context:render(text, opts.server.subagents)
        local extmarks = require("opencode.context").extmarks(rendered.input)
        for _, em in ipairs(extmarks) do
          vim.api.nvim_buf_set_extmark(buf, hl_ns, em.row - 1, em.col, {
            end_col = em.end_col,
            hl_group = em.hl_group,
          })
        end
      end

      vim.api.nvim_create_autocmd("TextChangedI", {
        buffer = buf,
        callback = update_hl,
      })
      vim.schedule(update_hl)
    end

    vim.keymap.set("i", "<CR>", function()
      if done then return end
      done = true
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      if lines[#lines] == "" then
        table.remove(lines)
      end
      local text = table.concat(lines, "\n")
      close_all(backdrop_buf, backdrop_win, win, buf)
      if text == "" then
        reject()
      else
        resolve(text)
      end
    end, { buffer = buf, noremap = true })

    vim.keymap.set("i", "<S-CR>", function()
      if done then return end
      done = true
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      if lines[#lines] == "" then
        table.remove(lines)
      end
      local text = table.concat(lines, "\n") .. "\\n"
      close_all(backdrop_buf, backdrop_win, win, buf)
      resolve(text)
    end, { buffer = buf, noremap = true })

    local line_count = vim.api.nvim_buf_line_count(buf)
    local last_line = vim.api.nvim_buf_get_lines(buf, line_count - 1, -1, false)[1] or ""
    vim.api.nvim_win_set_cursor(win, {line_count, vim.fn.strchars(last_line)})
    vim.cmd("startinsert!")
  end)
end

return M
