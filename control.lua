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

	-- Ghosts don't collide with trees, so check for them separately: a seed
	-- landing on a planned build would block the robots coming to build it.
	-- An area search matches by bounding box, so big ghosts (3x3 machines)
	-- count even when their centre is a couple of tiles away.
	local box = {{pos.x - 0.6, pos.y - 0.6}, {pos.x + 0.6, pos.y + 0.6}}
	if surface.count_entities_filtered{area = box, type = {"entity-ghost", "tile-ghost"}} > 0 then return end

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

-- Planted saplings ---------------------------------------------------------
-- The sapling item places a stand-in entity, because trees can't be ghosts.
-- The stand-in can be, so saplings go in blueprints, robots plant them, and
-- the reforest planner lays them out. After a short while it grows into a
-- real tree that takes after the dominant species around it, so replanting a
-- logged area restores the local forest type.

local PLANTED = "treeregrow-planted-sapling"
local PLANNER = "treeregrow-reforest-planner"
local GROW_CHECK_TICKS = 60

-- The most common living species within MATCH_RADIUS, or the default tree.
local function species_for(surface, pos)
	if not settings.global["treeregrow-match-nearby-species"].value then return SAPLING_TREE end
	local counts, best, best_count = {}, nil, nil
	for _, tree in pairs(surface.find_entities_filtered{position = pos, radius = MATCH_RADIUS, type = "tree"}) do
		if is_spreadable(tree.name) then
			local n = (counts[tree.name] or 0) + 1
			counts[tree.name] = n
			if not best_count or n > best_count then best, best_count = tree.name, n end
		end
	end
	return best or SAPLING_TREE
end

-- Swap a planted sapling for a real tree. If something has since taken the
-- spot, the sapling drops back as an item rather than vanishing.
local function grow(sapling)
	if not sapling.valid then return end
	local surface, pos = sapling.surface, sapling.position
	local tree = species_for(surface, pos)
	sapling.destroy{raise_destroy = true}
	if surface.can_place_entity{name = tree, position = pos} then
		surface.create_entity{name = tree, position = pos, raise_built = true}
	else
		surface.spill_item_stack{position = pos, stack = {name = "tree-sapling", count = 1}}
	end
end

local function on_planted(event)
	local e = event.entity
	if not (e and e.valid and e.name == PLANTED) then return end
	local seconds = settings.global["treeregrow-sapling-grow-seconds"].value
	if seconds <= 0 then
		grow(e)
		return
	end
	storage.growing = storage.growing or {}
	storage.growing[e.unit_number] = {entity = e, at = game.tick + seconds * 60}
end

local planted_filter = {{filter = "name", name = PLANTED}}
script.on_event(defines.events.on_built_entity, on_planted, planted_filter)
script.on_event(defines.events.on_robot_built_entity, on_planted, planted_filter)
script.on_event(defines.events.script_raised_built, on_planted, planted_filter)
script.on_event(defines.events.script_raised_revive, on_planted, planted_filter)

script.on_nth_tick(GROW_CHECK_TICKS, function()
	local growing = storage.growing
	if not growing then return end
	local now = game.tick
	for id, g in pairs(growing) do
		if not g.entity.valid then
			growing[id] = nil
		elseif now >= g.at then
			growing[id] = nil
			grow(g.entity)
		end
	end
end)

-- Reforest planner: fill an area's natural ground with sapling ghosts in a
-- loose scatter (one per spacing x spacing cell, at a random tile in it).
local function natural(surface, x, y)
	local tile = surface.get_tile(x, y)
	return tile.valid and tile.prototype.autoplace_specification ~= nil
end

local function reforest(surface, force, area, spacing, player)
	local x1, y1 = math.floor(area.left_top.x), math.floor(area.left_top.y)
	local x2, y2 = math.ceil(area.right_bottom.x) - 1, math.ceil(area.right_bottom.y) - 1
	local placed = 0
	for cx = x1, x2, spacing do
		for cy = y1, y2, spacing do
			-- a few tries at a random tile in the cell, for a natural look
			for _ = 1, 4 do
				local x = math.min(cx + math.random(0, spacing - 1), x2)
				local y = math.min(cy + math.random(0, spacing - 1), y2)
				local pos = {x = x + 0.5, y = y + 0.5}
				if natural(surface, x, y)
					and surface.count_entities_filtered{area = {{x, y}, {x + 1, y + 1}}, type = {"entity-ghost", "tree"}} == 0
					and surface.can_place_entity{name = PLANTED, position = pos, force = force,
						build_check_type = defines.build_check_type.manual_ghost} then
					surface.create_entity{name = "entity-ghost", inner_name = PLANTED, position = pos,
						force = force, player = player}
					placed = placed + 1
					break
				end
			end
		end
	end
	return placed
end

local function unplan(surface, force, area)
	local removed = 0
	for _, g in pairs(surface.find_entities_filtered{area = area, type = "entity-ghost", force = force}) do
		if g.ghost_name == PLANTED then
			g.destroy()
			removed = removed + 1
		end
	end
	return removed
end

script.on_event(defines.events.on_player_selected_area, function(event)
	if event.item ~= PLANNER then return end
	local player = game.get_player(event.player_index)
	local spacing = settings.get_player_settings(player)["treeregrow-planner-spacing"].value
	local n = reforest(event.surface, player.force, event.area, spacing, player)
	player.create_local_flying_text{text = {"treeregrow.planned", n}, create_at_cursor = true}
end)

script.on_event(defines.events.on_player_alt_selected_area, function(event)
	if event.item ~= PLANNER then return end
	local player = game.get_player(event.player_index)
	local n = unplan(event.surface, player.force, event.area)
	player.create_local_flying_text{text = {"treeregrow.unplanned", n}, create_at_cursor = true}
end)

-- For other mods and scripts (Claude Companion lays out forests with it):
--   remote.call("treeregrow", "reforest", surface_index, {{x1, y1}, {x2, y2}}, spacing, force_name)
remote.add_interface("treeregrow", {
	reforest = function(surface_index, box, spacing, force_name)
		local surface = game.get_surface(surface_index)
		local area = {left_top = {x = box[1][1], y = box[1][2]}, right_bottom = {x = box[2][1], y = box[2][2]}}
		return reforest(surface, game.forces[force_name or "player"], area, spacing or 3, nil)
	end,
	unplan = function(surface_index, box, force_name)
		local surface = game.get_surface(surface_index)
		return unplan(surface, game.forces[force_name or "player"], box)
	end,
	growing = function()
		local n = 0
		for _ in pairs(storage.growing or {}) do n = n + 1 end
		return n
	end,
})

-- Leaf regrowth ------------------------------------------------------------
-- Pollution strips leaves off trees one "gray stage" at a time, and since
-- Factorio 2.1.24 nothing brings them back. Here trees regain a stage at a
-- time wherever their chunk's pollution has dropped below a threshold.
--
-- A slow scan walks every chunk and queues the ones holding damaged living
-- trees; the queue is then revisited often enough that a bare tree regrows
-- fully in the configured time. Vanilla trees have 15 gray stages.

local LEAF_TICKS = 10 -- how often the regrowth work runs
local LEAF_SCAN_PER_RUN = 2 -- chunks scanned per surface per run (12/s)
local LEAF_STAGES = 15

local function chunk_key(x, y) return x .. "," .. y end

-- Living trees standing in the chunk. The area search also returns trees on
-- the border that belong to the neighbour, which would otherwise heal twice.
local function chunk_trees(surface, c)
	local x0, y0 = c.x * 32, c.y * 32
	local trees = {}
	for _, tree in pairs(surface.find_entities_filtered{area = {{x0, y0}, {x0 + 32, y0 + 32}}, type = "tree"}) do
		local pos = tree.position
		if pos.x >= x0 and pos.x < x0 + 32 and pos.y >= y0 and pos.y < y0 + 32 and is_spreadable(tree.name) then
			trees[#trees + 1] = tree
		end
	end
	return trees
end

-- Per-surface state. `chunks` lists every generated chunk once (kept current
-- by on_chunk_generated) so the scan never has to rebuild it mid-game; the
-- one full listing happens on load or when a surface is first seen.
local function leaf_state(surface)
	storage.leaf = storage.leaf or {}
	local st = storage.leaf[surface.index]
	if st then return st, false end
	local chunks = {}
	for c in surface.get_chunks() do chunks[#chunks + 1] = {x = c.x, y = c.y} end
	st = {chunks = chunks, scan_pos = 1, queue = {}, queued = {}, heal_pos = 1, budget = 0}
	storage.leaf[surface.index] = st
	return st, true
end

-- Trees only lose leaves to a pollutant that damages them (Nauvis pollution,
-- not Gleba spores), so other surfaces are skipped.
local function leaf_surface(surface)
	if not surface.valid or surface.platform then return false end
	local pollutant = surface.pollutant_type
	return pollutant ~= nil and pollutant.damages_trees
end

local function has_damaged_tree(surface, c)
	for _, tree in pairs(chunk_trees(surface, c)) do
		if tree.tree_gray_stage_index > 0 then return true end
	end
	return false
end

local function scan_chunks(surface, st)
	if #st.chunks == 0 then return end
	for _ = 1, LEAF_SCAN_PER_RUN do
		if st.scan_pos > #st.chunks then st.scan_pos = 1 end
		local c = st.chunks[st.scan_pos]
		st.scan_pos = st.scan_pos + 1
		local key = chunk_key(c.x, c.y)
		if not st.queued[key] and has_damaged_tree(surface, c) then
			st.queued[key] = true
			st.queue[#st.queue + 1] = c
		end
	end
end

-- Give every damaged tree in the chunk one stage back. Returns false once the
-- chunk has no damaged living trees left, so it can leave the queue.
local function heal_chunk(surface, c, limit)
	if surface.get_pollution({c.x * 32 + 16, c.y * 32 + 16}) >= limit then return true end
	local damaged = false
	for _, tree in pairs(chunk_trees(surface, c)) do
		local stage = tree.tree_gray_stage_index
		if stage > 0 then
			tree.tree_gray_stage_index = stage - 1
			if stage > 1 then damaged = true end
		end
	end
	return damaged
end

local function heal_queue(surface, st, limit, round_ticks)
	local n = #st.queue
	if n == 0 then st.budget = 0 return end
	-- visit each queued chunk once per round, spread evenly over the round
	st.budget = math.min(st.budget + n * LEAF_TICKS / round_ticks, n)
	while st.budget >= 1 and #st.queue > 0 do
		st.budget = st.budget - 1
		if st.heal_pos > #st.queue then st.heal_pos = 1 end
		local c = st.queue[st.heal_pos]
		if heal_chunk(surface, c, limit) then
			st.heal_pos = st.heal_pos + 1
		else
			st.queued[chunk_key(c.x, c.y)] = nil
			st.queue[st.heal_pos] = st.queue[#st.queue]
			st.queue[#st.queue] = nil
		end
	end
end

-- GMO Trees research: trees regrow leaves at any pollution level. Pollution
-- keeps stripping them as usual, and since trees absorb pollution by losing
-- leaves, regrown forests near the factory keep cleaning the air. Trees are
-- neutral, so one force researching it applies to the whole map.
local GMO_TECH = "treeregrow-gmo-trees"

local function sync_gmo()
	storage.gmo = false
	for _, force in pairs(game.forces) do
		local tech = force.technologies[GMO_TECH]
		if tech and tech.researched then storage.gmo = true return end
	end
end

script.on_nth_tick(LEAF_TICKS, function()
	if not settings.global["treeregrow-enable-leaf-regrowth"].value then return end

	-- Without GMO trees, never heal where pollution is still damaging trees:
	-- leaves come back only once the air has cleared.
	local limit = math.huge
	if not storage.gmo then
		limit = math.min(settings.global["treeregrow-leaf-regrowth-pollution"].value,
			game.map_settings.pollution.min_pollution_to_damage_trees)
	end
	local round_ticks = settings.global["treeregrow-leaf-regrowth-minutes"].value * 3600 / LEAF_STAGES

	for _, surface in pairs(game.surfaces) do
		if leaf_surface(surface) then
			local st = leaf_state(surface)
			scan_chunks(surface, st)
			heal_queue(surface, st, limit, round_ticks)
		end
	end
end)

script.on_event(defines.events.on_chunk_generated, function(event)
	local surface = event.surface
	if not leaf_surface(surface) then return end
	local st, fresh = leaf_state(surface)
	if not fresh then st.chunks[#st.chunks + 1] = {x = event.position.x, y = event.position.y} end
end)

script.on_event(defines.events.on_surface_deleted, function(event)
	if storage.leaf then storage.leaf[event.surface_index] = nil end
end)

-- Build the chunk lists during load rather than on a running tick.
local function init_leaf_states()
	storage.leaf = storage.leaf or {}
	for _, surface in pairs(game.surfaces) do
		if leaf_surface(surface) then leaf_state(surface) end
	end
end

local function on_research_changed(event)
	if event.research.name == GMO_TECH then sync_gmo() end
end
script.on_event(defines.events.on_research_finished, on_research_changed)
script.on_event(defines.events.on_research_reversed, on_research_changed)
script.on_event(defines.events.on_technology_effects_reset, sync_gmo)
script.on_event(defines.events.on_forces_merged, sync_gmo)

script.on_init(function()
	init_leaf_states()
	sync_gmo()
end)
script.on_configuration_changed(function()
	init_leaf_states()
	sync_gmo()
end)
