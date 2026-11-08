extends Node
## The Conquest section's hub (main menu → Conquest): Conquest's own page — its look (ConquestLook), the Demon's Lair
## backdrop with Malakor, what the mode is (the story in short, then three cards: the land, the factions, the King
## and how to win), and Find / Host a Conquest game (`Net.conquest_section`), Back to the main menu. Leaving a
## Conquest game comes back here; when the game dropped you (`Net.leave_reason`) a notice says why.

const BROWSER_SCENE := "res://scenes/ui/server_browser.tscn"
const HOST_SCENE := "res://scenes/ui/host_menu.tscn"
const PANEL_WIDTH: float = 820.0
const STORY := ("King Malakor fell defending his realm, and rose again as a demon: six arms grafted from his own fallen "
		+ "champions. His hordes hold the land. Four factions march from the corners to take it back, zone by zone, "
		+ "and storm his Lair in the middle.")

var _frame: Dictionary
var _panel: PanelContainer
var _cards: BoxContainer
var _notice: Dictionary = {}
var _leaving: bool = false
var _host_button: Button


func _ready() -> void:
	get_tree().paused = false
	Net.conquest_section = true
	ConquestLook.apply(self)
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()
	if Net.leave_reason != "":
		_show_notice(Net.leave_reason)
		Net.leave_reason = ""
	elif not OS.has_feature("mobile"):
		_host_button.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _notice.is_empty():
			_back()
		else:
			MenuKit.close_dialog(_notice)
			_notice = {}


func _build() -> void:
	_frame = MenuKit.frame($UI, "Conquest")
	var subtitle := MenuKit.label("The Six-Armed Sovereign", &"HeaderLabel", 34)
	subtitle.name = "Subtitle"
	(_frame.tools as Control).add_child(subtitle)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(_frame.body as Control).add_child(row)
	_panel = PanelContainer.new()
	_panel.name = "About"
	row.add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 16)
	scroll.add_child(column)
	var story := MenuKit.label(STORY, &"", 26)
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(story)
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 12)
	column.add_child(_cards)
	var land_size := roundi(ConquestMode.WORLD_HALF * 2.0)
	_card("The land", "crown", [
		"A %d m wild land in %d zones: calm by the corners, deadlier toward the middle." % [land_size, ConquestMode.ZONE_EDGES.size() + 1],
		"Demon warbands roam, grow back and march on the places you hold; storms, meteors and the Blood Moon "
				+ "strike only the inner zones."])
	_card("Your faction", "flag", [
		"Up to %d heroes in four factions (%d each), starting unarmed at a Citadel in a corner." % [
				Net.CONQUEST_MAX_PLAYERS, Net.CONQUEST_MAX_PLAYERS / ConquestMode.FACTIONS],
		"Take villages, outposts and cities; feed and arm your soldiers; train squads and send couriers with the M map."])
	_card("The King", "skull", [
		"Malakor rules the Lair with his four risen champions: Sir Eldor, Vaira, Valendor and Mother Tyressa.",
		"Win: slay Malakor (most damage to him, the killing blow counts extra), hold the Lair %d minutes, take every Citadel, reach the score, or lead when the %d minutes run out." % [
				roundi(ConquestMode.THRONE_WIN_TICKS * LogisticsManager.TICK / 60.0), ConquestMode.DEFAULT_TIME]])
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	var bottom: HBoxContainer = _frame.bottom
	var back := MenuKit.button("Back")
	back.name = "BackButton"
	back.pressed.connect(_back)
	bottom.add_child(back)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(gap)
	var find := MenuKit.button("Find Conquest Game", false, Vector2(340, 80))
	find.name = "ConquestFindButton"
	find.pressed.connect(_go_to.bind(BROWSER_SCENE))
	bottom.add_child(find)
	_host_button = MenuKit.button("Host Conquest Game", true, Vector2(360, 80))
	_host_button.name = "ConquestHostButton"
	_host_button.pressed.connect(_go_to.bind(HOST_SCENE))
	bottom.add_child(_host_button)


## One card: a gold title with a round icon, then its lines.
func _card(title: String, icon: String, lines: Array) -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"PanelInset"
	_cards.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)
	var badge := UiKit.medal(icon, 56.0)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(badge)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 4)
	row.add_child(text)
	text.add_child(MenuKit.label(title, &"HeaderLabel", 30))
	for line in lines:
		var label := MenuKit.label(line, &"HintLabel", 22)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(label)


func _back() -> void:
	Net.conquest_section = false
	_go_to(Net.MENU_SCENE)


func _go_to(path: String) -> void:
	if _leaving or not is_inside_tree():
		return
	_leaving = true
	get_tree().change_scene_to_file(path)


func _show_notice(reason: String) -> void:
	_notice = MenuKit.dialog($UI, "Disconnected")
	var text := MenuKit.label(reason, &"", 30)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(_notice.body as Control).add_child(text)
	var ok := MenuKit.button("OK", true)
	ok.name = "NoticeOkButton"
	ok.pressed.connect(func() -> void:
		MenuKit.close_dialog(_notice)
		_notice = {})
	(_notice.buttons as Control).add_child(ok)
	ok.grab_focus.call_deferred()


## Landscape: the story on the left, Malakor on the right. Phones: the panel fills the width.
func _layout() -> void:
	var compact := MenuKit.is_compact(_panel)
	var width := get_viewport().get_visible_rect().size.x
	_panel.custom_minimum_size.x = (width - 32.0) if compact else minf(PANEL_WIDTH, width * 0.48)
	(_frame.tools as Control).visible = not compact
	var backdrop := get_node_or_null("Backdrop")
	if backdrop:
		backdrop.set("view_shift", 0.0 if compact else -3.2)
