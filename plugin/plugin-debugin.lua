local a = vim.api
local PLUGIN_NAME = 'PluginDebugin'

local function get_subcommands()
	local pd = require("plugin-debugin")
	return {
		"c - clear",
		"o - open",
		"q - quit/close",
		"t - toggle",
		print == pd.paused and "r - resume" or "p - pause",
		pd.is_enabled() and "disable plugin" or "enable plugin",
		"set message separator character",
		"focus window on open?",
		"get message history",
		"include existing message history on initial open?",
		"overwrite?",
		"prepend?",
		-- 'persist?',
		"print to :messages also?",
		"save current window size",
		"set line limit",
		"schedule all prints to avoid textlock errors?",
		"show state",
	}
end

a.nvim_create_user_command(PLUGIN_NAME, function(info)
	local pd = require("plugin-debugin")
	if #info.fargs == 0 then
		pd.open()
	elseif info.fargs[1] == "enable plugin" then
		pd.enable()
	elseif info.fargs[1] == "disable plugin" then
		pd.disable()
	elseif info.fargs[1] == "t - toggle" or info.fargs[1] == "t" or info.fargs[1] == "toggle" then
		pd.toggle()
	elseif info.fargs[1] == "c - clear" or info.fargs[1] == "c" or info.fargs[1] == "clear" then
		pd.clear()
	elseif info.fargs[1] == "o - open" or info.fargs[1] == "o" or info.fargs[1] == "open" then
		pd.open(info.fargs[2])
	elseif
		info.fargs[1] == "q - quit/close"
		or info.fargs[1] == "q"
		or info.fargs[1] == "close"
		or info.fargs[1] == "quit"
	then
		pd.close()
	elseif info.fargs[1] == "p - pause" or info.fargs[1] == "p" or info.fargs[1] == "pause" then
		pd.pause()
	elseif info.fargs[1] == "r - resume" or info.fargs[1] == "r" or info.fargs[1] == "resume" then
		pd.resume()
	elseif info.fargs[1] == "also print to messages?" then
		pd.change_setting("also_print_to_messages", info.fargs[2] == "yes")
	elseif info.fargs[1] == "overwrite?" then
		pd.change_setting("overwrite", info.fargs[2] == "yes")
	elseif info.fargs[1] == "schedule all prints to avoid textlock errors?" then
		pd.change_setting("schedule", info.fargs[2] == "yes")
	elseif info.fargs[1] == "save current window size" then
		pd.save_current_window_size()
	elseif info.fargs[1] == "focus window on open?" then
		pd.change_setting("focus_window_on_open", info.fargs[2] == "yes")
		-- elseif info.fargs[1] == 'persist?' then
		-- 	settings.persist = (info.fargs[2] == 'yes')
	elseif info.fargs[1] == "include existing message history on initial open?" then
		pd.change_setting("copy_msg_history", info.fargs[2] == "yes")
	elseif info.fargs[1] == "set line limit" then
		pd.prompt_for_line_limit()
	elseif info.fargs[1] == "set message separator character" then
		pd.prompt_for_msg_separator()
	elseif info.fargs[1] == "prepend?" then
		pd.change_setting("prepend", info.fargs[2] == "yes")
	elseif info.fargs[1] == "show state" then
		pd.show_state()
	elseif info.fargs[1] == "get message history" then
		pd.copy_message_history()
	end
end, {
	desc = "Make `print` output to a regular buffer.",
	nargs = "*",
	complete = function(_, cmd_line, _)
		local args_so_far = vim.split(cmd_line, "%s+", { trimempty = true })
		if #args_so_far == 1 then
			return get_subcommands()
		end
		if args_so_far[2] == "o - open" or args_so_far[2] == "o" or args_so_far[2] == "open" then
			return { "current", "right", "bottom", "left" }
		end
		if
			args_so_far[2] == "print to :messages also?"
			or args_so_far[2] == "overwrite?"
			or args_so_far[2] == "prepend?"
			or args_so_far[2] == "focus window on open?"
			or args_so_far[2] == "include existing message history on initial open?"
			-- or args_so_far[2] == 'persist?'
			or args_so_far[2] == "schedule all prints to avoid textlock errors?"
		then
			return { "yes", "no" }
		end
	end,
})
