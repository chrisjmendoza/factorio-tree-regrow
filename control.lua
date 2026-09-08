-- TreeRegrow: forests spread onto natural ground; saplings plant real trees.

local SAPLING_TREE = "tree-05" -- entity the tree-sapling item places
local SPREAD_CYCLE_TICKS = 300 -- one spread pass every 5 seconds
local DENSITY_RADIUS = 5 -- radius used for the local density cap
local MATCH_RADIUS = 16 -- how far a planted sapling looks for a species to match

-- Dead husks don't propagate.
local function is_spreadable(name)
	return not (name:find("dead", 1, true) or name:find("dry", 1, true) or name:find("stump", 1, true))
end

-- One spread attempt: pick a random generated chunk, and if it holds trees, try
-- to seed one of them a short distance away onto unpaved, natural terrain.
local function try_spread(surface, opts)
	local chunk = surface.get_random_chunk()
	if not chunk then return end

	local area = {
		{chunk.x * 32, chunk.y * 32},
		{chunk.x * 32 + 32, chunk.y * 32 + 32},
	}
	local trees = surface.find_entities_filtered{area = area, type = "tree", limit = 8}
	if #trees == 0 then return end

	local parent = trees[math.random(#trees)]
	if not (parent.valid and is_spreadable(parent.name)) then return end

	local angle = math.random() * 2 * math.pi
	local dist = 2 + math.random() * (opts.distance - 2)
	local pos = {
		x = parent.position.x + math.cos(angle) * dist,
		y = parent.position.y + math.sin(angle) * dist,
	}

	if not surface.is_chunk_generated({x = math.floor(pos.x / 32), y = math.floor(pos.y / 32)}) then return end

	-- Only tiles that generate naturally (grass, dirt, sand...) accept seeds.
	-- Player-placed tiles like concrete, stone brick or landfill have no
	-- autoplace specification, which is what keeps paved-in trees solitary.
	local tile = surface.get_tile(math.floor(pos.x), math.floor(pos.y))
	if not (tile.valid and tile.prototype.autoplace_specification) then return end

	if opts.block_polluted and surface.get_pollution(pos) > 0.1 then return end

	if surface.count_entities_filtered{position = pos, radius = DENSITY_RADIUS, type = "tree"} >= opts.max_density then
		return
	end

	if not surface.can_place_entity{name = parent.name, position = pos} then return end

	surface.create_entity{name = parent.name, position = pos, raise_built = true}
end

script.on_nth_tick(SPREAD_CYCLE_TICKS, function()
	if not settings.global["treeregrow-enable-spread"].value then return end

	local opts = {
		distance = settings.global["treeregrow-spread-distance"].value,
		max_density = settings.global["treeregrow-max-density"].value,
		block_polluted = settings.global["treeregrow-pollution-blocks-spread"].value,
	}
	local attempts = settings.global["treeregrow-spread-attempts"].value

	for _, surface in pairs(game.surfaces) do
		if surface.valid and not surface.platform then
			for _ = 1, attempts do
				try_spread(surface, opts)
			end
		end
	end
end)

-- A freshly planted sapling takes after the dominant species around it, so
-- replanting a logged area restores the local forest type. With no trees
-- nearby it stays the default tree.
local function on_sapling_built(event)
	local entity = event.entity
	if not (entity and entity.valid) then return end
	if not settings.global["treeregrow-match-nearby-species"].value then return end

	local surface = entity.surface
	local pos = entity.position
	local nearby = surface.find_entities_filtered{position = pos, radius = MATCH_RADIUS, type = "tree"}

	local counts = {}
	local best, best_count
	for _, tree in pairs(nearby) do
		if tree ~= entity and is_spreadable(tree.name) then
			local n = (counts[tree.name] or 0) + 1
			counts[tree.name] = n
			if not best_count or n > best_count then
				best, best_count = tree.name, n
			end
		end
	end

	if best and best ~= entity.name then
		entity.destroy{raise_destroy = true}
		surface.create_entity{name = best, position = pos, raise_built = true}
	end
end

local sapling_filter = {{filter = "name", name = SAPLING_TREE}}
script.on_event(defines.events.on_built_entity, on_sapling_built, sapling_filter)
script.on_event(defines.events.on_robot_built_entity, on_sapling_built, sapling_filter)
