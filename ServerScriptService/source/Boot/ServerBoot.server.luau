local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.shared.Packages
local Promise = require(Packages.Promise)

local ServicesRoot = script.Parent.Parent.Services

local BOOT_ORDER = {
	"PlayerDataService",
}

local function loadService(module: ModuleScript): any?
	local ok, result = pcall(require, module)
	if not ok then
		warn(`Failed to load {module.Name}: {result}`)
		return nil
	end
	if type(result) ~= "table" then
		return nil
	end
	return result
end

local function initService(service: any, name: string): typeof(Promise.new(function() end))
	if type(service.init) ~= "function" then
		return Promise.resolve()
	end
	return Promise.try(function()
		service:init()
	end):catch(function(err)
		warn(`{name} failed to initialize: {err}`)
	end)
end

local function boot()
	local orderedServices: { { name: string, service: any } } = {}
	local unorderedServices: { { name: string, service: any } } = {}
	local loadedNames: { [string]: boolean } = {}

	for _, priorityName in BOOT_ORDER do
		local module = ServicesRoot:FindFirstChild(priorityName)
		if not module then
			warn(`Priority service "{priorityName}" not found.`)
			continue
		end
		local service = loadService(module)
		if service then
			table.insert(orderedServices, { name = priorityName, service = service })
			loadedNames[priorityName] = true
		end
	end

	for _, child in ServicesRoot:GetChildren() do
		if child:IsA("ModuleScript") and not loadedNames[child.Name] then
			loadedNames[child.Name] = true
			local service = loadService(child)
			if service then
				table.insert(unorderedServices, { name = child.Name, service = service })
			end
		end
	end

	Promise.each(orderedServices, function(entry)
		return initService(entry.service, entry.name)
	end):andThen(function()
		return Promise.each(unorderedServices, function(entry)
			return initService(entry.service, entry.name)
		end)
	end):catch(function(err)
		warn(`Boot critical failure: {err}`)
	end)
end

game:BindToClose(function()
	local module = ServicesRoot:FindFirstChild("PlayerDataService")
	if not module then return end

	local ok, PlayerDataService = pcall(require, module)
	if not ok or type(PlayerDataService) ~= "table" then return end

	for _, player in Players:GetPlayers() do
		local profile = PlayerDataService:getProfile(player)
		if profile and profile:IsActive() then
			profile:EndSession()
		end
	end
end)

boot()
