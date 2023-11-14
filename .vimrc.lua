local dap = require("dap")
local overseer = require("overseer")
local vim = vim

local TEST_BINARY = "./zig-cache/test"

local debug_test_config = vim.dap.setup_c_configuration(TEST_BINARY)

overseer.register_template {
    -- Required fields
    name = "Run tests",
    builder = function(params)
        -- This must return an overseer.TaskDefinition
        return {
            -- cmd is the only required field
            cmd = { "zig" },
            -- additional arguments for the cmd
            args = { "test", "test.zig", "-femit-bin=" .. TEST_BINARY },
            -- the name of the task (defaults to the cmd of the task)
            name = "Run tests",
            -- set the working directory for the task
        }
    end,
    -- Optional fields
    desc = "Run zig test",
    -- Tags can be used in overseer.run_template()
    tags = {  },
    params = {
        -- See :help overseer-params
    },
    -- Determines sort order when choosing tasks. Lower comes first.
    priority = 50,
    -- Add requirements for this template. If they are not met, the template will not be visible.
    -- All fields are optional.
}

vim.api.nvim_create_user_command("DebugTests", function()
    dap.run(debug_test_config)
end, {})


--vim.keymap.set('n', '<F5>', function()
--dap.run(debug_config)
--dap.repl.open()
--end)
