return PlaceObj('ModDef', {
	'title', "WIP Tunnel Boring Machine",
	'description', "Library that allows adding the ability to dig a tunnel over time to a building.\n\nDigging a tunnel produces Waste Rock and optionally consumes resources to line the tunnel. Digging a tunnel can interrupt the operation of a building, so that it does not perform its function until the tunnel is complete (eg. a Mine), or can happen in parallel to the normal operation of the building (eg. an underground passage).\n\nPermission is granted to update this mod to support the latest version of the game if I'm not around to do it myself.",
	'last_changes', "Initial version.",
	'dependencies', {
		PlaceObj('ModDependency', {
			'id', "ChoGGi_WasterockProdInfo",
			'title', "WasteRock Prod Info",
			'version_minor', 3,
			'required', false,
		}),
	},
	'id', "mrudat_TunnelBoringMachine",
	'pops_desktop_uuid', "26624ca5-42e6-4a9c-ac13-3d7706410602",
	'pops_any_uuid', "0de2e0b4-2c92-4382-966f-37d860802baa",
	'author', "mrudat",
	'version', 4,
	'lua_revision', 233360,
	'saved_with_revision', 245618,
	'code', {
		"Code/TunnelBoringMachine.lua",
	},
	'saved', 1566095836,
	'TagOther', true,
})
