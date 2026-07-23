-- Credit: Discord: dropy_dev_47097 | Roblox: AXCOP4
-- Connected Discord-GitHub

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

-- world config n ore drop rates
local CONFIG = {
	WORLD_SIZE = 40,
	BLOCK_SIZE = 4,
	SEA_LEVEL = 4,
	MOUNTAIN_HEIGHT = 12,
	NOISE_SCALE_TERRAIN = 26,
	NOISE_SCALE_CAVE = 14,
	CAVE_THRESHOLD = 0.42,
	TREE_CHANCE = 0.02,
	ORE_CHANCES = {
		Diamond = 0.02,
		Iron = 0.06,
		Coal = 0.12,
	}
}

-- remotes n asset folders
local event = ReplicatedStorage:WaitForChild("GenerateWorld")
local blocksFolder = ReplicatedStorage:WaitForChild("Blocks")
local assetsFolder = ReplicatedStorage:WaitForChild("ModelsAssets")

-- templates tbl
local templates = {
	Grass = blocksFolder:WaitForChild("Grass"),
	Dirt = blocksFolder:WaitForChild("Dirt"),
	Stone = blocksFolder:WaitForChild("Stone"),
	Water = blocksFolder:WaitForChild("Water"),
	Sand = blocksFolder:WaitForChild("Sand"),
	Bedrock = blocksFolder:WaitForChild("Bedrock"),
	CoalOre = blocksFolder:WaitForChild("Coalore"),
	IronOre = blocksFolder:WaitForChild("Ironore"),
	DiamondOre = blocksFolder:WaitForChild("Diamond"),
}

local treeTemplate = assetsFolder:WaitForChild("MinecraftTree")

-- main generator class
local TerrainGenerator = {}
TerrainGenerator.__index = TerrainGenerator

function TerrainGenerator.new(customSeed)
	local self = setmetatable({}, TerrainGenerator)
	self.Seed = customSeed or Random.new():NextInteger(1, 999999)
	self.Random = Random.new(self.Seed)
	self.WorldFolder = nil
	self.TerrainFolder = nil
	self.FloraFolder = nil
	self.WorldGrid = {}
	self.IsGenerating = false
	self.TotalBlocksSpawned = 0
	return self
end

-- calculates height w/ 2 noise layers
function TerrainGenerator:CalculateHeight(x, z)
	local baseNoise = math.noise(x / CONFIG.NOISE_SCALE_TERRAIN, z / CONFIG.NOISE_SCALE_TERRAIN, self.Seed / 10000) * 6
	local detailNoise = math.noise(x / 12, z / 12, self.Seed / 5000) * 2.5
	local combined = 6 + baseNoise + detailNoise
	return math.clamp(math.floor(combined), 2, CONFIG.MOUNTAIN_HEIGHT)
end

-- checks if point is a cave hollow
function TerrainGenerator:IsCaveCell(x, y, z)
	if y <= 1 then return false end
	local caveNoise = math.noise(
		x / CONFIG.NOISE_SCALE_CAVE, 
		y / CONFIG.NOISE_SCALE_CAVE, 
		(z + self.Seed) / CONFIG.NOISE_SCALE_CAVE
	)
	return caveNoise > CONFIG.CAVE_THRESHOLD
end

-- picks ore type based on y level n RNG
function TerrainGenerator:DetermineOreType(y)
	local roll = self.Random:NextNumber()
	if y <= 3 and roll < CONFIG.ORE_CHANCES.Diamond then
		return "DiamondOre"
	elseif y <= 5 and roll < CONFIG.ORE_CHANCES.Iron then
		return "IronOre"
	elseif y <= 8 and roll < CONFIG.ORE_CHANCES.Coal then
		return "CoalOre"
	end
	return "Stone"
end

-- cleans up old map n sets up folders
function TerrainGenerator:InitializeFolders()
	local oldWorld = Workspace:FindFirstChild("GeneratedWorld")
	if oldWorld then 
		oldWorld:Destroy() 
	end

	local worldFolder = Instance.new("Folder")
	worldFolder.Name = "GeneratedWorld"
	worldFolder:SetAttribute("Seed", self.Seed)

	local terrainFolder = Instance.new("Folder")
	terrainFolder.Name = "Terrain"
	terrainFolder.Parent = worldFolder

	local floraFolder = Instance.new("Folder")
	floraFolder.Name = "Flora"
	floraFolder.Parent = worldFolder

	self.WorldFolder = worldFolder
	self.TerrainFolder = terrainFolder
	self.FloraFolder = floraFolder
end

-- builds grid in memory first so we dont lag
function TerrainGenerator:BuildWorldMatrix()
	self.WorldGrid = {}

	for gridX = 0, CONFIG.WORLD_SIZE - 1 do
		self.WorldGrid[gridX] = {}
		for gridZ = 0, CONFIG.WORLD_SIZE - 1 do
			self.WorldGrid[gridX][gridZ] = {}
			local height = self:CalculateHeight(gridX, gridZ)

			-- map base
			self.WorldGrid[gridX][gridZ][0] = "Bedrock"

			-- stone n ores layers
			for y = 1, height - 2 do
				if not self:IsCaveCell(gridX, y, gridZ) then
					self.WorldGrid[gridX][gridZ][y] = self:DetermineOreType(y)
				end
			end

			-- dirt layer
			if height - 1 > 0 then
				self.WorldGrid[gridX][gridZ][height - 1] = "Dirt"
			end

			-- top block stuff
			local topBlock = "Grass"
			if height <= CONFIG.SEA_LEVEL + 1 then
				topBlock = "Sand"
			end
			self.WorldGrid[gridX][gridZ][height] = topBlock

			-- water fill below sea lvl
			if height < CONFIG.SEA_LEVEL then
				for waterY = height + 1, CONFIG.SEA_LEVEL do
					self.WorldGrid[gridX][gridZ][waterY] = "Water"
				end
			end
		end
	end
end

-- tree spawner w/ random y rot
function TerrainGenerator:PlantTree(posX, groundY, posZ)
	if not self.FloraFolder then return end

	local tree = treeTemplate:Clone()
	for _, part in ipairs(tree:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	local boxCFrame, boxSize = tree:GetBoundingBox()
	local bottomToPivot = tree:GetPivot().Position.Y - (boxCFrame.Position.Y - boxSize.Y / 2)
	local targetPivot = Vector3.new(posX, (groundY + 1) * CONFIG.BLOCK_SIZE + bottomToPivot, posZ)
	local randomRotation = math.rad(self.Random:NextInteger(0, 3) * 90)

	tree:PivotTo(CFrame.new(targetPivot) * CFrame.Angles(0, randomRotation, 0))
	tree.Parent = self.FloraFolder
end

-- clones blocks n fills buffers for bulk move
function TerrainGenerator:InstantiateTerrain()
	local partsBuffer = {}
	local cframesBuffer = {}
	local halfSize = (CONFIG.WORLD_SIZE - 1) / 2
	self.TotalBlocksSpawned = 0

	for gridX = 0, CONFIG.WORLD_SIZE - 1 do
		for gridZ = 0, CONFIG.WORLD_SIZE - 1 do
			local posX = math.floor((gridX - halfSize) * CONFIG.BLOCK_SIZE)
			local posZ = math.floor((gridZ - halfSize) * CONFIG.BLOCK_SIZE)

			for y, blockType in pairs(self.WorldGrid[gridX][gridZ]) do
				local template = templates[blockType] or templates.Stone
				local block = template:Clone()
				block.Anchored = true

				local posY = math.floor(y * CONFIG.BLOCK_SIZE + (CONFIG.BLOCK_SIZE / 2))
				local targetCFrame = CFrame.new(posX, posY, posZ)

				table.insert(partsBuffer, block)
				table.insert(cframesBuffer, targetCFrame)

				if self.TerrainFolder then
					block.Parent = self.TerrainFolder
				end

				self.TotalBlocksSpawned = self.TotalBlocksSpawned + 1

				-- tree chance on grass
				if blockType == "Grass" and y > CONFIG.SEA_LEVEL + 1 then
					if self.Random:NextNumber() < CONFIG.TREE_CHANCE then
						self:PlantTree(posX, y, posZ)
					end
				end
			end
		end

		-- yield every 5 loops so server doesnt freeze
		if gridX % 5 == 0 then
			task.wait()
		end
	end

	return partsBuffer, cframesBuffer
end

-- main runner method
function TerrainGenerator:Generate()
	if self.IsGenerating then 
		return false 
	end

	self.IsGenerating = true
	self:InitializeFolders()
	self:BuildWorldMatrix()

	local partsBuffer, cframesBuffer = self:InstantiateTerrain()

	-- move everything at once bc performance
	Workspace:BulkMoveTo(partsBuffer, cframesBuffer, Enum.BulkMoveMode.FireCFrameChanged)

	if self.WorldFolder then
		self.WorldFolder.Parent = Workspace
		self.WorldFolder:SetAttribute("TotalBlocks", self.TotalBlocksSpawned)
	end

	self.IsGenerating = false
	return true
end

local activeGenerator = nil

-- main server listener
local function HandleWorldGenerationRequest(player)
	if activeGenerator and activeGenerator.IsGenerating then
		event:FireClient(player, "Busy")
		return
	end

	event:FireAllClients("Started")

	task.spawn(function()
		local generator = TerrainGenerator.new()
		activeGenerator = generator

		local startTime = os.clock()
		local success, err = pcall(function()
			return generator:Generate()
		end)

		local elapsedTime = math.floor((os.clock() - startTime) * 1000) / 1000

		if success then
			print("[WorldGenerator]: Chunk generated in " .. tostring(elapsedTime) .. "s. Total blocks: " .. tostring(generator.TotalBlocksSpawned))
			event:FireAllClients("Finished", generator.Seed, generator.TotalBlocksSpawned)
		else
			if activeGenerator then
				activeGenerator.IsGenerating = false
			end
			warn("[WorldGenerator Error]: " .. tostring(err))
			event:FireAllClients("Error", err)
		end
	end)
end

event.OnServerEvent:Connect(HandleWorldGenerationRequest)
