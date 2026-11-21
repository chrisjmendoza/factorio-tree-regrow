require("util")

-- Borrow the icon of the tree the sapling plants, with a wood-icon fallback.
local sapling_tree = data.raw["tree"]["tree-05"]
local icons
if sapling_tree and sapling_tree.icons then
	icons = table.deepcopy(sapling_tree.icons)
elseif sapling_tree and sapling_tree.icon then
	icons = {{icon = sapling_tree.icon, icon_size = sapling_tree.icon_size or 64}}
else
	icons = {{icon = "__base__/graphics/icons/wood.png", icon_size = 64}}
end

data:extend({
	{
		type = "item",
		name = "tree-sapling",
		icons = icons,
		subgroup = "terrain",
		order = "z[tree-sapling]",
		place_result = "tree-05",
		stack_size = 100,
	},
})

if settings.startup["treeregrow-enable-sapling-recipe"].value then
	data:extend({
		{
			type = "recipe",
			name = "tree-sapling",
			-- No category: 2.1 removed `category` (now `categories`); default is crafting.
			energy_required = 1,
			ingredients = {{type = "item", name = "wood", amount = 2}},
			results = {{type = "item", name = "tree-sapling", amount = 1}},
			enabled = false,
		},
		{
			type = "technology",
			name = "treeregrow-forestry",
			icons = table.deepcopy(icons),
			unit = {
				count = 25,
				ingredients = {{"automation-science-pack", 1}},
				time = 15,
			},
			effects = {
				{type = "unlock-recipe", recipe = "tree-sapling"},
			},
		},
	})
end
