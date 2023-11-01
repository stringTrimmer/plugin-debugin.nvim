--TODO: when plugin-debugin is only window, can't close it, so try going to alt file or next buf instead
--TODO: `open` left (or right) should take up all vertical space I think
local a = vim.api
-- a.nvim_echo({ { 'hijack_print required', 'WarningMsg' } }, true, {})
local PLUGIN_NAME = 'HijackPrint'
if not vim.g.hijack_print_orig_print then vim.g.hijack_print_orig_print = print end
if not vim.g.HIJACKPRINT_SETTINGS then
	vim.g.HIJACKPRINT_SETTINGS = {
		position = 'bottom',
		also_print_to_messages = false,
		overwrite = false,
		focus_window_on_open = true,
		prepend = true,
		line_limit = 10000,
		copy_msg_history = true,
	}
end

local hijack_bufnr
local line_count = 0
local limit_reached = false

---Reference: :help lua-vim-variables
---@param key any
---@param value any
local function set_global_dictionary_item(key, value)
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
	if opts.open then vim.cmd.buffer(bufnr) end
	return bufnr
end

local function hijacked() return hijack_bufnr and a.nvim_buf_is_loaded(hijack_bufnr) end

local function find_hijack_buf()
	local hibufinfo
	if hijacked() then
		local buflist = vim.fn.getbufinfo(hijack_bufnr)
		if #buflist == 1 then hibufinfo = buflist[1] end
	end
	if not hibufinfo then
		for _, bufinfo in pairs(vim.fn.getbufinfo { bufloaded = 1 }) do
			if bufinfo.name and bufinfo.name:find(PLUGIN_NAME .. '$') then
				hijack_bufnr = bufinfo.bufnr
				hibufinfo = bufinfo
				break
			end
		end
	end
	return hibufinfo
end

local function write_to_buf(lines, overwrite, prepend)
	vim.schedule(function()
		local bufinfo = find_hijack_buf()
		a.nvim_buf_set_lines(
			hijack_bufnr,
			(overwrite or prepend) and 0 or -1,
			(prepend and not overwrite) and 0 or -1,
			false,
			lines
		)
		if bufinfo and bufinfo.windows then
			for i = 1, #bufinfo.windows, 1 do
				a.nvim_win_set_cursor(bufinfo.windows[i], { prepend and 1 or a.nvim_buf_line_count(hijack_bufnr), 0 })
			end
		end
	end)
end

local function paused() end

local _print = function(both, overwrite, prepend, pause)
	if pause then return paused end

	return function(...)
		if both then vim.g.hijack_print_orig_print(...) end
		if limit_reached then return end
		if not limit_reached and line_count >= vim.g.HIJACKPRINT_SETTINGS.line_limit then
			limit_reached = true
			local msg = ('%s LINE LIMIT REACHED, NO LONGER PRINTTING TO BUFFER'):format(string.upper(PLUGIN_NAME))
			a.nvim_echo({ { msg, 'WarningMsg' } }, true, {})
			write_to_buf({ msg }, overwrite, prepend)
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
			-- a.nvim_echo({ { 'split: ' .. vim.split(vim.inspect(select(i, ...)), '\n')[1], 'WarningMsg' } }, true, {})
			-- vim.list_extend(lines, {vim.inspect(select(i, ...))})
			-- table.insert(lines, vim.inspect(select(i, ...)))
		end
		line_count = line_count + #lines
		write_to_buf(lines, overwrite, prepend)
		-- DEBUG
		-- vim.g.hijack_print_orig_print(unpack(lines))
		-- a.nvim_echo({ { 'last_line: ' .. last_line, 'WarningMsg' } }, true, {})
	end
end

-- local function capture_resize(winid, wintype)
-- 	vim.api.nvim_create_autocmd('WinResized', {
-- 		group = vim.api.nvim_create_augroup(HIJACKPRINT .. '_resize', { clear = true }),
-- 		desc = 'Capture the HIJACKPRINT window size so it can be used when reopenning',
-- 		pattern = tostring(winid),
-- 		-- once = true,
-- 		callback = function(ctx)
-- 			vim.print('WinResized', ctx)
-- 			if wintype == 'vertical' then
-- 				set_vim_dictionary_item('width', a.nvim_win_get_width(winid))
-- 			elseif wintype == 'horizontal' then
-- 				set_vim_dictionary_item('height', a.nvim_win_get_height(winid))
-- 			end
-- 		end,
-- 	})
-- end

local function show_state()
	local state = ('%s State = %s'):format(
		PLUGIN_NAME,
		vim.inspect(
			vim.tbl_deep_extend(
				'keep',
				{ hijack_bufnr = hijack_bufnr, line_count = line_count, limit_reached = limit_reached },
				vim.g.HIJACKPRINT_SETTINGS
			)
		)
	)
	a.nvim_echo({ { state, 'Type' } }, true, {})
	write_to_buf(vim.split(state, '\n'), false, vim.g.HIJACKPRINT_SETTINGS.prepend)
end

local function get_first_window()
	local winid
	local bufinfo = find_hijack_buf()
	if bufinfo and bufinfo.windows and #bufinfo.windows > 0 then winid = bufinfo.windows[1] end
	return winid
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

local function set_print(opts)
	opts = vim.tbl_extend('keep', opts or {}, {
		also_print_to_messages = vim.g.HIJACKPRINT_SETTINGS.also_print_to_messages,
		overwrite = vim.g.HIJACKPRINT_SETTINGS.overwrite,
		prepend = vim.g.HIJACKPRINT_SETTINGS.prepend,
	})
	-- pause should not be persisted
	local pause = opts.pause or false
	opts.pause = nil
	vim.g.HIJACKPRINT_SETTINGS = vim.tbl_extend('keep', opts, vim.g.HIJACKPRINT_SETTINGS)
	if hijacked() then print = _print(opts.also_print_to_messages, opts.overwrite, opts.prepend, pause) end
end

local function hijack()
	hijack_bufnr = scratch(PLUGIN_NAME, { wipe = false, listed = false, open = false })
	vim.bo[hijack_bufnr].filetype = PLUGIN_NAME
	if vim.g.HIJACKPRINT_SETTINGS.copy_msg_history then
		local messages = vim.split(vim.fn.execute 'messages', '\n')
		vim.api.nvim_buf_set_lines(hijack_bufnr, 0, 0, false, messages)
	end
	set_print()
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

local function close()
	local bufinfo = find_hijack_buf()
	if bufinfo and bufinfo.windows then close_all(bufinfo.windows) end
end

local function open(position)
	local bufinfo = find_hijack_buf()
	if not bufinfo then
		hijack()
	elseif bufinfo.windows then
		if not position then
			for i = 1, #bufinfo.windows, 1 do
				a.nvim_set_current_win(bufinfo.windows[i])
				return
			end
		else
			close_all(bufinfo.windows)
		end
	end
	position = position or vim.g.HIJACKPRINT_SETTINGS.position

	set_global_dictionary_item('position', position)
	local wintype
	if position == 'right' then
		vim.cmd('vertical rightbelow sbuffer ' .. hijack_bufnr)
		wintype = 'vertical'
	elseif position == 'left' then
		vim.cmd('vertical leftabove sbuffer ' .. hijack_bufnr)
		wintype = 'vertical'
	elseif position == 'bottom' then
		vim.cmd('botright sbuffer ' .. hijack_bufnr)
		wintype = 'horizontal'
	else
		vim.cmd.buffer(hijack_bufnr)
		wintype = 'current'
	end
	local winid = a.nvim_get_current_win()
	if wintype == 'vertical' then
		if vim.g.HIJACKPRINT_SETTINGS.width then a.nvim_win_set_width(winid, vim.g.HIJACKPRINT_SETTINGS.width) end
	elseif wintype == 'horizontal' then
		if vim.g.HIJACKPRINT_SETTINGS.height then a.nvim_win_set_width(winid, vim.g.HIJACKPRINT_SETTINGS.height) end
	end
	if wintype ~= 'current' and not vim.g.HIJACKPRINT_SETTINGS.focus_window_on_open then vim.cmd.wincmd 'p' end
	-- capture_resize(winid, wintype)
end

local function toggle()
	if is_open() then
		close()
		vim.cmd('echo " "')
	else
		open()
	end
end

local function clear()
	if hijacked() then a.nvim_buf_set_lines(hijack_bufnr, 0, -1, false, {}) end
	line_count = 0
	limit_reached = false
end

local function revert()
	if hijacked() then a.nvim_buf_delete(hijack_bufnr, {}) end
	hijack_bufnr = nil
	print = vim.g.hijack_print_orig_print
end

a.nvim_create_user_command(PLUGIN_NAME, function(info)
	if #info.fargs == 0 then
		open()
	elseif info.fargs[1] == 'revert' then
		revert()
	elseif info.fargs[1] == 't - toggle' or info.fargs[1] == 't' or info.fargs[1] == 'toggle' then
		toggle()
	elseif info.fargs[1] == 'c - clear' or info.fargs[1] == 'c' or info.fargs[1] == 'clear' then
		clear()
	elseif info.fargs[1] == 'o - open' or info.fargs[1] == 'o' or info.fargs[1] == 'open' then
		open(info.fargs[2])
	elseif info.fargs[1] == 'q - close/quit' or info.fargs[1] == 'q' or info.fargs[1] == 'close' or info.fargs[1] == 'quit' then
		close()
	elseif info.fargs[1] == 'p - pause' or info.fargs[1] == 'p' or info.fargs[1] == 'pause' then
		pause()
	elseif info.fargs[1] == 'r - resume' or info.fargs[1] == 'r' or info.fargs[1] == 'resume' then
		resume()
	elseif info.fargs[1] == 'also print to messages?' then
		set_print { also_print_to_messages = info.fargs[2] == 'yes' }
	elseif info.fargs[1] == 'overwrite?' then
		set_print { overwrite = info.fargs[2] == 'yes' }
	elseif info.fargs[1] == 'save current window size' then
		save_current_window_size()
	elseif info.fargs[1] == 'focus window on open?' then
		set_global_dictionary_item('focus_window_on_open', info.fargs[2] == 'yes')
	elseif info.fargs[1] == 'include existing message history on initial open?' then
		set_global_dictionary_item('copy_msg_history', info.fargs[2] == 'yes')
	elseif info.fargs[1] == 'set line limit' then
		set_line_limit()
	elseif info.fargs[1] == 'prepend?' then
		switch_to_prepend(info.fargs[2] == 'yes')
	elseif info.fargs[1] == 'show state' then
		show_state()
	end
end, {
	nargs = '*',
	complete = function(_, cmd_line, _)
		-- DEBUG
		-- a.nvim_echo(
		-- 	{ { ('arg_lead: %s'):format(arg_lead), 'Comment' }, { ('cmd_line: %s'):format(cmd_line), 'Comment' } },
		-- 	true,
		-- 	{}
		-- )
		local args_so_far = vim.split(cmd_line, ' ', { plain = true, trimempty = true })
		if #args_so_far == 1 then
			return {
				't - toggle',
				'o - open',
				'c - clear',
				'x - close',
				print == paused and 'r - resume' or 'p - pause',
				'revert',
				'overwrite?',
				'prepend?',
				'also print to messages?',
				'save current window size',
				'focus window on open?',
				'include existing message history on initial open?',
				'set line limit',
				'show state',
			}
		elseif #args_so_far == 2 then
			if args_so_far[2] == 'open' or args_so_far[2] == 'o' then
				return { 'current', 'right', 'bottom', 'left' }
			elseif
				args_so_far[2] == 'also print to messages?'
				or args_so_far[2] == 'overwrite?'
				or args_so_far[2] == 'prepend?'
				or args_so_far[2] == 'focus window on open?'
				or args_so_far[2] == 'include existing message history on initial open?'
			then
				return { 'yes', 'no' }
			end
		end
	end,
	desc = 'Make `print` output to a regular buffer.',
})
a.nvim_create_autocmd('FileType', {
	group = a.nvim_create_augroup(PLUGIN_NAME, { clear = true }),
	desc = ('Add `q` keymap to close/hide and `backspace` keymap to clear the %s window/buffer'):format(PLUGIN_NAME),
	pattern = ('%s'):format(PLUGIN_NAME),
	callback = function()
		vim.keymap.set('n', 'q', function()
			if #vim.api.nvim_list_wins() > 1 then
				vim.api.nvim_win_close(0, false)
			elseif vim.fn.bufloaded(0) ~= 0 then
				a.nvim_feedkeys(a.nvim_replace_termcodes('<C-^>', true, false, true), 'n', false)
			else
				vim.cmd.bnext()
			end
		end, { buffer = true, desc = 'Quit (close or hide window or buffer)' })
		vim.keymap.set('n', '<BS>', clear, { buffer = true, desc = 'Clear buffer (i.e. delete all lines)' })
	end,
})
