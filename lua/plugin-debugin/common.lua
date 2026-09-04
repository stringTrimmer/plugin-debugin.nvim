local PLUGIN_NAME = 'PluginDebugin'
local autocmd_group = vim.api.nvim_create_augroup(PLUGIN_NAME, { clear = true })

M = { PLUGIN_NAME = PLUGIN_NAME, autocmd_group = autocmd_group }
return M
