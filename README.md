# NuNvim

NuNvim is a lightweight unit test runner that executes tests based on the current cursor position. When the cursor is placed on a method, it runs that specific test; when positioned on a class, it runs all tests within that class.

It supports both `xUnit` and `NUnit` console runners and works on both Windows and Linux.

## Installation

### lazy.nvim:
```lua
{
    "Irdis/NuNvim",
    config = function()
        require("nunvim").setup(config)
        vim.keymap.set('n', '<Leader>ur', ':lua require("nunvim").run_debug({ run_outside = true })<CR>')
        vim.keymap.set('n', '<Leader>ua', ':lua require("nunvim").run_debug({ run_all = true, run_outside = true })<CR>')
    end
}
```
