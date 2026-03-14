extends Control

# ---------------------------------------------------------------------------
# BASBAT COMMAND CENTER — GDScript port of PaulinaPorsmyr/FlightBaseSimulator
# ---------------------------------------------------------------------------

# ---- State ----------------------------------------------------------------
var cc_hour:   int = 8
var cc_day:    int = 1
var cc_fuel:   int = 50000
var cc_ammo:   int = 120
var cc_ue:     int = 5
var cc_pilots: int = 18

var cc_fleet: Array = [
	{"id": "G-101", "status": "READY", "flightTime": 12,  "nextService": 100, "uhTime": 0, "life": 88.0},
	{"id": "G-102", "status": "READY", "flightTime": 84,  "nextService": 100, "uhTime": 0, "life": 16.0},
	{"id": "G-103", "status": "READY", "flightTime": 45,  "nextService": 100, "uhTime": 0, "life": 55.0},
	{"id": "G-104", "status": "READY", "flightTime": 92,  "nextService": 100, "uhTime": 0, "life":  8.0},
	{"id": "G-105", "status": "READY", "flightTime":  5,  "nextService": 100, "uhTime": 0, "life": 95.0}
]

var cc_missions: Array = []
var selected_plan_day: int = 1

const MISSION_CONFIGS := {
	"DCA":   {"fuel": 3500, "ammo": 6, "desc": "AIR SUPERIORITY"},
	"RECCE": {"fuel": 4000, "ammo": 0, "desc": "ISR RECON"},
	"STRIKE":{"fuel": 5000, "ammo": 4, "desc": "SEAD STRIKE"}
}

# ---- UI node refs (resolved after ready) ----------------------------------
@onready var clock_label:   Label       = $VBox/TopStatus/HBox/TimeBlock/ClockLabel
@onready var day_label:     Label       = $VBox/TopStatus/HBox/TimeBlock/DayLabel
@onready var fuel_label:    Label       = $VBox/TopStatus/HBox/Resources/FuelLabel
@onready var ammo_label:    Label       = $VBox/TopStatus/HBox/Resources/AmmoLabel
@onready var ue_label:      Label       = $VBox/TopStatus/HBox/Resources/UELabel
@onready var pilots_label:  Label       = $VBox/TopStatus/HBox/Resources/PilotsLabel
@onready var adv_btn:       Button      = $VBox/TopStatus/HBox/AdvBtn

@onready var fleet_list:    RichTextLabel = $VBox/Main/HBox/LeftPanel/FleetList
@onready var calendar_grid: GridContainer = $VBox/Main/HBox/CenterPanel/ScrollCenter/CenterVBox/CalGrid
@onready var timeline_cont: HBoxContainer = $VBox/Main/HBox/CenterPanel/ScrollCenter/CenterVBox/Timeline
@onready var life_chart:    Control       = $VBox/Main/HBox/CenterPanel/ScrollCenter/CenterVBox/LifeChart

@onready var maint_label:   RichTextLabel = $VBox/Main/HBox/RightPanel/MaintLabel
@onready var log_label:     RichTextLabel = $VBox/Main/HBox/RightPanel/LogLabel
@onready var plunder_btn:   Button        = $VBox/Main/HBox/RightPanel/PlunderBtn

# Mission modal
@onready var modal:         Control       = $Modal
@onready var modal_day_lbl: Label         = $Modal/ModalContent/TitleLabel
@onready var task_picker:   OptionButton  = $Modal/ModalContent/TaskPicker
@onready var size_picker:   OptionButton  = $Modal/ModalContent/SizePicker
@onready var start_spin:    SpinBox       = $Modal/ModalContent/StartSpin
@onready var spec_label:    Label         = $Modal/ModalContent/SpecLabel
@onready var suggest_label: Label         = $Modal/ModalContent/SuggestLabel
@onready var save_btn:      Button        = $Modal/ModalContent/HBoxBtns/SaveBtn
@onready var cancel_btn:    Button        = $Modal/ModalContent/HBoxBtns/CancelBtn

# Life-chart data (drawn via _draw on the LifeChart control)
var chart_datasets: Array = []   # [{color, points:[Vector2]}]
var CHART_COLORS := [
	Color(0, 1, 0.25),   # green
	Color(0, 0.95, 1),   # cyan
	Color(1, 0, 0.24),   # red
	Color(0.95, 0.76, 0.06), # yellow
	Color(0.61, 0.35, 0.71)  # purple
]

# ---- Ready ----------------------------------------------------------------
func _ready() -> void:
	modal.visible = false

	# Wire LifeChart draw node back to this script
	if life_chart != null and life_chart.has_method("_draw"):
		life_chart.cc_ref = self

	adv_btn.pressed.connect(_on_advance_time)
	plunder_btn.pressed.connect(_on_plunder)
	save_btn.pressed.connect(_on_save_mission)
	cancel_btn.pressed.connect(_on_cancel_modal)
	task_picker.item_selected.connect(_on_task_changed)
	size_picker.item_selected.connect(_on_size_changed)

	# Populate pickers
	task_picker.clear()
	for k in MISSION_CONFIGS.keys():
		task_picker.add_item(k)

	size_picker.clear()
	size_picker.add_item("SINGLE (1)")
	size_picker.add_item("ROTE (2)")
	size_picker.add_item("FOUR-SHIP (4)")

	_refresh_all()

# ---- Advance time ---------------------------------------------------------
func _on_advance_time() -> void:
	cc_hour += 1
	if cc_hour >= 24:
		cc_hour = 0
		cc_day += 1

	for ac in cc_fleet:
		if ac["status"] == "UH" and ac["uhTime"] > 0:
			ac["uhTime"] -= 1
			if ac["uhTime"] == 0:
				ac["status"] = "READY"
				ac["life"] = 100.0
		if ac["status"] == "MISSION":
			ac["life"] -= 2.0
			ac["flightTime"] += 2
		if ac["life"] < 0.0:
			ac["life"] = 0.0

	for m in cc_missions:
		if m["day"] == cc_day and m["start"] == cc_hour and m["status"] == "PLANNED":
			_execute_ato(m)

	_refresh_all()

# ---- ATO execution --------------------------------------------------------
func _execute_ato(m: Dictionary) -> void:
	var task_key: String = m["task"]
	var spec: Dictionary = MISSION_CONFIGS[task_key]
	var ac_needed: int   = m["acNeeded"]
	var total_fuel: int  = spec["fuel"] * ac_needed

	var ready_ac: Array = cc_fleet.filter(func(f): return f["status"] == "READY")

	if ready_ac.size() >= ac_needed and cc_fuel >= total_fuel:
		cc_fuel -= total_fuel
		cc_ammo -= (spec["ammo"] * ac_needed)
		m["status"] = "EXECUTED"

		for i in range(ac_needed):
			var ac = ready_ac[i]
			ac["status"] = "MISSION"
			# Simulate mission return after a short real-time delay
			var t = get_tree().create_timer(2.0)
			t.timeout.connect(_on_mission_return.bind(ac))

		_log_msg("START ATO: %s (%d FPL)" % [task_key, ac_needed], Color(0, 0.95, 1))
	else:
		_log_msg("ATO ABORTED: RESURSBRIST", Color(1, 0, 0.24))

func _on_mission_return(ac: Dictionary) -> void:
	var roll: int = randi() % 6 + 1
	if roll >= 5:
		ac["status"] = "UH"
		ac["uhTime"] = 16 if roll == 6 else 4
		_log_msg("VARNING: %s FEL (T++: %dH)" % [ac["id"], ac["uhTime"]], Color(1, 0, 0.24))
	else:
		ac["status"] = "READY"
		_log_msg("RETUR: %s OK." % ac["id"], Color(0, 1, 0.25))
	_refresh_all()

# ---- Modal ----------------------------------------------------------------
func _open_modal(day: int) -> void:
	selected_plan_day = day
	modal_day_lbl.text = "ATO PLANERING // DAG %d" % day
	modal.visible = true
	_update_mission_specs()

func _on_cancel_modal() -> void:
	modal.visible = false

func _on_task_changed(_idx: int) -> void:
	_update_mission_specs()

func _on_size_changed(_idx: int) -> void:
	_update_mission_specs()

func _update_mission_specs() -> void:
	var task_key: String = task_picker.get_item_text(task_picker.selected)
	var size_idx: int    = size_picker.selected
	var ac_count: int    = [1, 2, 4][size_idx]
	var spec: Dictionary = MISSION_CONFIGS[task_key]

	spec_label.text = "BEHOV: %dL FUEL / %d AMMO." % [spec["fuel"] * ac_count, spec["ammo"] * ac_count]

	var sorted_ready: Array = cc_fleet.filter(func(f): return f["status"] == "READY")
	sorted_ready.sort_custom(func(a, b): return a["life"] > b["life"])
	var suggested: Array[String] = []
	for i in range(min(ac_count, sorted_ready.size())):
		suggested.append(sorted_ready[i]["id"])
	suggest_label.text = "FORSLAG: " + ", ".join(suggested)

func _on_save_mission() -> void:
	var task_key: String = task_picker.get_item_text(task_picker.selected)
	var size_idx: int    = size_picker.selected
	var ac_count: int    = [1, 2, 4][size_idx]
	cc_missions.append({
		"day":      selected_plan_day,
		"task":     task_key,
		"acNeeded": ac_count,
		"start":    int(start_spin.value),
		"status":   "PLANNED"
	})
	modal.visible = false
	_refresh_all()

# ---- Plunder --------------------------------------------------------------
func _on_plunder() -> void:
	for ac in cc_fleet:
		if ac["status"] == "UH" and ac["uhTime"] > 4:
			ac["uhTime"] += 8
			cc_ue += 1
			_log_msg("PLUNDRING: UE HAMTAD FRAN " + ac["id"], Color(0.95, 0.76, 0.06))
			_refresh_all()
			return

# ---- Log ------------------------------------------------------------------
var _log_lines: Array[String] = []

func _log_msg(msg: String, color: Color) -> void:
	_log_lines.insert(0, "[color=#%s]> %s[/color]" % [color.to_html(false), msg])
	if _log_lines.size() > 40:
		_log_lines.resize(40)
	if is_node_ready() and log_label != null:
		log_label.text = "\n".join(_log_lines)
		log_label.bbcode_enabled = true

# ---- Refresh all UI -------------------------------------------------------
func _refresh_all() -> void:
	_update_status_bar()
	_render_fleet()
	_render_calendar()
	_render_timeline()
	_build_chart_data()
	life_chart.queue_redraw()
	_render_log()

func _update_status_bar() -> void:
	clock_label.text  = "%02d:00" % cc_hour
	day_label.text    = "DAG: %d" % cc_day
	fuel_label.text   = "FUEL: %d" % cc_fuel
	ammo_label.text   = "AMMO: %d" % cc_ammo
	ue_label.text     = "UE: %d"   % cc_ue
	pilots_label.text = "PILOTS: %d" % cc_pilots

func _render_fleet() -> void:
	var lines: Array[String] = []
	for f in cc_fleet:
		var slit: float = (float(f["flightTime"]) / float(f["nextService"])) * 100.0
		var uh_left: int = f["nextService"] - f["flightTime"]
		var status_color: String
		match f["status"]:
			"READY":   status_color = "#00ff41"
			"UH":      status_color = "#ff003c"
			"MISSION": status_color = "#f1c40f"
			_:         status_color = "#aaaaaa"
		lines.append("[color=%s][b]%s[/b] [%s] | LIFE: %d%% | UH: %dH | SLIT: %d%%[/color]" % [
			status_color, f["id"], f["status"], int(f["life"]), uh_left, int(slit)
		])
	fleet_list.bbcode_enabled = true
	fleet_list.text = "\n".join(lines)

	# MRO bays
	var uh_lines: Array[String] = []
	for f in cc_fleet:
		if f["status"] == "UH":
			uh_lines.append("[color=#ff003c]%s [T-%dH][/color]" % [f["id"], f["uhTime"]])
	maint_label.bbcode_enabled = true
	maint_label.text = "\n".join(uh_lines) if uh_lines.size() > 0 else "TOMT"

func _render_calendar() -> void:
	# Clear existing day buttons
	for child in calendar_grid.get_children():
		child.queue_free()

	for i in range(1, 15):
		var has_m: bool = cc_missions.any(func(m): return m["day"] == i)
		var mission_count: int = cc_missions.filter(func(m): return m["day"] == i).size()

		var btn := Button.new()
		btn.text = "DAG %d\n%d ATO" % [i, mission_count]
		btn.custom_minimum_size = Vector2(70, 60)
		btn.tooltip_text = "Plan mission on day %d" % i

		if i == cc_day:
			btn.add_theme_color_override("font_color", Color(0, 1, 0.25))
		elif has_m:
			btn.add_theme_color_override("font_color", Color(0, 0.95, 1))

		var day_capture := i
		btn.pressed.connect(func(): _open_modal(day_capture))
		calendar_grid.add_child(btn)

func _render_timeline() -> void:
	for child in timeline_cont.get_children():
		child.queue_free()

	for i in range(24):
		var lbl := Label.new()
		lbl.text = "%02d" % i
		lbl.custom_minimum_size = Vector2(28, 40)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 9)
		if i == cc_hour:
			lbl.add_theme_color_override("font_color", Color(0, 1, 0.25))
		else:
			lbl.add_theme_color_override("font_color", Color(0.27, 0.27, 0.27))
		timeline_cont.add_child(lbl)

func _render_log() -> void:
	log_label.bbcode_enabled = true
	log_label.text = "\n".join(_log_lines)

# ---- Life chart data ------------------------------------------------------
func _build_chart_data() -> void:
	chart_datasets.clear()
	for idx in range(cc_fleet.size()):
		var ac = cc_fleet[idx]
		var points: Array[Vector2] = []
		var virtual_life: float = ac["life"]
		for d in range(1, 15):
			if d < cc_day:
				points.append(Vector2(d, -1))  # no data
				continue
			var missions_today: Array = cc_missions.filter(func(m): return m["day"] == d)
			var daily_drain: float = 1.0
			for m in missions_today:
				daily_drain += (float(m["acNeeded"]) * 8.0) / float(cc_fleet.size())
			virtual_life -= daily_drain
			if virtual_life <= 5.0:
				virtual_life = 100.0
			points.append(Vector2(d, clampf(virtual_life, 0.0, 100.0)))
		chart_datasets.append({"color": CHART_COLORS[idx % CHART_COLORS.size()], "points": points})

# ---- LifeChart custom draw -----------------------------------------------
func _draw_life_chart(chart_ctrl: Control) -> void:
	# Called from LifeChartDraw node's _draw()
	var rect: Rect2 = chart_ctrl.get_rect()
	var w: float    = rect.size.x
	var h: float    = rect.size.y
	var pad_l: float = 32.0
	var pad_b: float = 20.0
	var pad_t: float = 8.0
	var pad_r: float = 8.0

	var draw_w: float = w - pad_l - pad_r
	var draw_h: float = h - pad_t - pad_b

	# Background
	chart_ctrl.draw_rect(Rect2(Vector2.ZERO, rect.size), Color(0.02, 0.02, 0.02))

	# Grid lines (y)
	for pct in [0, 25, 50, 75, 100]:
		var y: float = pad_t + draw_h * (1.0 - pct / 100.0)
		chart_ctrl.draw_line(Vector2(pad_l, y), Vector2(w - pad_r, y), Color(0.13, 0.13, 0.13))
		chart_ctrl.draw_string(
			ThemeDB.fallback_font,
			Vector2(0, y + 4),
			"%d" % pct,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0, 1, 0.25)
		)

	# Dataset lines
	for ds in chart_datasets:
		var prev: Vector2 = Vector2.ZERO
		var first: bool = true
		for pt in ds["points"]:
			if pt.y < 0:
				first = true
				continue
			var x: float = pad_l + (pt.x - 1.0) / 13.0 * draw_w
			var y: float = pad_t + draw_h * (1.0 - pt.y / 100.0)
			var cur := Vector2(x, y)
			if not first:
				chart_ctrl.draw_line(prev, cur, ds["color"], 1.5)
			chart_ctrl.draw_circle(cur, 2.0, ds["color"])
			first = false
			prev = cur
