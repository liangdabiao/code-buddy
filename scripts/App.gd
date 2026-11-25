extends Control

const CurriculumScript = preload("res://scripts/CurriculumRepository.gd")
const ProgressScript = preload("res://scripts/ProgressStore.gd")
const UIKitScript = preload("res://scripts/UIKit.gd")
const ChromeScript = preload("res://scripts/Chrome.gd")

const PAGE_SIZE := 9
const READER_CHARS := 300

var ui: UIKit
var repo
var progress
var background: TextureRect
var chrome: Control
var screen_root: Control

var screen := "home"
var title_text := "编程学习宝" setget _set_title_text
var footer_text := "" setget _set_footer_text
var menu_panels: Array = []
var menu_meta: Array = []
var menu_index := 0
var last_action_msec := 0

var toast_text := ""
var toast_time := 0.0

var module_page := 0
var unit_page := 0
var current_module_id := ""
var current_unit_index := -1

var body_pages: Array = []
var body_page := 0

var quiz_items: Array = []
var quiz_index := 0
var quiz_correct := 0
var quiz_state := "playing"
var quiz_selected := -1
var quiz_result: Dictionary = {}


func _ready() -> void:
	ui = UIKitScript.new()
	repo = CurriculumScript.new()
	progress = ProgressScript.new()
	add_child(repo)
	add_child(progress)
	background = ui.texture(self, "res://assets/icons/forest_bg.png", Rect2(Vector2.ZERO, Vector2(640, 480)))
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	move_child(background, 0)
	chrome = ChromeScript.new()
	chrome.app = self
	chrome.rect_size = Vector2(640, 480)
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(chrome)
	_show_home()


func _set_title_text(value: String) -> void:
	title_text = value
	_sync_chrome()


func _set_footer_text(value: String) -> void:
	footer_text = value
	_sync_chrome()


func _sync_chrome() -> void:
	if chrome != null and is_instance_valid(chrome):
		chrome.update()


func draw_chrome(ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(0, 0, 640, 54), Color(0.035, 0.075, 0.078, 0.94))
	ci.draw_rect(Rect2(0, 53, 640, 1), ui.LINE)
	ci.draw_string(ui.font(20), Vector2(20, 35), title_text, ui.TEXT)
	var status := "%d/%d 课  ·  %d XP  ·  连续 %d 天" % [_track_completed_count(), repo.unit_count(), int(progress.data.get("xp", 0)), int(progress.data.get("streak", 0))]
	ci.draw_string(ui.font(13), Vector2(620 - ui.font(13).get_string_size(status).x, 34), status, ui.GOLD)
	ci.draw_rect(Rect2(0, 444, 640, 36), Color(0.035, 0.075, 0.078, 0.94))
	ci.draw_rect(Rect2(0, 444, 640, 1), ui.LINE)
	ci.draw_string(ui.font(14), Vector2(20, 467), footer_text, ui.MUTED)
	if toast_text != "":
		var width := ui.font(17).get_string_size(toast_text).x + 40
		ci.draw_rect(Rect2((640 - width) / 2, 61, width, 38), Color(0.12, 0.25, 0.21, 0.96))
		ci.draw_string(ui.font(17), Vector2((640 - width) / 2 + 20, 87), toast_text, ui.GREEN)


func _process(delta: float) -> void:
	if toast_time > 0:
		toast_time -= delta
		if toast_time <= 0:
			toast_text = ""
			_sync_chrome()


func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event is InputEventKey and event.echo:
		return
	var action := ""
	for candidate in ["nav_up", "nav_down", "nav_left", "nav_right", "accept", "back", "replay", "hint", "prev", "next", "menu"]:
		if event.is_action_pressed(candidate):
			action = candidate
			break
	if action == "":
		return
	var now := OS.get_ticks_msec()
	if now - last_action_msec < 70:
		return
	last_action_msec = now
	get_viewport().set_input_as_handled()
	match action:
		"nav_up": _navigate(-1)
		"nav_down": _navigate(1)
		"nav_left": _page_step(-1)
		"nav_right": _page_step(1)
		"accept": _accept()
		"back": _back()
		"replay": _replay()
		"hint": _hint()
		"prev": _page_step(-1)
		"next": _page_step(1)
		"menu": _learning_menu()


func _clear_screen() -> void:
	if is_instance_valid(screen_root):
		screen_root.free()
	screen_root = Control.new()
	screen_root.rect_size = Vector2(640, 480)
	screen_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen_root)
	move_child(screen_root, 1)
	menu_panels.clear()
	menu_meta.clear()
	menu_index = 0
	_sync_chrome()


func _show_home() -> void:
	_clear_screen()
	screen = "home"
	title_text = "编程学习宝"
	footer_text = "方向键 选择   A 确认   B 返回   开始 退出"
	var next_index := _next_unit_index()
	var next_unit: Dictionary = repo.get_unit(next_index)
	var next_title := String(next_unit.get("title", "开始学习"))
	if next_title.length() > 24:
		next_title = next_title.substr(0, 22) + "…"
	var track_done := _track_completed_count()
	ui.label(screen_root, "freeCodeCamp 中文课程 · 离线版", Rect2(30, 70, 580, 26), 15, ui.GREEN)
	ui.label(screen_root, repo.track_title, Rect2(30, 98, 580, 38), 27, ui.TEXT)
	ui.label(screen_root, "切换课程 →", Rect2(400, 74, 210, 26), 15, ui.GOLD, 2)
	ui.progress_bar(screen_root, Rect2(30, 142, 580, 6), float(track_done) / float(max(1, repo.unit_count())), ui.GOLD)
	var items := [
		{"text": "继续学习 · " + next_title, "action": "continue", "enabled": true},
		{"text": "课程目录 · %d 个模块" % repo.module_count(), "action": "modules", "enabled": true},
		{"text": "切换课程 · JavaScript / Python", "action": "tracks", "enabled": true},
		{"text": "随机测验 · 从已学课程抽题", "action": "random_quiz", "enabled": not _question_pool().empty()},
		{"text": "操作说明", "action": "controls", "enabled": true},
		{"text": "清除学习记录", "action": "reset", "enabled": true},
	]
	_build_menu(items, Rect2(44, 160, 552, 40), 44, 0)
	ui.label(screen_root, "数据来自 freeCodeCamp 官方中文课程；学习记录只保存在本机。", Rect2(44, 424, 552, 20), 12, ui.MUTED, 1)


func _track_completed_count() -> int:
	var count := 0
	var track: String = String(repo.track_id)
	var prefix: String = track + "::"
	for unit_id in progress.data.get("completed", {}):
		if String(unit_id).begins_with(prefix):
			count += 1
	return count


func _show_tracks() -> void:
	_clear_screen()
	screen = "tracks"
	title_text = "切换课程"
	footer_text = "上下键 选择   A 切换   B 返回首页"
	ui.label(screen_root, "选择要学习的编程语言", Rect2(30, 70, 580, 32), 20, ui.GREEN)
	var items := []
	for index in range(repo.track_count()):
		var track: Dictionary = repo.get_track(index)
		var badge := String(track.get("badge", ""))
		var track_id := String(track.get("id", ""))
		var status := "当前" if track_id == repo.track_id else ""
		items.append({
			"text": "%s  %s" % [badge, String(track.get("title", ""))],
			"status": status,
			"action": "track",
			"index": index,
			"enabled": true,
		})
	_build_menu(items, Rect2(44, 130, 552, 54), 66, 0)
	ui.label(screen_root, "两个课程共用一本书架；学习进度各自独立保存。", Rect2(44, 340, 552, 44), 14, ui.MUTED, 0, true)


func _next_unit_index() -> int:
	var saved_id: String = progress.current_unit_id()
	var index: int = repo.index_of_unit_id(saved_id)
	if index >= 0 and not progress.is_completed(String(repo.get_unit(index).get("id", ""))):
		return index
	for i in range(repo.unit_count()):
		if not progress.is_completed(String(repo.get_unit(i).get("id", ""))):
			return i
	return 0


func _show_modules() -> void:
	_clear_screen()
	screen = "modules"
	title_text = "课程目录"
	footer_text = "上下键 选择   A 进入   B 首页   左右键 翻页"
	var modules: Array = []
	for index in range(repo.module_count()):
		modules.append(repo.get_module(index))
	var start := module_page * PAGE_SIZE
	var items := []
	for index in range(start, min(start + PAGE_SIZE, modules.size())):
		var module: Dictionary = modules[index]
		var module_id := String(module.get("id", ""))
		var bucket: Array = repo.units_for_module(module_id)
		var done := 0
		for unit in bucket:
			if progress.is_completed(String(unit.get("id", ""))):
				done += 1
		items.append({
			"text": "%02d  %s" % [index + 1, String(module.get("title", ""))],
			"status": "%d/%d" % [done, bucket.size()],
			"action": "module",
			"index": index,
			"enabled": true,
		})
	_build_menu(items, Rect2(28, 66, 584, 36), 38, 0)
	ui.label(screen_root, "第 %d / %d 页" % [module_page + 1, max(1, int(ceil(float(modules.size()) / float(PAGE_SIZE))))], Rect2(420, 412, 192, 24), 14, ui.MUTED, 2)


func _show_units() -> void:
	_clear_screen()
	screen = "units"
	title_text = "课程列表"
	footer_text = "上下键 选择   A 进入   B 返回目录   左右键 翻页"
	var module: Dictionary = repo.get_module(_module_index_by_id(current_module_id))
	var bucket: Array = repo.units_for_module(current_module_id)
	var start := unit_page * PAGE_SIZE
	var items := []
	for index in range(start, min(start + PAGE_SIZE, bucket.size())):
		var unit: Dictionary = bucket[index]
		var unit_id := String(unit.get("id", ""))
		var status := "已学" if progress.is_completed(unit_id) else ("待学" if true else "")
		items.append({
			"text": "%02d  %s" % [index + 1, String(unit.get("title", ""))],
			"status": status,
			"action": "unit",
			"index": repo.index_of_unit_id(unit_id),
			"enabled": true,
		})
	_build_menu(items, Rect2(28, 66, 584, 36), 38, 0)
	ui.label(screen_root, String(module.get("title", "")), Rect2(28, 412, 300, 24), 14, ui.MUTED)
	ui.label(screen_root, "第 %d / %d 页" % [unit_page + 1, max(1, int(ceil(float(bucket.size()) / float(PAGE_SIZE))))], Rect2(420, 412, 192, 24), 14, ui.MUTED, 2)


func _module_index_by_id(module_id: String) -> int:
	for index in range(repo.module_count()):
		if String(repo.get_module(index).get("id", "")) == module_id:
			return index
	return 0


func _open_unit(index: int) -> void:
	var unit: Dictionary = repo.get_unit(index)
	if unit.empty():
		return
	current_unit_index = index
	current_module_id = String(unit.get("moduleId", ""))
	progress.set_current_unit(String(unit.get("id", "")))
	body_pages = _paginate_body(unit.get("body", []))
	body_page = 0
	quiz_items = unit.get("questions", []).duplicate(true)
	quiz_index = 0
	quiz_correct = 0
	quiz_state = "playing"
	quiz_result = {}
	_show_reader()


func _paginate_body(items: Array) -> Array:
	var pages: Array = []
	var current: Array = []
	var used := 0
	for item in items:
		var entry: Dictionary = item
		var text := String(entry.get("text", ""))
		var cost := text.length() + (60 if String(entry.get("kind", "")) == "code" else 20)
		if not current.empty() and used + cost > READER_CHARS:
			pages.append(current)
			current = []
			used = 0
		current.append({"kind": String(entry.get("kind", "text")), "text": text})
		used += cost
	if not current.empty():
		pages.append(current)
	if pages.empty():
		pages.append([{"kind": "text", "text": "这一课没有阅读内容，可以直接进入练习。"}])
	return pages


func _show_reader() -> void:
	_clear_screen()
	screen = "reader"
	title_text = "阅读"
	footer_text = "左右键 翻页   A 下一项/开始练习   B 返回   X 跳到练习"
	var unit: Dictionary = repo.get_unit(current_unit_index)
	if unit.empty():
		_show_home()
		return
	title_text = String(unit.get("title", "阅读")).substr(0, 22)
	var page_items: Array = body_pages[body_page] if body_page < body_pages.size() else []
	ui.label(screen_root, String(unit.get("moduleTitle", "")), Rect2(24, 64, 400, 24), 14, ui.MUTED)
	ui.label(screen_root, "第 %d / %d 页" % [body_page + 1, body_pages.size()], Rect2(430, 64, 186, 24), 14, ui.GOLD, 2)
	var y := 96.0
	for entry in page_items:
		var kind := String(entry.get("kind", "text"))
		var text := String(entry.get("text", ""))
		if kind == "heading":
			ui.label(screen_root, text, Rect2(28, y, 584, 30), 20, ui.GOLD, 0, true)
			y += 36
		elif kind == "code":
			ui.panel(screen_root, Rect2(26, y, 588, 62), Color("0d1617"), ui.LINE, 6)
			ui.label(screen_root, text.substr(0, 150), Rect2(36, y + 4, 568, 54), 13, ui.BLUE, 0, true, ui.ipa_font(13))
			y += 68
		else:
			ui.label(screen_root, text, Rect2(28, y, 584, 74), 17, ui.TEXT, 0, true)
			y += 80
		if y > 424:
			break


func _reader_done() -> void:
	if quiz_items.empty():
		var unit: Dictionary = repo.get_unit(current_unit_index)
		progress.complete_reading(String(unit.get("id", "")))
		_show_simple_result("阅读完成", "这一课没有配套练习题，已记入学习进度。", 0, 0)
		return
	quiz_index = 0
	quiz_correct = 0
	quiz_state = "playing"
	quiz_selected = -1
	_show_quiz()


func _show_quiz() -> void:
	_clear_screen()
	screen = "quiz"
	title_text = "练习"
	footer_text = "上下键 选择   A 确认   B 返回   Y 查看解析"
	if quiz_state == "result":
		_build_quiz_result()
		return
	if quiz_index >= quiz_items.size():
		_finish_quiz()
		return
	var item: Dictionary = quiz_items[quiz_index]
	var options: Array = item.get("options", [])
	ui.label(screen_root, "第 %d / %d 题" % [quiz_index + 1, quiz_items.size()], Rect2(28, 64, 584, 24), 15, ui.GOLD, 2)
	ui.label(screen_root, String(item.get("text", "")), Rect2(40, 96, 560, 96), 20, ui.TEXT, 0, true)
	var items := []
	for index in range(options.size()):
		items.append({"text": "%d. %s" % [index + 1, String(options[index])], "action": "answer", "index": index, "enabled": true})
	_build_menu(items, Rect2(44, 208, 552, 42), 48, 0)
	if quiz_state == "feedback":
		_show_feedback(item)


func _show_feedback(item: Dictionary) -> void:
	var correct := int(item.get("answer", 0))
	var options: Array = item.get("options", [])
	var answer_text: String = String(options[correct]) if correct >= 0 and correct < options.size() else ""
	var panel_color := Color("14241f") if quiz_selected == correct else Color("2a2220")
	ui.panel(screen_root, Rect2(40, 316, 560, 112), panel_color, ui.GREEN if quiz_selected == correct else ui.RED, 12)
	ui.label(screen_root, "答对了！" if quiz_selected == correct else "正确答案：%s" % String(answer_text), Rect2(56, 324, 528, 34), 20, ui.GREEN if quiz_selected == correct else ui.RED, 0, true)
	var feedback := String(item.get("feedback", ""))
	if feedback != "":
		ui.label(screen_root, feedback.substr(0, 100), Rect2(56, 366, 528, 52), 15, ui.MUTED, 0, true)


func _answer_question(index: int) -> void:
	if quiz_state != "playing" or quiz_index >= quiz_items.size():
		return
	var item: Dictionary = quiz_items[quiz_index]
	quiz_selected = index
	if index == int(item.get("answer", -1)):
		quiz_correct += 1
	quiz_state = "feedback"
	_show_quiz()


func _finish_quiz() -> void:
	var unit: Dictionary = repo.get_unit(current_unit_index)
	var unit_id := String(unit.get("id", ""))
	var total := quiz_items.size()
	quiz_result = {"correct": quiz_correct, "total": total, "first": not progress.is_completed(unit_id)}
	progress.record_result(unit_id, quiz_correct, total)
	quiz_state = "result"
	_show_quiz()


func _build_quiz_result() -> void:
	var total := int(quiz_result.get("total", 0))
	var correct := int(quiz_result.get("correct", 0))
	var score := 0 if total == 0 else int(round(100.0 * float(correct) / float(total)))
	var unit: Dictionary = repo.get_unit(current_unit_index)
	var items := [
		{"text": "再看一遍讲解", "action": "reader", "enabled": true},
		{"text": "重新练习", "action": "retry", "enabled": true},
		{"text": "回到课程列表", "action": "units", "enabled": true},
	]
	if progress.completed_count() < repo.unit_count():
		items.append({"text": "下一课", "action": "next_unit", "enabled": true})
	items.append({"text": "回到首页", "action": "home", "enabled": true})
	_build_menu(items, Rect2(180, 226, 360, 38), 42, 0)
	ui.label(screen_root, "%d%%" % score, Rect2(40, 86, 200, 70), 46, ui.GOLD if score >= 60 else ui.RED)
	ui.label(screen_root, "答对 %d / %d" % [correct, total], Rect2(250, 92, 350, 40), 22, ui.TEXT)
	ui.label(screen_root, String(unit.get("title", "")).substr(0, 34), Rect2(250, 136, 350, 30), 16, ui.MUTED)
	if bool(quiz_result.get("first", false)):
		ui.label(screen_root, "首次完成 +10 XP", Rect2(250, 172, 350, 30), 17, ui.GREEN)


func _show_simple_result(title: String, detail: String, correct: int, total: int) -> void:
	_clear_screen()
	screen = "result"
	title_text = title
	footer_text = "A 确认   B 返回课程列表"
	ui.label(screen_root, detail, Rect2(50, 130, 540, 60), 23, ui.GREEN, 1, true)
	_build_menu([
		{"text": "回到课程列表", "action": "units", "enabled": true},
		{"text": "下一课", "action": "next_unit", "enabled": true},
		{"text": "回到首页", "action": "home", "enabled": true},
	], Rect2(180, 230, 360, 44), 50, 0)


func _question_pool() -> Array:
	var pool: Array = []
	for unit in repo.units:
		if not progress.is_completed(String(unit.get("id", ""))):
			continue
		for question in unit.get("questions", []):
			pool.append(question)
	return pool


func _switch_track(index: int) -> void:
	if not repo.select_track_id(String(repo.get_track(index).get("id", ""))):
		return
	module_page = 0
	unit_page = 0
	current_module_id = ""
	current_unit_index = -1
	_show_home()


func _start_random_quiz() -> void:
	var pool := _question_pool()
	if pool.empty():
		_show_toast("先学完几课，再来随机测验")
		return
	pool.shuffle()
	quiz_items = []
	for index in range(min(10, pool.size())):
		quiz_items.append(pool[index])
	current_unit_index = max(0, current_unit_index)
	quiz_index = 0
	quiz_correct = 0
	quiz_state = "playing"
	quiz_result = {"random": true}
	_show_quiz()


func _show_controls() -> void:
	_clear_screen()
	screen = "controls"
	title_text = "操作说明"
	footer_text = "B 返回首页"
	var rows := [
		["十字键 / 左摇杆", "上下选择，左右翻页"],
		["A", "确认 / 下一页 / 下一题"],
		["B", "返回上一级"],
		["X / L1", "跳到练习 / 上一页"],
		["Y / R1", "查看解析 / 下一页"],
		["Select", "回到首页"],
		["Start", "退出到 PortMaster"],
	]
	for index in range(rows.size()):
		var y := 76 + index * 46
		ui.panel(screen_root, Rect2(48, y, 544, 38), ui.PANEL, ui.LINE, 8)
		ui.label(screen_root, rows[index][0], Rect2(64, y + 3, 210, 32), 17, ui.GOLD)
		ui.label(screen_root, rows[index][1], Rect2(280, y + 3, 300, 32), 17, ui.TEXT)


func _show_reset_confirm() -> void:
	_clear_screen()
	screen = "reset"
	title_text = "确认清除"
	footer_text = "A 确认清除   B 取消"
	ui.panel(screen_root, Rect2(100, 150, 440, 190), Color("2a2220"), ui.RED, 16)
	ui.label(screen_root, "确定清除全部学习记录？", Rect2(120, 178, 400, 50), 23, ui.TEXT, 1)
	ui.label(screen_root, "此操作不可撤销", Rect2(120, 232, 400, 32), 17, ui.MUTED, 1)
	ui.label(screen_root, "A 确定    B 取消", Rect2(120, 288, 400, 32), 19, ui.GOLD, 1)


func _build_menu(items: Array, rect: Rect2, spacing: float, columns: int) -> void:
	for index in range(items.size()):
		var item: Dictionary = items[index]
		var y: float = rect.position.y + index * spacing if spacing > 0 else rect.position.y + index * (rect.size.y + 8)
		var panel := ui.panel(screen_root, Rect2(rect.position.x, y, rect.size.x, rect.size.y), ui.PANEL, ui.LINE, 10)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.connect("gui_input", self, "_on_menu_gui_input", [index])
		var status: String = String(item.get("status", ""))
		var status_width: float = ui.font(14).get_string_size(status).x + 8 if status != "" else 0
		ui.label(panel, String(item.get("text", "")), Rect2(16, 3, rect.size.x - status_width - 24, rect.size.y - 6), 17 if rect.size.y >= 40 else 15, ui.TEXT, 0, true)
		if status != "":
			ui.label(panel, status, Rect2(rect.size.x - status_width - 8, 3, status_width, rect.size.y - 6), 13, ui.GREEN if status == "已学" else ui.MUTED, 2)
		if not bool(item.get("enabled", true)):
			panel.modulate = Color(1, 1, 1, 0.4)
		menu_panels.append(panel)
		menu_meta.append(item)
	_refresh_menu()


func _refresh_menu() -> void:
	for index in range(menu_panels.size()):
		var selected := index == menu_index
		var background_color: Color = ui.PANEL_LIGHT if selected else ui.PANEL
		var border_color: Color = ui.GOLD if selected else ui.LINE
		menu_panels[index].add_stylebox_override("panel", ui.style(background_color, border_color, 10, 2 if selected else 1))
		if bool(menu_meta[index].get("enabled", true)):
			menu_panels[index].modulate = Color(1, 1, 1, 1)


func _on_menu_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
		menu_index = index
		_refresh_menu()
		_activate_menu()


func _navigate(direction: int) -> void:
	if menu_panels.empty():
		return
	if screen == "modules":
		var start := module_page * PAGE_SIZE
		var count: int = min(PAGE_SIZE, repo.module_count() - start)
		if direction < 0 and menu_index == 0 and module_page > 0:
			module_page -= 1
			_show_modules()
			menu_index = max(0, min(PAGE_SIZE, repo.module_count() - module_page * PAGE_SIZE) - 1)
			_refresh_menu()
			return
		if direction > 0 and menu_index == count - 1 and (module_page + 1) * PAGE_SIZE < repo.module_count():
			module_page += 1
			_show_modules()
			return
	if screen == "units":
		var bucket: Array = repo.units_for_module(current_module_id)
		var start2 := unit_page * PAGE_SIZE
		var count2: int = min(PAGE_SIZE, bucket.size() - start2)
		if direction < 0 and menu_index == 0 and unit_page > 0:
			unit_page -= 1
			_show_units()
			menu_index = max(0, min(PAGE_SIZE, bucket.size() - unit_page * PAGE_SIZE) - 1)
			_refresh_menu()
			return
		if direction > 0 and menu_index == count2 - 1 and (unit_page + 1) * PAGE_SIZE < bucket.size():
			unit_page += 1
			_show_units()
			return
	menu_index = posmod(menu_index + direction, menu_panels.size())
	_refresh_menu()


func _page_step(direction: int) -> void:
	match screen:
		"reader":
			var next_page := body_page + direction
			if next_page >= 0 and next_page < body_pages.size():
				body_page = next_page
				_show_reader()
		"modules":
			var max_page := max(0, int(ceil(float(repo.module_count()) / float(PAGE_SIZE))) - 1)
			var next_page2 := clamp(module_page + direction, 0, max_page)
			if next_page2 != module_page:
				module_page = next_page2
				_show_modules()
		"units":
			var bucket: Array = repo.units_for_module(current_module_id)
			var max_page2 := max(0, int(ceil(float(bucket.size()) / float(PAGE_SIZE))) - 1)
			var next_page3 := clamp(unit_page + direction, 0, max_page2)
			if next_page3 != unit_page:
				unit_page = next_page3
				_show_units()


func _accept() -> void:
	match screen:
		"reader":
			if body_page + 1 < body_pages.size():
				body_page += 1
				_show_reader()
			else:
				_reader_done()
		"quiz":
			if quiz_state == "feedback":
				quiz_index += 1
				quiz_selected = -1
				quiz_state = "playing"
				_show_quiz()
			elif not menu_panels.empty():
				_activate_menu()
		"reset":
			progress.reset_game()
			_show_home()
		_:
			if not menu_panels.empty():
				_activate_menu()


func _activate_menu() -> void:
	if menu_index < 0 or menu_index >= menu_meta.size():
		return
	var item: Dictionary = menu_meta[menu_index]
	if not bool(item.get("enabled", true)):
		return
	match String(item.get("action", "")):
		"continue": _open_unit(_next_unit_index())
		"tracks": _show_tracks()
		"track": _switch_track(int(item.get("index", 0)))
		"modules": _show_modules()
		"module":
			var module: Dictionary = repo.get_module(int(item.get("index", 0)))
			current_module_id = String(module.get("id", ""))
			unit_page = 0
			_show_units()
		"unit": _open_unit(int(item.get("index", 0)))
		"answer": _answer_question(int(item.get("index", 0)))
		"reader": _show_reader()
		"retry":
			quiz_index = 0
			quiz_correct = 0
			quiz_state = "playing"
			quiz_selected = -1
			_show_quiz()
		"units": _show_units()
		"next_unit": _open_unit(min(repo.unit_count() - 1, current_unit_index + 1))
		"random_quiz": _start_random_quiz()
		"controls": _show_controls()
		"reset": _show_reset_confirm()
		"home": _show_home()


func _back() -> void:
	match screen:
		"reader": _show_units()
		"units": _show_modules()
		"quiz":
			if quiz_state == "feedback":
				quiz_state = "playing"
				quiz_selected = -1
				_show_quiz()
			else:
				_show_units()
		"modules", "tracks", "controls", "result", "reset": _show_home()
		"home": pass


func _replay() -> void:
	if screen == "reader":
		_reader_done()
	elif screen == "quiz" and quiz_state == "feedback":
		_hint()


func _hint() -> void:
	if screen == "quiz" and quiz_state == "feedback":
		var item: Dictionary = quiz_items[quiz_index]
		var feedback := String(item.get("feedback", ""))
		if feedback != "":
			_show_toast(feedback.substr(0, 40))


func _learning_menu() -> void:
	if screen != "home":
		_show_home()


func _show_toast(text: String) -> void:
	toast_text = text
	toast_time = 2.6
	_sync_chrome()
