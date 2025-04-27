return {
	"okuuva/auto-save.nvim",
	version = "^1.0.0",
	cmd = "ASToggle",
	event = { "InsertLeave", "TextChanged" },
	opts = {
		enabled = true,
		trigger_events = {
			immediate_save = { "FocusLost" },
			defer_save = {},
			cancel_deferred_save = {},
		},

		condition = nil,
		write_all_buffers = false,
		noautocmd = false,
		lockmarks = false,
		debounce_delay = 1000,

		debug = false,
	},
}
