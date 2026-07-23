--!strict
-- Credit: Discord: dropy_dev_47097 | Roblox: AXCOP4
-- Connected Discord-GitHub

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

type GenerationConfig = {
	WORLD_SIZE: number,
	BLOCK_SIZE: number,
	SEA_LEVEL: number,
	MOUNTAIN_HEIGHT: number,
	NOISE_SCALE_TERRAIN: number,
	NOISE_SCALE_CAVE: number,
	CAVE_THRESHOLD: number,
	TREE_CHANCE: number,
	ORE_CHANCES: { [string]: number }
}

local CONFIG: GenerationConfig = {
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

local TerrainGenerator = {}
TerrainGenerator.__index = TerrainGenerator

type TerrainGeneratorImpl = {
	Seed: number,
	Random: Random,
	WorldFolder: Folder?,
	TerrainFolder: Folder?,
	FloraFolder: Folder?,
	WorldGrid: { [number]: { [number]: { [number]: string } } },
	IsGenerating: boolean,
	TotalBlocksSpawned: number,
}

export type TerrainGenerator = typeof(setmetatable({} :: TerrainGeneratorImpl, TerrainGenerator))

local event = ReplicatedStorage:WaitForChild("GenerateWorld") :: RemoteEvent
local blocksFolder = ReplicatedStorage:WaitForChild("Blocks") :: Folder
local assetsFolder = ReplicatedStorage:WaitForChild("ModelsAssets") :: Folder

local templates: { [string]: BasePart } = {
	Grass = blocksFolder:WaitForChild("Grass") :: BasePart,
	Dirt = blocksFolder:WaitForChild("Dirt") :: BasePart,
	Stone = blocksFolder:WaitForChild("Stone") :: BasePart,
	Water = blocksFolder:WaitForChild("Water") :: BasePart,
	Sand = blocksFolder:WaitForChild("Sand") :: BasePart,
	Bedrock = blocksFolder:WaitForChild("Bedrock") :: BasePart,
	CoalOre = blocksFolder:WaitForChild("Coalore") :: BasePart,
	IronOre = blocksFolder:WaitForChild("Ironore") :: BasePart,
	DiamondOre = blocksFolder:WaitForChild("Diamond") :: BasePart,
}

local treeTemplate = assetsFolder:WaitForChild("MinecraftTree") :: Model

function TerrainGenerator.new(customSeed: number?): TerrainGenerator
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

function TerrainGenerator:CalculateHeight(x: number, z: number): number
	local baseNoise = math.noise(x / CONFIG.NOISE_SCALE_TERRAIN, z / CONFIG.NOISE_SCALE_TERRAIN, self.Seed / 10000) * 6
	local detailNoise = math.noise(x / 12, z / 12, self.Seed / 5000) * 2.5
	local combined = 6 + baseNoise + detailNoise
	return math.clamp(math.floor(combined), 2, CONFIG.MOUNTAIN_HEIGHT)
end

function TerrainGenerator:IsCaveCell(x: number, y: number, z: number): boolean
	if y <= 1 then return false end
	local caveNoise = math.noise(
		x / CONFIG.NOISE_SCALE_CAVE, 
		y / CONFIG.NOISE_SCALE_CAVE, 
		(z + self.Seed) / CONFIG.NOISE_SCALE_CAVE
	)
	return caveNoise > CONFIG.CAVE_THRESHOLD
end

function TerrainGenerator:DetermineOreType(y: number): string
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

function TerrainGenerator:BuildWorldMatrix()
	self.WorldGrid = {}

	for gridX = 0, CONFIG.WORLD_SIZE - 1 do
		self.WorldGrid[gridX] = {}
		for gridZ = 0, CONFIG.WORLD_SIZE - 1 do
			self.WorldGrid[gridX][gridZ] = {}
			local height = self:CalculateHeight(gridX, gridZ)

			self.WorldGrid[gridX][gridZ][0] = "Bedrock"

			for y = 1, height - 2 do
				if not self:IsCaveCell(gridX, y, gridZ) then
					self.WorldGrid[gridX][gridZ][y] = self:DetermineOreType(y)
				end
			end

			if height - 1 > 0 then
				self.WorldGrid[gridX][gridZ][height - 1] = "Dirt"
			end

			local topBlock = "Grass"
			if height <= CONFIG.SEA_LEVEL + 1 then
				topBlock = "Sand"
			end
			self.WorldGrid[gridX][gridZ][height] = topBlock

			if height < CONFIG.SEA_LEVEL then
				for waterY = height + 1, CONFIG.SEA_LEVEL do
					self.WorldGrid[gridX][gridZ][waterY] = "Water"
				end
			end
		end
	end
end

function TerrainGenerator:PlantTree(posX: number, groundY: number, posZ: number)
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

function TerrainGenerator:InstantiateTerrain(): ( {BasePart}, {CFrame} )
	local partsBuffer: {BasePart} = {}
	local cframesBuffer: {CFrame} = {}
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

				self.TotalBlocksSpawned += 1

				if blockType == "Grass" and y > CONFIG.SEA_LEVEL + 1 then
					if self.Random:NextNumber() < CONFIG.TREE_CHANCE then
						self:PlantTree(posX, y, posZ)
					end
				end
			end
		end

		if gridX % 5 == 0 then
			task.wait()
		end
	end

	return partsBuffer, cframesBuffer
end

function TerrainGenerator:Generate(): boolean
	if self.IsGenerating then 
		return false 
	end

	self.IsGenerating = true
	self:InitializeFolders()
	self:BuildWorldMatrix()

	local partsBuffer, cframesBuffer = self:InstantiateTerrain()

	Workspace:BulkMoveTo(partsBuffer, cframesBuffer, Enum.BulkMoveMode.FireCFrameChanged)

	if self.WorldFolder then
		self.WorldFolder.Parent = Workspace
		self.WorldFolder:SetAttribute("TotalBlocks", self.TotalBlocksSpawned)
	end

	self.IsGenerating = false
	return true
end

local activeGenerator: TerrainGenerator? = nil

local function HandleWorldGenerationRequest(player: Player)
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
			print(string.format("[WorldGenerator]: Chunk generated successfully in %s sec. Total blocks: %d", tostring(elapsedTime), generator.TotalBlocksSpawned))
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
