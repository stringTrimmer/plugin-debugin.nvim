local api = vim.api
local cmd = vim.cmd
local fn = vim.fn
local common = require 'plugin-debugin.common'
local PLUGIN_NAME = common.PLUGIN_NAME
local PLUGIN_NAME_SHADA = string.upper(PLUGIN_NAME)
local plugin_bufnr
local line_count = 0
local limit_reached = false
local adjusted_win_width
local autocmd_group = common.autocmd_group
local builtin_print = print -- store original print function so it can be restored as needed

---@alias plugin_debugin.window_position 'current' | 'bottom' | 'left' | 'right' | 'top'

---@class plugin_debugin.persisted_settings
---@field position? plugin_debugin.window_position
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
local settings = {
	position = 'bottom',
	also_print_to_messages = false,
	overwrite = false,
	focus_window_on_open = true,
	prepend = true,
	line_limit = 10000,
	copy_msg_history = true,
	separator = '-',
	width = 50,
	height = 20,
	persist = false,
	schedule = false,
}

---@enum (key) plugin_debugin.settings_keys
local settings_keys = {
	position = 'string',
	also_print_to_messages = 'boolean',
	overwrite = 'boolean',
	focus_window_on_open = 'boolean',
	prepend = 'boolean',
	line_limit = 'integer',
	copy_msg_history = 'boolean',
	separator = 'string',
	width = 'integer',
	height = 'integer',
	persist = 'boolean',
	schedule = 'boolean',
}

local function get_schedule_from_session_or_default() return vim.g[PLUGIN_NAME] and vim.g[PLUGIN_NAME] == 'true' end

-- using a vim all-caps global so preferences are persisted in SHADA
if vim.g[PLUGIN_NAME_SHADA] then
	settings = vim.g[PLUGIN_NAME_SHADA]
else
	api.nvim_echo({ { ('init vim_did_enter:%s'):format(vim.v.vim_did_enter), 'WarningMsg' } }, true, {})
	if vim.v.vim_did_enter == 0 then
		api.nvim_create_autocmd('VimEnter', {
			desc = ('Get %s settings from SHADA'):format(PLUGIN_NAME),
			group = common.autocmd_group,
			callback = function()
				api.nvim_echo({ { ('%s VimEnter'):format(PLUGIN_NAME), 'WarningMsg' } }, true, {})
				if vim.g[PLUGIN_NAME_SHADA] then settings = vim.g[PLUGIN_NAME_SHADA] end
			end,
		})
	end
end

if vim.g[PLUGIN_NAME] then
	settings.schedule = get_schedule_from_session_or_default()
else
	api.nvim_create_autocmd('SessionLoadPost', {
		desc = ('Get %s settings from Session'):format(PLUGIN_NAME),
		group = common.autocmd_group,
		callback = function()
			api.nvim_echo({ { 'init SessionLoadPost', 'WarningMsg' } }, true, {})
			settings.schedule = get_schedule_from_session_or_default()
		end,
	})
end

local function is_enabled() return plugin_bufnr and api.nvim_buf_is_loaded(plugin_bufnr) end

---Return a list of window ids; should be just one, but there's nothing strictly
---preventing user from openning another window on the plugin's buffer
---@return integer[]
local function get_windows()
	if is_enabled() then
		local winlist = fn.win_findbuf(plugin_bufnr)
		if #winlist > 0 then return winlist end
	end
	return {}
end

---Put lines in the plugin's buffer either at the beginning if `prepend` or end otherwise or
---replace the buffer if `overwrite`
---@param lines string[]
---@param overwrite boolean
---@param prepend boolean
local function write_to_buf(lines, overwrite, prepend)
	local windows = get_windows()
	api.nvim_buf_set_lines(
		plugin_bufnr,
		(overwrite or prepend) and 0 or -1,
		(prepend and not overwrite) and 0 or -1,
		false,
		lines
	)
	if #windows > 0 then
		for i = 1, #windows, 1 do
			api.nvim_win_set_cursor(windows[i], { prepend and 1 or api.nvim_buf_line_count(plugin_bufnr), 0 })
		end
	end
end

local function paused() end

local write_to_buf_scheduled = vim.schedule_wrap(write_to_buf)

local function print_to_buf(...)
	if settings.also_print_to_messages then builtin_print(...) end

	if limit_reached then return end

	local write_to_buf_fun = settings.schedule and write_to_buf_scheduled or write_to_buf

	if line_count >= settings.line_limit then
		limit_reached = true
		local msg = ('%s line limit reached, no longer printting to buffer'):format(PLUGIN_NAME)
		api.nvim_echo({ { msg, 'WarningMsg' } }, true, {})
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

local function close_all(windows)
	for i = 1, #windows, 1 do
		api.nvim_win_close(windows[i], false)
	end
end

local function get_first_window()
	local windows = get_windows()
	return #windows > 0 and windows[1] or nil
end

local function is_open() return get_first_window() ~= nil end

local M = {}
function M.is_enabled() return is_enabled() end

function M.show_state()
	local state = ('%s State = %s'):format(
		PLUGIN_NAME,
		vim.inspect(vim.tbl_deep_extend('keep', {
			plugin_bufnr = plugin_bufnr,
			line_count = line_count,
			limit_reached = limit_reached,
			pause = print == paused,
		}, settings))
	)
	api.nvim_echo({ { state, 'Type' } }, true, {})
	if is_enabled() then write_to_buf(vim.split(state, '\n'), false, settings.prepend) end
end

function M.save_current_window_size()
	local winid
	if plugin_bufnr == api.nvim_get_current_buf() then
		winid = api.nvim_get_current_win()
	else
		winid = get_first_window()
	end
	if winid then
		settings.width = api.nvim_win_get_width(winid)
		settings.height = api.nvim_win_get_height(winid)
		api.nvim_echo({
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
		api.nvim_echo(
			{ { ('%s not currently open to get the height and width from.'):format(PLUGIN_NAME), 'WarningMsg' } },
			false,
			{}
		)
	end
end

---Change lua `print` to custom function configured by opts and persist opts settings.
local function set_print(should_pause)
	if not is_enabled() then return end
	print = should_pause and paused or print_to_buf
end

local function get_message_history() return vim.split(api.nvim_cmd({ cmd = 'messages' }, { output = true }), '\n') end

local function enable(buf)
	if buf then
		plugin_bufnr = buf
		vim.bo[plugin_bufnr].modified = false
		vim.bo[plugin_bufnr].buftype = 'nofile'
		vim.bo[plugin_bufnr].swapfile = false
	else
		plugin_bufnr = api.nvim_create_buf(false, true)
		api.nvim_buf_set_name(plugin_bufnr, PLUGIN_NAME)
	end
	vim.bo[plugin_bufnr].bufhidden = 'hide'
	vim.bo[plugin_bufnr].filetype = PLUGIN_NAME
	if settings.copy_msg_history then vim.api.nvim_buf_set_lines(plugin_bufnr, 0, 0, false, get_message_history()) end
	set_print()
end

function M.enable()
	if is_enabled() then return end
	enable()
end

function M._reenable(buf)
	enable(buf)
end

function M.copy_message_history() write_to_buf(get_message_history(), settings.overwrite, settings.prepend) end

function M.pause() set_print(true) end

function M.resume() set_print(false) end

function M.prompt_for_line_limit()
	vim.ui.input(
		{ prompt = ('Enter the maximum # of lines %s should print before haulting: '):format(PLUGIN_NAME) },
		function(input)
			if input and input ~= '' and not input:find '%D' then
				settings.line_limit = tonumber(input)
			else
				api.nvim_echo({ { ('%s line limit must be a number'):format(PLUGIN_NAME), 'WarningMsg' } }, true, {})
			end
		end
	)
end

-- TODO: support setting no separator
function M.prompt_for_msg_separator()
	vim.ui.input(
		{ prompt = ('Enter a character for %s to print as a separator between messages: '):format(PLUGIN_NAME) },
		function(input)
			if type(input) == 'string' and fn.strchars(input) == 1 then
				settings.separator = input
			else
				api.nvim_echo(
					{ { ('%s separator must be a single character'):format(PLUGIN_NAME), 'WarningMsg' } },
					true,
					{}
				)
			end
		end
	)
end

function M.close() close_all(get_windows()) end

---Open a window (at given position) on the plugin's buffer to show the what has been logged
---@param position? plugin_debugin.window_position
function M.open(position)
	if not is_enabled() then
		enable()
	else
		local windows = get_windows()
		if #windows > 0 then
			if not position then
				for i = 1, #windows do
					api.nvim_set_current_win(windows[i])
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
		vim.cmd('vertical botright sbuffer ' .. plugin_bufnr)
		wintype = 'vertical'
	elseif position == 'left' then
		vim.cmd('vertical topleft sbuffer ' .. plugin_bufnr)
		wintype = 'vertical'
	elseif position == 'bottom' then
		vim.cmd('botright sbuffer ' .. plugin_bufnr)
		wintype = 'horizontal'
	elseif position == 'top' then
		vim.cmd('topleft sbuffer ' .. plugin_bufnr)
		wintype = 'horizontal'
	else
		cmd.buffer(plugin_bufnr)
		wintype = 'current'
	end
	local winid = api.nvim_get_current_win()
	if wintype == 'vertical' then
		if settings.width then api.nvim_win_resize(winid, settings.width, -1, {}) end
	elseif wintype == 'horizontal' then
		if settings.height then api.nvim_win_resize(winid, -1, settings.height, {}) end
	end
	local wininfo = fn.getwininfo(winid)[1]
	adjusted_win_width = wininfo.width - wininfo.textoff
	if wintype ~= 'current' and not settings.focus_window_on_open then cmd.wincmd 'p' end
	-- capture_resize(winid, wintype)
end

function M.toggle()
	if is_open() then
		M.close()
		vim.cmd 'echo " "'
	else
		M.open()
	end
end

function M.clear()
	if is_enabled() then api.nvim_buf_set_lines(plugin_bufnr, 0, -1, false, {}) end
	line_count = 0
	limit_reached = false
end

function M.disable()
	if is_enabled() then api.nvim_buf_delete(plugin_bufnr, {}) end
	plugin_bufnr = nil
	print = builtin_print
end

function M.change_setting(setting, value)
	vim.validate(
		setting,
		value,
		function() return settings_keys[setting] ~= nil and type(value) == settings_keys[setting] end,
		false -- TODO: should we reset the setting to default if given nil?
	)
	settings[setting] = value
end

api.nvim_create_autocmd('VimLeavePre', {
	desc = ('Persist %s config in shada via all-caps vim global'):format(PLUGIN_NAME),
	group = common.autocmd_group,
	callback = function()
		settings.schedule = nil -- don't persist schedule globally
		vim.g[PLUGIN_NAME_SHADA] = settings
		vim.g[PLUGIN_NAME] = settings.schedule -- but do persist it per session
	end,
})

api.nvim_create_autocmd('FileType', {
	desc = ('Add `q` keymap to close/hide and `backspace` keymap to clear the %s window/buffer'):format(PLUGIN_NAME),
	group = autocmd_group,
	pattern = ('%s'):format(PLUGIN_NAME),
	callback = function()
		vim.keymap.set('n', 'q', function()
			if #vim.api.nvim_list_wins() > 1 then
				vim.api.nvim_win_close(0, false)
			elseif fn.bufloaded(0) ~= 0 then
				api.nvim_feedkeys(api.nvim_replace_termcodes('<C-^>', true, false, true), 'n', false)
			else
				cmd.bnext()
			end
		end, { buffer = true, desc = 'Quit (close window or hide buffer)' })
		vim.keymap.set('n', '<BS>', M.clear, { buffer = true, desc = 'Clear buffer (i.e. delete all lines)' })
	end,
})

api.nvim_create_autocmd('SessionWritePre', {
	desc = ('Set %s per-session settings in session global variable'):format(PLUGIN_NAME),
	group = autocmd_group,
	callback = function()
		api.nvim_echo({ { 'init SessionWritePre', 'WarningMsg' } }, true, {})
		vim.g[PLUGIN_NAME] = tostring(settings.schedule)
	end,
})

-- a.nvim_create_autocmd('VimLeave', {
-- 	group = autocmd_group,
-- 	desc = ('Write %s buffer to a file if `persist` option is true'):format(PLUGIN_NAME),
-- 	callback = function()
-- 		if settings.persist and is_enabled() then
-- 			a.nvim_set_current_buf(plugin_bufnr)
-- 			vim.bo[plugin_bufnr].buftype = ''
-- 			cmd.saveas { vim.fs.normalize(('%s/%s.log'):format(fn.stdpath 'log', PLUGIN_NAME)), bang = true }
-- 		end
-- 	end,
-- })
return M
