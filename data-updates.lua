-- Give living trees a chance to drop a sapling when mined.
local chance = settings.startup["treeregrow-sapling-drop-chance"].value

if chance > 0 then
	for name, tree in pairs(data.raw["tree"]) do
		local is_dead = name:find("dead", 1, true) or name:find("dry", 1, true) or name:find("stump", 1, true)
		local minable = tree.minable
		if minable and not is_dead then
			if minable.result then
				minable.results = {{type = "item", name = minable.result, amount = minable.count or 1}}
				minable.result = nil
				minable.count = nil
			end
			if minable.results then
				table.insert(minable.results, {type = "item", name = "tree-sapling", amount = 1, probability = chance})
			end
		end
	end
end
