extends CanvasLayer

var sim_ref = null

# Shorthand prefix for all panels (now nested under TabContainer/Airbase Sim)
const _TAB := "TabContainer/Airbase Sim/"

func _ready():
	print("HUD READY")

	if has_node(_TAB + "MissionControlPanel/MissionTypePicker"):
		get_node(_TAB + "MissionControlPanel/MissionTypePicker").item_selected.connect(_on_mission_type_changed)

	if has_node(_TAB + "MissionControlPanel/PlaceMissionButton"):
		get_node(_TAB + "MissionControlPanel/PlaceMissionButton").pressed.connect(_on_place_mission_pressed)

	if has_node(_TAB + "MissionControlPanel/AircraftCountSpinBox"):
		get_node(_TAB + "MissionControlPanel/AircraftCountSpinBox").value = 1

	if has_node(_TAB + "AircraftControlPanel/AddAirCraftButton"):
		get_node(_TAB + "AircraftControlPanel/AddAirCraftButton").pressed.connect(_on_add_aircraft_pressed)

	if has_node(_TAB + "AircraftControlPanel/AircraftSpawnPicker"):
		var picker = get_node(_TAB + "AircraftControlPanel/AircraftSpawnPicker")
		picker.clear()
		picker.add_item("GripenE")
		picker.add_item("LOTUS")
		picker.add_item("GlobalEye")
		picker.add_item("VLO/UCAV")

func set_simulation(sim):
	sim_ref = sim
	_populate_mission_types()
	_on_mission_type_changed(0)

func _populate_mission_types():
	if not has_node(_TAB + "MissionControlPanel/MissionTypePicker"):
		return

	var picker = get_node(_TAB + "MissionControlPanel/MissionTypePicker")
	picker.clear()

	for mission_name in Mission.MissionType.keys():
		picker.add_item(mission_name)

func _on_mission_type_changed(index: int):
	if sim_ref == null:
		return
	if not has_node(_TAB + "MissionControlPanel/AircraftTypePicker"):
		return

	var aircraft_picker = get_node(_TAB + "MissionControlPanel/AircraftTypePicker")
	aircraft_picker.clear()

	var allowed = sim_ref.get_allowed_aircraft_for_mission_type(index)
	for aircraft_name in allowed:
		aircraft_picker.add_item(aircraft_name)

func _on_place_mission_pressed():
	if sim_ref == null:
		return

	var mission_type   = get_node(_TAB + "MissionControlPanel/MissionTypePicker").selected
	var type_picker    = get_node(_TAB + "MissionControlPanel/AircraftTypePicker")
	var aircraft_type  = type_picker.get_item_text(type_picker.selected)
	var aircraft_count = int(get_node(_TAB + "MissionControlPanel/AircraftCountSpinBox").value)

	sim_ref.arm_manual_mission(mission_type, aircraft_type, aircraft_count)

	if has_node(_TAB + "MissionControlPanel/MissionModeLabel"):
		get_node(_TAB + "MissionControlPanel/MissionModeLabel").text = "Click map..."

func _on_add_aircraft_pressed():
	if sim_ref == null:
		return

	var picker = get_node(_TAB + "AircraftControlPanel/AircraftSpawnPicker")
	var aircraft_type = picker.get_item_text(picker.selected)
	sim_ref.add_aircraft_inventory(aircraft_type, 1)

func update_hud(sim) -> void:
	if has_node(_TAB + "AircraftPanel/AircraftLabel"):
		var aircraft_lines: Array[String] = []
		aircraft_lines.append("ACTIVE AIRCRAFT")
		aircraft_lines.append("")

		for ac in sim.aircraft_list:
			aircraft_lines.append(
				"%s | %s | %s | Fuel %.0f" % [
					ac.aircraft_id,
					ac.aircraft_type,
					Aircraft.AircraftState.keys()[ac.state],
					ac.fuel_level
				]
			)

		get_node(_TAB + "AircraftPanel/AircraftLabel").text = "\n".join(aircraft_lines)

	if has_node(_TAB + "QueuePanel/QueueLabel") and sim.bases.size() > 0:
		var base = sim.bases[0]
		var queue_lines: Array[String] = []

		var fuel_names: Array[String] = []
		for ac in base.fuel_queue:
			fuel_names.append(ac.aircraft_id)

		var ammo_names: Array[String] = []
		for ac in base.ammo_queue:
			ammo_names.append(ac.aircraft_id)

		var service_names: Array[String] = []
		for ac in base.service_queue:
			service_names.append(ac.aircraft_id)

		var runway_names: Array[String] = []
		for ac in base.runway_queue:
			runway_names.append(ac.aircraft_id)

		queue_lines.append("BASE / QUEUES")
		queue_lines.append("")
		queue_lines.append("Fuel queue: "    + ", ".join(fuel_names))
		queue_lines.append("Ammo queue: "    + ", ".join(ammo_names))
		queue_lines.append("Service queue: " + ", ".join(service_names))
		queue_lines.append("Runway queue: "  + ", ".join(runway_names))
		queue_lines.append("")
		queue_lines.append("Fuel stock: %.0f" % base.fuel_stock)
		queue_lines.append("Ammo stock: %d"   % base.ammo_stock)
		queue_lines.append("Bay 1 busy: %s"   % str(base.service_bay_busy[0]))
		queue_lines.append("Bay 2 busy: %s"   % str(base.service_bay_busy[1]))

		get_node(_TAB + "QueuePanel/QueueLabel").text = "\n".join(queue_lines)

	if has_node(_TAB + "MissionPanel/MissionLabel"):
		var mission_lines: Array[String] = []
		mission_lines.append("MISSIONS")
		mission_lines.append("")

		for mission in sim.missions:
			mission_lines.append(
				"%s | %s | %s | %s %d/%d" % [
					mission.id,
					Mission.MissionType.keys()[mission.type],
					mission.status,
					mission.aircraft_type,
					mission.assigned_aircraft.size(),
					mission.aircraft_count
				]
			)

		get_node(_TAB + "MissionPanel/MissionLabel").text = "\n".join(mission_lines)

	if has_node(_TAB + "FleetPanel/FleetLabel"):
		var fleet_lines: Array[String] = []
		fleet_lines.append("FLEET")
		fleet_lines.append("")

		for aircraft_type in sim.fleet_inventory.keys():
			var data = sim.fleet_inventory[aircraft_type]
			fleet_lines.append(
				"%s | total %d | avail %d | busy %d" % [
					aircraft_type,
					data["total"],
					data["available"],
					data["busy"]
				]
			)

		get_node(_TAB + "FleetPanel/FleetLabel").text = "\n".join(fleet_lines)

	if has_node(_TAB + "MissionControlPanel/MissionModeLabel"):
		if sim.awaiting_map_click:
			get_node(_TAB + "MissionControlPanel/MissionModeLabel").text = "Click map..."
		else:
			get_node(_TAB + "MissionControlPanel/MissionModeLabel").text = "Idle"
