local nunvim = {}

nunvim.nunitconsole = "nunit3-console"
nunvim.configuration = "Debug"

nunvim.setup = function(config) 
    if not config then
        return
    end

    if config.nunitconsole then 
        nunvim.nunitconsole = config.nunitconsole
    end
end

nunvim.run_release = function()
    nunvim.run("Release")
end

nunvim.run_debug = function()
    nunvim.run("Debug")
end

nunvim.run = function(configuration)
    nunvim.buf = vim.api.nvim_get_current_buf()
    nunvim.cursor_row = nunvim.get_cursor_row()
    if configuration then 
        nunvim.configuration = configuration
    end
    nunvim.nunitconsole = "c:\\Distr\\NUnit.Console-3.19.0\\bin\\net462\\nunit3-console"

    local location = nunvim.get_location()
    if not location.success then
        nunvim.log("Missing a testable thing (class/method) under the cursor")
        return
    end

    local file_path = vim.api.nvim_buf_get_name(nunvim.buf)
    local root_folder = vim.loop.cwd()
    local csproj = nunvim.get_csproj(file_path, root_folder)
    if not csproj then 
        nunvim.log("Unable to locate .csproj")
        return
    end

    local dll = nunvim.get_dll(csproj, nunvim.configuration)
    if not dll then 
        nunvim.log("Unable to locate .dll")
        return
    end

    local cmd = nunvim.build_cmd(location, nunvim.nunitconsole, dll)
    vim.cmd(cmd)
end

nunvim.log = function(msg)
    print("[nunvim] " .. msg)
end

nunvim.build_cmd = function(location, nunit_path, dll_path)
    local cmd = "!" .. nunit_path

    cmd = cmd .. " " .. dll_path
    cmd = cmd .. " " .. nunvim.build_cmd_location(location)
    cmd = cmd .. " " .. "--noh"
    cmd = cmd .. " " .. "--noresult"
    cmd = cmd .. " " .. "--labels=BeforeAndAfter"

    return cmd
end

nunvim.build_cmd_location = function(location)
    local cmd = "--test="
    cmd = cmd .. location.namespace
    cmd = cmd .. "." .. location.class
    if location.method then 
        cmd = cmd .. "." .. location.method
    end
    return cmd
end

nunvim.get_cursor_row = function()
    local row = unpack(vim.api.nvim_win_get_cursor(0))
    return row - 1
end

nunvim.get_dll = function(csproj, configuration)
    local csproj_folder = vim.fn.fnamemodify(csproj, ":h")
    local csproj_name_noext = vim.fn.fnamemodify(csproj, ":t:r")
    local dll_name = csproj_name_noext .. ".dll"
    local initial_folder = csproj_folder .. "\\bin\\" .. configuration
    local dll_path = nunvim.look_for_dll(dll_name, initial_folder)

    return dll_path
end

nunvim.look_for_dll = function(dll_name, directory)
    return nunvim.look_for_dll_int(string.lower(dll_name), directory)
end

nunvim.look_for_dll_int = function(dll_name, directory)
    local dir = vim.loop.fs_scandir(directory)
    if not dir then
        nunvim.log("Unable to access: " .. directory)
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
        local found = nunvim.look_for_dll_int(dll_name, inner_dir)
        if found then 
            return found
        end
    end
    return nil
end


nunvim.get_csproj = function(location, root)
    local directory = vim.fn.fnamemodify(location, ":h")

    if directory == location then
        nunvim.log("Unable to locate .csproj")
        return nil
    end

    local dir = vim.loop.fs_scandir(directory)
    if not dir then
        nunvim.log("Unable to access: " .. directory)
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
        nunvim.log("Unable to locate .csproj")
        return nil
    end
    return nunvim.get_csproj(directory, root)
end

nunvim.get_location = function()
    local parser = vim.treesitter.get_parser(buf, "c_sharp")
    local tree = parser:parse()[1]
    local root = tree:root()

    local location_info = {
        complete = false,
        success = false
    }
    nunvim.traverse_root(root, location_info)

    return location_info
end

nunvim.traverse_root = function(node, info)
    if node:type() == "file_scoped_namespace_declaration" then 
        info.namespace = nunvim.get_identifier(node, "name")
        info.file_scoped_namespace = true
    elseif node:type() == "namespace_declaration" then
        local start_row, _, end_row, _ = node:range()
        if nunvim.cursor_row < start_row or nunvim.cursor_row > end_row then
            return
        end

        info.namespace = nunvim.get_identifier(node, "name")
        info.file_scoped_namespace = false

        nunvim.traverse_namespace(node, info)
    else 
        for child in node:iter_children() do
            nunvim.traverse_root(child, info)
            if info.complete then 
                return 
            end

            if info.file_scoped_namespace then
                nunvim.traverse_namespace(node, info)
            end
        end
    end
end

nunvim.traverse_namespace = function(node, info)
    if node:type() == "class_declaration" then
        local start_row, _, end_row, _ = node:range()
        if nunvim.cursor_row < start_row or nunvim.cursor_row > end_row then
            return
        end
        local identifier_row
        info.class, identifier_row = nunvim.get_identifier(node, "name")
        if nunvim.cursor_row == identifier_row then
            info.complete = true
            info.success = true
            return
        end
        nunvim.traverse_class(node, info)
        info.complete = true
    else 
        for child in node:iter_children() do
            nunvim.traverse_namespace(child, info)
            if info.complete then 
                return 
            end
        end
    end
end

nunvim.traverse_class = function(node, info)
    if node:type() == "method_declaration" then
        local start_row, _, end_row, _ = node:range()
        if nunvim.cursor_row < start_row or nunvim.cursor_row > end_row then
            return
        end
        if nunvim.has_test_attributes(node) then 
            info.method = nunvim.get_identifier(node, "name")
            info.success = true
        end
        info.complete = true
    else 
        for child in node:iter_children() do
            nunvim.traverse_class(child, info)
            if info.complete then 
                return 
            end
        end
    end
end

nunvim.has_test_attributes = function(node)
    for attr_lst in node:iter_children() do
        if attr_lst:type() == "attribute_list" then
            for attr in attr_lst:iter_children() do
                local identifier = nunvim.get_identifier(attr, "name")
                if identifier == "Test" or identifier == "TestCase" then 
                    return true
                end
            end
        end
    end
    return false
end

nunvim.get_identifier = function(node, node_name)
    for child, child_name in node:iter_children() do
        if node_name == child_name then
            local start_row = child:range()
            return vim.treesitter.get_node_text(child, nunvim.buf), start_row
        end
    end
    return nil
end


nunvim.reload = function()
    package.loaded["nunvim"] = nil
end

return nunvim
