local M = {}

M.nunitconsole = "nunit3-console"

M.setup = function(config)
    if not config then
        return
    end

    if config.nunitconsole then
        M.nunitconsole = config.nunitconsole
    end
end

M.run_release = function(options)
    M.run("Release", options)
end

M.run_debug = function(options)
    M.run("Debug", options)
end

M.run = function(configuration, options)
    if not options then
        options = {}
    end

    M.buf = vim.api.nvim_get_current_buf()
    M.cursor_row = M.get_cursor_row()

    local location
    if not options.run_all then
        location = M.get_location(M.buf)

        if not location.success then
            M.log("Missing a testable thing (class/method) under the cursor")
            return
        end
    end

    local file_path = vim.api.nvim_buf_get_name(M.buf)
    local root_folder = vim.loop.cwd()
    local csproj = M.get_csproj(file_path, root_folder)
    if not csproj then
        M.log("Unable to locate .csproj")
        return
    end

    local dll = M.get_dll(csproj, configuration)
    if not dll then
        M.log("Unable to locate .dll")
        return
    end

    local cmd = M.build_cmd(location, M.nunitconsole, dll, options.run_all)
    if options.run_outside then
        M.run_in_term(cmd)
    else
        M.run_in_message(cmd)
    end
end

M.log = function(msg)
    print("[nunvim] " .. msg)
end

M.run_in_term = function(cmd)
    local b = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_set_current_buf(b)
    local ch = vim.fn.termopen('cmd');
    vim.api.nvim_chan_send(ch, cmd .. '\r')
end

M.run_in_message = function(cmd)
    vim.cmd("!" .. cmd)
end

M.build_cmd = function(location, nunit_path, dll_path, run_all)
    local cmd = nunit_path

    cmd = cmd .. " " .. dll_path
    if not run_all then
        cmd = cmd .. " " .. M.build_cmd_location(location)
    end
    cmd = cmd .. " " .. "--noh"
    cmd = cmd .. " " .. "--noresult"
    cmd = cmd .. " " .. "--labels=BeforeAndAfter"

    return cmd
end

M.build_cmd_location = function(location)
    local cmd = "--test="
    cmd = cmd .. location.namespace
    cmd = cmd .. "." .. location.class
    if location.method then
        cmd = cmd .. "." .. location.method
    end
    return cmd
end

M.get_cursor_row = function()
    local row = table.unpack(vim.api.nvim_win_get_cursor(0))
    return row - 1
end

M.get_dll = function(csproj, configuration)
    local csproj_folder = vim.fn.fnamemodify(csproj, ":h")
    local csproj_name_noext = vim.fn.fnamemodify(csproj, ":t:r")
    local dll_name = csproj_name_noext .. ".dll"
    local initial_folder = csproj_folder .. "\\bin\\" .. configuration
    local dll_path = M.look_for_dll(dll_name, initial_folder)

    return dll_path
end

M.look_for_dll = function(dll_name, directory)
    return M.look_for_dll_int(string.lower(dll_name), directory)
end

M.look_for_dll_int = function(dll_name, directory)
    local dir = vim.loop.fs_scandir(directory)
    if not dir then
        M.log("Unable to access: " .. directory)
        return nil
    end

    local inner_dirs = {}
    while true do
        local name, type = vim.loop.fs_scandir_next(dir)

        if not name then break end

        if type == "file" and string.lower(name) == dll_name then
            return directory .. "\\" .. name
        elseif type == "directory" then
            table.insert(inner_dirs, directory .. "\\" .. name)
        end
    end

    for _, inner_dir in ipairs(inner_dirs) do
        local found = M.look_for_dll_int(dll_name, inner_dir)
        if found then
            return found
        end
    end
    return nil
end


M.get_csproj = function(location, root)
    local directory = vim.fn.fnamemodify(location, ":h")

    if directory == location then
        M.log("Unable to locate .csproj")
        return nil
    end

    local dir = vim.loop.fs_scandir(directory)
    if not dir then
        M.log("Unable to access: " .. directory)
        return nil
    end
    while true do
        local name, type = vim.loop.fs_scandir_next(dir)

        if not name then break end

        if type == "file" and string.match(name, "%.csproj$") then
            return directory .. "\\" .. name
        end
    end
    if directory == root then
        M.log("Unable to locate .csproj")
        return nil
    end
    return M.get_csproj(directory, root)
end

M.get_location = function(buf)
    local parser = vim.treesitter.get_parser(buf, "c_sharp")
    local tree = parser:parse()[1]
    local root = tree:root()

    local location_info = {
        complete = false,
        success = false
    }
    M.traverse_root(root, location_info)

    return location_info
end

M.traverse_root = function(node, info)
    if node:type() == "file_scoped_namespace_declaration" then
        info.namespace = M.get_identifier(node, "name")
        info.file_scoped_namespace = true
    elseif node:type() == "namespace_declaration" then
        local start_row, _, end_row, _ = node:range()
        if M.cursor_row < start_row or M.cursor_row > end_row then
            return
        end

        info.namespace = M.get_identifier(node, "name")
        info.file_scoped_namespace = false

        M.traverse_namespace(node, info)
    else
        for child in node:iter_children() do
            M.traverse_root(child, info)
            if info.complete then
                return
            end

            if info.file_scoped_namespace then
                M.traverse_namespace(node, info)
            end
        end
    end
end

M.traverse_namespace = function(node, info)
    if node:type() == "class_declaration" then
        local start_row, _, end_row, _ = node:range()
        if M.cursor_row < start_row or M.cursor_row > end_row then
            return
        end
        local identifier_row
        info.class, identifier_row = M.get_identifier(node, "name")
        if M.cursor_row == identifier_row then
            info.complete = true
            info.success = true
            return
        end
        M.traverse_class(node, info)
        info.complete = true
    else
        for child in node:iter_children() do
            M.traverse_namespace(child, info)
            if info.complete then
                return
            end
        end
    end
end

M.traverse_class = function(node, info)
    if node:type() == "method_declaration" then
        local start_row, _, end_row, _ = node:range()
        if M.cursor_row < start_row or M.cursor_row > end_row then
            return
        end
        if M.has_test_attributes(node) then
            info.method = M.get_identifier(node, "name")
            info.success = true
        end
        info.complete = true
    else
        for child in node:iter_children() do
            M.traverse_class(child, info)
            if info.complete then
                return
            end
        end
    end
end

M.has_test_attributes = function(node)
    for attr_lst in node:iter_children() do
        if attr_lst:type() == "attribute_list" then
            for attr in attr_lst:iter_children() do
                local identifier = M.get_identifier(attr, "name")
                if identifier == "Test" or identifier == "TestCase" then
                    return true
                end
            end
        end
    end
    return false
end

M.get_identifier = function(node, node_name)
    for child, child_name in node:iter_children() do
        if node_name == child_name then
            local start_row = child:range()
            return vim.treesitter.get_node_text(child, M.buf), start_row
        end
    end
    return nil
end


M.reload = function()
    package.loaded["nunvim"] = nil
end

return M
