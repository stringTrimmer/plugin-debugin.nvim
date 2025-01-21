local a = vim.api
local cmd = vim.cmd
local fn = vim.fn
local PLUGIN_NAME = 'HijackPrint'
local PLUGIN_NAME_UPPER = string.upper(PLUGIN_NAME)
local ORIGINAL_PRINT = PLUGIN_NAME .. '_orig_print'
---@type hijack_print_persisted_settings
local settings
local hijack_bufnr
local line_count = 0
local limit_reached = false
local adjusted_win_width
local schedule = false
local autocmd_group = a.nvim_create_augroup(PLUGIN_NAME, { clear = true })
-- use a global to store original print function incase the module is reloaded we won't lose the reference to it
if not vim.g[ORIGINAL_PRINT] then vim.g[ORIGINAL_PRINT] = print end

---@class hijack_print_persisted_settings
---@field position? 'bottom' | 'left' | 'right' | 'current'
---@field also_print_to_messages? boolean
---@field overwrite? boolean
---@field focus_window_on_open? boolean
---@field prepend? boolean
---@field line_limit? integer
---@field copy_msg_history? boolean
---@field separator? string
---@field width? integer
---@field height? integer
---@field persist? boolean

if vim.g[PLUGIN_NAME_UPPER] then
	settings = vim.g[PLUGIN_NAME_UPPER]
else
	settings = {
		position = 'bottom',
		also_print_to_messages = false,
		overwrite = false,
		focus_window_on_open = true,
		prepend = true,
		line_limit = 10000,
		copy_msg_history = true,
		separator = '-',
		width = 50,
		height = 50,
		persist = false,
	}
	if vim.v.vim_did_enter ~= 1 then
		a.nvim_create_autocmd('VimEnter', {
			desc = 'Get %s settings from SHADA',
			group = autocmd_group,
			callback = function()
				if vim.g[PLUGIN_NAME_UPPER] then settings = vim.g[PLUGIN_NAME_UPPER] end
			end,
		})
	end
end

---Create a scratch buffer with given name, optionally make it wipeable and show it in current window
---@param name string
---@param opts {wipe:boolean, listed:boolean, open:boolean}
---@return number
local function scratch(name, opts)
	opts = vim.tbl_extend('keep', opts or {}, { wipe = false, listed = false, open = true })
	local bufnr = a.nvim_create_buf(opts.listed, true)
	vim.bo[bufnr].bufhidden = opts.wipe and 'wipe' or 'hide'
	a.nvim_buf_set_name(bufnr, name)
	if opts.open then cmd.buffer(bufnr) end
	return bufnr
end

local function is_hijacked() return hijack_bufnr and a.nvim_buf_is_loaded(hijack_bufnr) end

local function find_hijack_win()
	if is_hijacked() then
		local winlist = fn.win_findbuf(hijack_bufnr)
		if #winlist > 0 then return winlist end
	end
	for _, bufinfo in pairs(fn.getbufinfo { bufloaded = 1 }) do
		if bufinfo.name and bufinfo.name:find(PLUGIN_NAME .. '$') then
			hijack_bufnr = bufinfo.bufnr
			return bufinfo.windows
		end
	end
	return {}
end

---Put lines in the plugin's buffer either at the beginning if `prepend` or end otherwise or
---replace the buffer if `overwrite`
---@param lines string[]
---@param overwrite boolean
---@param prepend boolean
local function write_to_buf(lines, overwrite, prepend)
	local windows = find_hijack_win()
	a.nvim_buf_set_lines(
		hijack_bufnr,
		(overwrite or prepend) and 0 or -1,
		(prepend and not overwrite) and 0 or -1,
		false,
		lines
	)
	if #windows > 0 then
		for i = 1, #windows, 1 do
			a.nvim_win_set_cursor(windows[i], { prepend and 1 or a.nvim_buf_line_count(hijack_bufnr), 0 })
		end
	end
end

local function paused() end

local write_to_buf_scheduled = vim.schedule_wrap(write_to_buf)

local function print_to_buf(...)
	if settings.also_print_to_messages then vim.g[ORIGINAL_PRINT](...) end

	if limit_reached then return end

	local write_to_buf_fun = schedule and write_to_buf_scheduled or write_to_buf

	if line_count >= settings.line_limit then
		limit_reached = true
		local msg = ('%s line limit reached, no longer printting to buffer'):format(PLUGIN_NAME)
		a.nvim_echo({ { msg, 'WarningMsg' } }, true, {})
		write_to_buf_fun({ msg }, settings.overwrite, settings.prepend)
		return
	end

	local lines = {}
	for i = 1, select('#', ...) do
		local cur_arg = select(i, ...)
		if type(cur_arg) == 'string' then
			vim.list_extend(lines, vim.split(cur_arg, '\n'))
		else
			vim.list_extend(lines, vim.split(vim.inspect(cur_arg), '\n'))
		end
	end
	if settings.separator then
		vim.list_extend(lines, {
			string.rep(settings.separator, adjusted_win_width and adjusted_win_width or settings.width - 4),
		})
	end
	line_count = line_count + #lines
	write_to_buf_fun(lines, settings.overwrite, settings.prepend)
end

local function show_state()
	local state = ('%s State = %s'):format(
		PLUGIN_NAME,
		vim.inspect(vim.tbl_deep_extend('keep', {
			hijack_bufnr = hijack_bufnr,
			line_count = line_count,
			limit_reached = limit_reached,
			pause = print == paused,
			schedule = schedule,
		}, settings))
	)
	a.nvim_echo({ { state, 'Type' } }, true, {})
	if is_hijacked() then write_to_buf(vim.split(state, '\n'), false, settings.prepend) end
end

local function get_first_window()
	local windows = find_hijack_win()
	return #windows > 0 and windows[1] or nil
end

local function is_open() return get_first_window() ~= nil end

local function save_current_window_size()
	local winid
	if hijack_bufnr == a.nvim_get_current_buf() then
		winid = a.nvim_get_current_win()
	else
		winid = get_first_window()
	end
	if winid then
		settings.width = a.nvim_win_get_width(winid)
		settings.height = a.nvim_win_get_height(winid)
		a.nvim_echo({
			{
				('Saving width: %d and height: %d for next time %s is opened.'):format(
					settings.width,
					settings.height,
					PLUGIN_NAME
				),
				'WarningMsg',
			},
		}, false, {})
	else
		a.nvim_echo(
			{ { ('%s not currently open to get the height and width from.'):format(PLUGIN_NAME), 'WarningMsg' } },
			false,
			{}
		)
	end
end
---Change lua `print` to custom function configured by opts and persist opts settings.
local function set_print(should_pause)
	if not is_hijacked() then return end
	print = should_pause and paused or print_to_buf
end

local function get_message_history() return vim.split(fn.execute 'messages', '\n') end

local function hijack()
	hijack_bufnr = scratch(PLUGIN_NAME, { wipe = false, listed = false, open = false })
	vim.bo[hijack_bufnr].filetype = PLUGIN_NAME
	if settings.copy_msg_history then vim.api.nvim_buf_set_lines(hijack_bufnr, 0, 0, false, get_message_history()) end
	set_print()
end

local function copy_message_history() write_to_buf(get_message_history(), settings.overwrite, settings.prepend) end

local function close_all(windows)
	for i = 1, #windows, 1 do
		a.nvim_win_close(windows[i], false)
	end
end

local function pause()
	set_print(true)
end

local function resume()
	set_print(false)
end

local function switch_to_prepend(prepend) settings.prepend = prepend end

local function set_line_limit()
	vim.ui.input(
		{ prompt = ('Enter the maximum # of lines %s should print before haulting: '):format(PLUGIN_NAME) },
		function(input)
			if input and input ~= '' and not input:find '%D' then
				settings.line_limit = tonumber(input)
			else
				a.nvim_echo({ { ('%s line limit must be a number'):format(PLUGIN_NAME), 'WarningMsg' } }, true, {})
			end
		end
	)
end

local function set_separator()
	vim.ui.input(
		{ prompt = ('Enter a character for %s to print as a separator between messages: '):format(PLUGIN_NAME) },
		function(input)
			if type(input) == 'string' and fn.strchars(input) == 1 then
				settings.separator = input
			else
				a.nvim_echo(
					{ { ('%s separator must be a single character'):format(PLUGIN_NAME), 'WarningMsg' } },
					true,
					{}
				)
			end
		end
	)
end

local function close() close_all(find_hijack_win()) end

local function open(position)
	if not is_hijacked() then
		hijack()
	else
		local windows = find_hijack_win()
		if #windows > 0 then
			if not position then
				for i = 1, #windows do
					a.nvim_set_current_win(windows[i])
					return
				end
			else
				close_all(windows)
			end
		end
	end
	position = position or settings.position
	settings.position = position
	local wintype
	if position == 'right' then
		vim.cmd('vertical botright sbuffer ' .. hijack_bufnr)
		wintype = 'vertical'
	elseif position == 'left' then
		vim.cmd('vertical topleft sbuffer ' .. hijack_bufnr)
		wintype = 'vertical'
	elseif position == 'bottom' then
		vim.cmd('botright sbuffer ' .. hijack_bufnr)
		wintype = 'horizontal'
	else
		cmd.buffer(hijack_bufnr)
		wintype = 'current'
	end
	local winid = a.nvim_get_current_win()
	if wintype == 'vertical' then
		if settings.width then a.nvim_win_set_width(winid, settings.width) end
	elseif wintype == 'horizontal' then
		if settings.height then a.nvim_win_set_width(winid, settings.height) end
	end
	local wininfo = fn.getwininfo(winid)[1]
	---@diagnostic disable-next-line: undefined-field
	adjusted_win_width = wininfo.width - wininfo.textoff
	if wintype ~= 'current' and not settings.focus_window_on_open then cmd.wincmd 'p' end
	-- capture_resize(winid, wintype)
end

local function toggle()
	if is_open() then
		close()
		vim.cmd 'echo " "'
	else
		open()
	end
end

local function clear()
	if is_hijacked() then a.nvim_buf_set_lines(hijack_bufnr, 0, -1, false, {}) end
	line_count = 0
	limit_reached = false
end

local function revert()
	if is_hijacked() then a.nvim_buf_delete(hijack_bufnr, {}) end
	hijack_bufnr = nil
	print = vim.g[ORIGINAL_PRINT]
end

local function get_subcommands()
	return {
		'c - clear',
		'o - open',
		'q - quit/close',
		't - toggle',
		print == paused and 'r - resume' or 'p - pause',
		is_hijacked() and 'disable plugin' or 'enable plugin',
		'enter message separator character',
		'focus window on open?',
		'get message history',
		'include existing message history on initial open?',
		'overwrite?',
		'prepend?',
		-- 'persist?',
		'print to :messages also?',
		'save current window size',
		'set line limit',
		'schedule all prints to avoid textlock errors?',
		'show state',
	}
end

a.nvim_create_user_command(PLUGIN_NAME, function(info)
	if #info.fargs == 0 then
		open()
	elseif info.fargs[1] == 'enable plugin' then
		hijack()
	elseif info.fargs[1] == 'disable plugin' then
		revert()
	elseif info.fargs[1] == 't - toggle' or info.fargs[1] == 't' or info.fargs[1] == 'toggle' then
		toggle()
	elseif info.fargs[1] == 'c - clear' or info.fargs[1] == 'c' or info.fargs[1] == 'clear' then
		clear()
	elseif info.fargs[1] == 'o - open' or info.fargs[1] == 'o' or info.fargs[1] == 'open' then
		open(info.fargs[2])
	elseif
		info.fargs[1] == 'q - quit/close'
		or info.fargs[1] == 'q'
		or info.fargs[1] == 'close'
		or info.fargs[1] == 'quit'
	then
		close()
	elseif info.fargs[1] == 'p - pause' or info.fargs[1] == 'p' or info.fargs[1] == 'pause' then
		pause()
	elseif info.fargs[1] == 'r - resume' or info.fargs[1] == 'r' or info.fargs[1] == 'resume' then
		resume()
	elseif info.fargs[1] == 'also print to messages?' then
		settings.also_print_to_messages = (info.fargs[2] == 'yes')
	elseif info.fargs[1] == 'overwrite?' then
		settings.overwrite = (info.fargs[2] == 'yes')
	elseif info.fargs[1] == 'schedule all prints to avoid textlock errors?' then
		schedule = info.fargs[2] == 'yes'
	elseif info.fargs[1] == 'save current window size' then
		save_current_window_size()
	elseif info.fargs[1] == 'focus window on open?' then
		settings.focus_window_on_open = (info.fargs[2] == 'yes')
	elseif info.fargs[1] == 'persist?' then
		settings.persist = (info.fargs[2] == 'yes')
	elseif info.fargs[1] == 'include existing message history on initial open?' then
		settings.copy_msg_history = (info.fargs[2] == 'yes')
	elseif info.fargs[1] == 'set line limit' then
		set_line_limit()
	elseif info.fargs[1] == 'enter message separator character' then
		set_separator()
	elseif info.fargs[1] == 'prepend?' then
		switch_to_prepend(info.fargs[2] == 'yes')
	elseif info.fargs[1] == 'show state' then
		show_state()
	elseif info.fargs[1] == 'get message history' then
		copy_message_history()
	end
end, {
	desc = 'Make `print` output to a regular buffer.',
	nargs = '*',
	complete = function(_, cmd_line, _)
		local args_so_far = vim.split(cmd_line, '%s+', { trimempty = true })
		if #args_so_far == 1 then return get_subcommands() end
		if args_so_far[2] == 'o - open' or args_so_far[2] == 'o' or args_so_far[2] == 'open' then
			return { 'current', 'right', 'bottom', 'left' }
		end
		if
			args_so_far[2] == 'print to :messages also?'
			or args_so_far[2] == 'overwrite?'
			or args_so_far[2] == 'prepend?'
			or args_so_far[2] == 'focus window on open?'
			or args_so_far[2] == 'include existing message history on initial open?'
			or args_so_far[2] == 'persist?'
			or args_so_far[2] == 'schedule all prints to avoid textlock errors?'
		then
			return { 'yes', 'no' }
		end
	end,
})

a.nvim_create_autocmd('VimLeavePre', {
	desc = ('Persist %s config in shada via all-caps vim global'):format(PLUGIN_NAME),
	group = autocmd_group,
	callback = function() vim.g[PLUGIN_NAME_UPPER] = settings end,
})

a.nvim_create_autocmd('FileType', {
	desc = ('Add `q` keymap to close/hide and `backspace` keymap to clear the %s window/buffer'):format(PLUGIN_NAME),
	group = autocmd_group,
	pattern = ('%s'):format(PLUGIN_NAME),
	callback = function()
		vim.keymap.set('n', 'q', function()
			if #vim.api.nvim_list_wins() > 1 then
				vim.api.nvim_win_close(0, false)
			elseif fn.bufloaded(0) ~= 0 then
				a.nvim_feedkeys(a.nvim_replace_termcodes('<C-^>', true, false, true), 'n', false)
			else
				cmd.bnext()
			end
		end, { buffer = true, desc = 'Quit (close window or hide buffer)' })
		vim.keymap.set('n', '<BS>', clear, { buffer = true, desc = 'Clear buffer (i.e. delete all lines)' })
	end,
})

-- a.nvim_create_autocmd('VimLeave', {
-- 	group = autocmd_group,
-- 	desc = ('Write %s buffer to a file if `persist` option is true'):format(PLUGIN_NAME),
-- 	callback = function()
-- 		if settings.persist and is_hijacked() then
-- 			a.nvim_set_current_buf(hijack_bufnr)
-- 			vim.bo[hijack_bufnr].buftype = ''
-- 			cmd.saveas { vim.fs.normalize(('%s/%s.log'):format(fn.stdpath 'log', PLUGIN_NAME)), bang = true }
-- 		end
-- 	end,
-- })
