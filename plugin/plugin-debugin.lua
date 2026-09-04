local common = require 'plugin-debugin.common'
local api = vim.api
local fn = vim.fn
local PLUGIN_NAME = common.PLUGIN_NAME

local function get_subcommands(arg_lead, subcmds)
	if not arg_lead or arg_lead:find '^%s*$' then return subcmds end
	return fn.matchfuzzy(subcmds, arg_lead, { matchseq = true })
end

api.nvim_create_user_command(PLUGIN_NAME, function(info)
	local pd = require 'plugin-debugin'

	if #info.fargs == 0 then
		pd.open()
		return
	end
	local arg1 = info.fargs[1]
	if arg1 == 'enable_plugin' then
		pd.enable()
	elseif arg1 == 'disable_plugin' then
		pd.disable()
	elseif arg1 == 't-toggle' or arg1 == 't' or arg1 == 'toggle' then
		pd.toggle()
	elseif arg1 == 'c-clear' or arg1 == 'c' or arg1 == 'clear' then
		pd.clear()
	elseif arg1 == 'o-open' or arg1 == 'o' or arg1 == 'open' then
		pd.open(info.fargs[2])
	elseif arg1 == 'q-quit/close' or arg1 == 'q' or arg1 == 'close' or arg1 == 'quit' then
		pd.close()
	elseif arg1 == 'p-pause' or arg1 == 'p' or arg1 == 'pause' then
		pd.pause()
	elseif arg1 == 'r-resume' or arg1 == 'r' or arg1 == 'resume' then
		pd.resume()
	elseif arg1 == 'also_print_to_messages?' then
		pd.change_setting('also_print_to_messages', info.fargs[2] == 'yes')
	elseif arg1 == 'overwrite?' then
		pd.change_setting('overwrite', info.fargs[2] == 'yes')
	elseif arg1 == 'schedule_all_prints_to_avoid_textlock_errors?' then
		pd.change_setting('schedule', info.fargs[2] == 'yes')
	elseif arg1 == 'save_current_window_size' then
		pd.save_current_window_size()
	elseif arg1 == 'focus_window_on_open?' then
		pd.change_setting('focus_window_on_open', info.fargs[2] == 'yes')
		-- elseif arg1 == 'persist?' then
		-- 	settings.persist = (info.fargs[2] == 'yes')
	elseif arg1 == 'include_existing_message_history_on_initial_open?' then
		pd.change_setting('copy_msg_history', info.fargs[2] == 'yes')
	elseif arg1 == 'set_line_limit' then
		pd.prompt_for_line_limit()
	elseif arg1 == 'set_message_separator_character' then
		pd.prompt_for_msg_separator()
	elseif arg1 == 'prepend?' then
		pd.change_setting('prepend', info.fargs[2] == 'yes')
	elseif arg1 == 'show_state' then
		pd.show_state()
	elseif arg1 == 'get_message_history' then
		pd.copy_message_history()
	end
end, {
	desc = 'Make `print` output to a regular buffer.',
	nargs = '*',
	complete = function(arg_lead, cmd_line, _)
		local args_so_far = vim.split(cmd_line, '%s+', { trimempty = false })

		if #args_so_far < 3 then
			local pd = require 'plugin-debugin'
			return get_subcommands(arg_lead, {
				'c-clear',
				'o-open',
				'q-quit/close',
				't-toggle',
				print == pd.paused and 'r-resume' or 'p-pause',
				pd.is_enabled() and 'disable_plugin' or 'enable_plugin',
				'set_message_separator_character',
				'focus_window_on_open?',
				'get_message_history',
				'include_existing_message_history_on_initial_open?',
				'overwrite?',
				'prepend?',
				-- 'persist?',
				'print_to_:messages_also?',
				'save_current_window_size',
				'set_line_limit',
				'schedule_all_prints_to_avoid_textlock_errors?',
				'show_state',
			})
		end

		if args_so_far[2] == 'o-open' or args_so_far[2] == 'o' or args_so_far[2] == 'open' then
			return get_subcommands(arg_lead, { 'current', 'right', 'bottom', 'left', 'top' })
		end
		if
			args_so_far[2] == 'print_to_:messages_also?'
			or args_so_far[2] == 'overwrite?'
			or args_so_far[2] == 'prepend?'
			or args_so_far[2] == 'focus_window_on_open?'
			or args_so_far[2] == 'include_existing_message_history_on_initial_open?'
			-- or args_so_far[2] == 'persist?'
			or args_so_far[2] == 'schedule_all_prints_to_avoid_textlock_errors?'
		then
			return get_subcommands(arg_lead, { 'yes', 'no' })
		end
	end,
})

local function find_buf()
	for _, bufinfo in pairs(fn.getbufinfo { bufloaded = 1 }) do
		if bufinfo.name and bufinfo.name:find(PLUGIN_NAME .. '$') then return bufinfo end
	end
end

-- re-enable on `:restart`
if vim.v.startreason:find('restart', 1, true) then
	api.nvim_create_autocmd({ 'SessionLoadPost' }, {
		group = common.autocmd_group,
		once = true,
		desc = ('%s: Re-enable if plugin was in use before a `:restart`'):format(PLUGIN_NAME),
		callback = function()
			local buf = find_buf()
			if buf then require('plugin-debugin')._reenable(buf.bufnr) end
		end,
	})
end
