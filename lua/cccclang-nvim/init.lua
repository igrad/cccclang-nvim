print("Hello from the plugin!")

local M = {}

-- Use vim.fs to find files in the hierarchy
local function find_upwards(filename, start_dir)
	local result = vim.fs.find(filename, { upward = true, path = start_dir or vim.fn.getcwd() })
	if #result > 0 then
		return result[1]
	end
	return nil
end

-- Function to check if the current directory has a CMakeLists.txt file
local function has_cmakelists()
	return find_upwards("CMakeLists.txt") ~= nil
end

-- Function to check if a .h or .cpp file is open
local function is_cpp_file_open()
	local bufname = vim.fn.bufname()
	return bufname:match("%.h$") or bufname:match("%.cpp$")
end

-- Function to scan the top-most CMakeLists.txt file for CMAKE_EXPORT_COMPILE_COMMANDS
local function scan_cmake_flag()
	local cmake_file = find_upwards("CMakeLists.txt")
	if not cmake_file then
		vim.notify("No CMakeLists.txt file found in the project hierarchy.", vim.log.levels.WARN)
		return
	end

	local flag_found = false
	local flag_set = false

	local content = {}
	for line in io.lines(cmake_file) do
		table.insert(content, line)
		if line:match("CMAKE_EXPORT_COMPILE_COMMANDS") then
			flag_found = true
			local value = line:match("CMAKE_EXPORT_COMPILE_COMMANDS%s*=%s*(%w+)")
			if value == "ON" then
				vim.notify(
					"CMake is already configured to build the compile_commands.json file on next build. Please run CMake now.",
					vim.log.levels.INFO
				)
				return
			elseif value == "OFF" then
				flag_set = false
			end
		end
	end

	if not flag_found or not flag_set then
		vim.ui.select(
			{ "Yes", "No" },
			{
				prompt = "CMake is not currently configured to generate a compile_commands.json file. Would you like to configure it to do so on the next build?",
			},
			function(choice)
				if choice == "Yes" then
					if flag_found then
						for i, line in ipairs(content) do
							content[i] = line:gsub(
								"CMAKE_EXPORT_COMPILE_COMMANDS%s*=%s*OFF",
								"CMAKE_EXPORT_COMPILE_COMMANDS = ON"
							)
						end
					else
						table.insert(content, 1, "set(CMAKE_EXPORT_COMPILE_COMMANDS ON)")
					end

					local f = assert(io.open(cmake_file, "w"))
					f:write(table.concat(content, "\n"))
					f:close()
					vim.notify("Please run CMake now.", vim.log.levels.INFO)
				end
			end
		)
	end
end

-- Function to prompt the user with options
local function prompt_user()
	vim.ui.select(
		{ "Retry", "Create a compile_commands.json", "Ignore" },
		{ prompt = "Compile commands could not be found for this project. What would you like to do?" },
		function(choice)
			if choice == "Retry" then
				M.check_compile_commands()
			elseif choice == "Create a compile_commands.json" then
				scan_cmake_flag()
			elseif choice == "Ignore" then
				-- Silently move on
			end
		end
	)
end

-- Main function to check for compile_commands.json
function M.check_compile_commands()
	if not has_cmakelists() then
		return
	end

	if not is_cpp_file_open() then
		return
	end

	local compile_commands = find_upwards("compile_commands.json")
	if not compile_commands then
		prompt_user()
	end
end

-- Set up a command to run the check
function M.setup()
	vim.api.nvim_create_user_command("CheckCompileCommands", function()
		M.check_compile_commands()
	end, { desc = "Check for compile_commands.json in the project hierarchy" })
end

return M
