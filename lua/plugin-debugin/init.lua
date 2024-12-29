local a = vim.api
local cmd = vim.cmd
local fn = vim.fn
local PLUGIN_NAME = 'HijackPrint'
local hijack_bufnr
local line_count = 0
local limit_reached = false
local adjusted_win_width
local is_paused = false
local schedule = false

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
---@field persist? boolean

---@class hijack_print_settings : hijack_print_persisted_settings
---@field pause? boolean
---@field schedule? boolean

if not vim.g.hijack_print_orig_print then vim.g.hijack_print_orig_print = print end
if not vim.g.HIJACKPRINT_SETTINGS then
	---@type hijack_print_persisted_settings
	vim.g.HIJACKPRINT_SETTINGS = {
		position = 'bottom',
		also_print_to_messages = false,
		overwrite = false,
		focus_window_on_open = true,
		prepend = true,
		line_limit = 10000,
		copy_msg_history = true,
		separator = '-',
		width = 10,
		persist = false,
	}
end

---@param key any
---@param value any
local function set_global_dictionary_item(key, value)
	---Reference: :help lua-vim-variables
	local tmp = vim.g.HIJACKPRINT_SETTINGS
	tmp[key] = value
	vim.g.HIJACKPRINT_SETTINGS = tmp
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

--- Return a function for printing customized by opts
---@param opts hijack_print_settings
---@return function
local get_print = function(opts)
	if opts.pause then return paused end
	local write_to_buf_fun = opts.schedule and vim.schedule_wrap(write_to_buf) or write_to_buf

	return function(...)
		if opts.also_print_to_messages then vim.g.hijack_print_orig_print(...) end
		if limit_reached then return end
		if not limit_reached and line_count >= opts.line_limit then
			limit_reached = true
			local msg = ('%s LINE LIMIT REACHED, NO LONGER PRINTTING TO BUFFER'):format(string.upper(PLUGIN_NAME))
			a.nvim_echo({ { msg, 'WarningMsg' } }, true, {})
			write_to_buf_fun({ msg }, opts.overwrite, opts.prepend)
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
		if type(opts.separator) == 'string' and opts.separator:len() > 0 then
			vim.list_extend(lines, {
				string.rep(opts.separator, adjusted_win_width and adjusted_win_width or opts.width - 4),
			})
		end
		line_count = line_count + #lines
		write_to_buf_fun(lines, opts.overwrite, opts.prepend)
	end
end

local function show_state()
	local state = ('%s State = %s'):format(
		PLUGIN_NAME,
		vim.inspect(
			vim.tbl_deep_extend(
				'keep',
				{ hijack_bufnr = hijack_bufnr, line_count = line_count, limit_reached = limit_reached, pause = is_paused, schedule = schedule },
				vim.g.HIJACKPRINT_SETTINGS
			)
		)
	)
	a.nvim_echo({ { state, 'Type' } }, true, {})
	if is_hijacked() then write_to_buf(vim.split(state, '\n'), false, vim.g.HIJACKPRINT_SETTINGS.prepend) end
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
		local width = a.nvim_win_get_width(winid)
		local height = a.nvim_win_get_height(winid)
		set_global_dictionary_item('width', width)
		set_global_dictionary_item('height', height)
		a.nvim_echo({
			{
				('Saving width: %d and height: %d for next time %s is opened.'):format(width, height, PLUGIN_NAME),
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

---Merge given settings into the table stored in a vim global which is saved in SHADA
---@param opts hijack_print_settings
local function merge_settings(opts)
	assert(opts ~= nil)
	opts = vim.tbl_extend('keep', opts, vim.g.HIJACKPRINT_SETTINGS)
	if opts.pause ~= nil then
		is_paused = opts.pause
	end
	if opts.schedule ~= nil then
		schedule = opts.schedule
	end
	-- pause and schedule should not be persisted
	opts.pause = nil
	opts.schedule = nil
	vim.g.HIJACKPRINT_SETTINGS = vim.deepcopy(opts, true)
	opts.pause = is_paused
	opts.schedule = schedule
	return opts
end

---Change lua `print` to custom function configured by opts and persist opts settings.
---@param opts? hijack_print_settings
local function set_print(opts)
	opts = merge_settings(opts or {})
	if not is_hijacked() then return end
	print = get_print(opts)
end

local function get_message_history() return vim.split(fn.execute 'messages', '\n') end

local function hijack()
	hijack_bufnr = scratch(PLUGIN_NAME, { wipe = false, listed = false, open = false })
	vim.bo[hijack_bufnr].filetype = PLUGIN_NAME
	if vim.g.HIJACKPRINT_SETTINGS.copy_msg_history then
		vim.api.nvim_buf_set_lines(hijack_bufnr, 0, 0, false, get_message_history())
	end
	set_print()
end

local function copy_message_history()
	get_print(
		vim.tbl_extend(
			'keep',
			{ also_print_to_messages = false, pause = false, schedule = false },
			vim.g.HIJACKPRINT_SETTINGS
		)
	)(unpack(get_message_history()))
end

local function close_all(windows)
	for i = 1, #windows, 1 do
		a.nvim_win_close(windows[i], false)
	end
end

local function pause()
	if print ~= paused then set_print { pause = true } end
end

local function resume()
	if print == paused then set_print { pause = false } end
end

local function switch_to_prepend(prepend) set_print { prepend = prepend } end

local function set_line_limit()
	vim.ui.input(
		{ prompt = ('Enter the maximum # of lines %s should print before haulting: '):format(PLUGIN_NAME) },
		function(input)
			if input and input ~= '' and not input:find '%D' then
				set_global_dictionary_item('line_limit', tonumber(input))
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
				set_global_dictionary_item('separator', input)
				set_print()
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
	position = position or vim.g.HIJACKPRINT_SETTINGS.position
	set_global_dictionary_item('position', position)
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
		if vim.g.HIJACKPRINT_SETTINGS.width then a.nvim_win_set_width(winid, vim.g.HIJACKPRINT_SETTINGS.width) end
	elseif wintype == 'horizontal' then
		if vim.g.HIJACKPRINT_SETTINGS.height then a.nvim_win_set_width(winid, vim.g.HIJACKPRINT_SETTINGS.height) end
	end
	local wininfo = fn.getwininfo(winid)[1]
	---@diagnostic disable-next-line: undefined-field
	adjusted_win_width = wininfo.width - wininfo.textoff
	if wintype ~= 'current' and not vim.g.HIJACKPRINT_SETTINGS.focus_window_on_open then cmd.wincmd 'p' end
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
	print = vim.g.hijack_print_orig_print
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
		set_print { also_print_to_messages = info.fargs[2] == 'yes' }
	elseif info.fargs[1] == 'overwrite?' then
		set_print { overwrite = info.fargs[2] == 'yes' }
	elseif info.fargs[1] == 'schedule all prints to avoid textlock errors?' then
		set_print { schedule = info.fargs[2] == 'yes' }
	elseif info.fargs[1] == 'save current window size' then
		save_current_window_size()
	elseif info.fargs[1] == 'focus window on open?' then
		set_global_dictionary_item('focus_window_on_open', info.fargs[2] == 'yes')
	elseif info.fargs[1] == 'persist?' then
		set_global_dictionary_item('persist', info.fargs[2] == 'yes')
	elseif info.fargs[1] == 'include existing message history on initial open?' then
		set_global_dictionary_item('copy_msg_history', info.fargs[2] == 'yes')
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
	desc = 'Make `print` output to a regular buffer.',
})

local autocmd_group = a.nvim_create_augroup(PLUGIN_NAME, { clear = true })
a.nvim_create_autocmd('FileType', {
	group = autocmd_group,
	desc = ('Add `q` keymap to close/hide and `backspace` keymap to clear the %s window/buffer'):format(PLUGIN_NAME),
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
		end, { buffer = true, desc = 'Quit (close or hide window or buffer)' })
		vim.keymap.set('n', '<BS>', clear, { buffer = true, desc = 'Clear buffer (i.e. delete all lines)' })
	end,
})

-- a.nvim_create_autocmd('VimLeave', {
-- 	group = autocmd_group,
-- 	desc = ('Write %s buffer to a file if `persist` option is true'):format(PLUGIN_NAME),
-- 	callback = function()
-- 		if vim.g.HIJACKPRINT_SETTINGS.persist and is_hijacked() then
-- 			a.nvim_set_current_buf(hijack_bufnr)
-- 			vim.bo[hijack_bufnr].buftype = ''
-- 			cmd.saveas { vim.fs.normalize(('%s/%s.log'):format(fn.stdpath 'log', PLUGIN_NAME)), bang = true }
-- 		end
-- 	end,
-- })
