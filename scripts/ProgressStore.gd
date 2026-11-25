extends Node

signal changed

const SAVE_PATH := "user://code_buddy_profile.json"
const BACKUP_PATH := "user://code_buddy_profile.bak"
const TEMP_PATH := "user://code_buddy_profile.tmp"

var data: Dictionary = default_data()


func _ready() -> void:
	load_game()


func default_data() -> Dictionary:
	return {
		"version": 1,
		"completed": {},
		"scores": {},
		"currentUnit": "",
		"xp": 0,
		"streak": 0,
		"lastStudyDay": "",
		"history": [],
	}


func load_game() -> void:
	var file := File.new()
	for path in [SAVE_PATH, BACKUP_PATH]:
		if file.file_exists(path) and file.open(path, File.READ) == OK:
			var parsed = JSON.parse(file.get_as_text()).result
			file.close()
			if parsed is Dictionary and int(parsed.get("version", 0)) == 1:
				data = _merge_defaults(parsed)
				return
	emit_signal("changed")


func _merge_defaults(saved: Dictionary) -> Dictionary:
	var merged := default_data()
	for key in saved:
		merged[key] = saved[key]
	return merged


func save_game() -> void:
	var file := File.new()
	if file.open(TEMP_PATH, File.WRITE) != OK:
		push_error("Could not write learning profile")
		return
	file.store_string(JSON.print(data))
	file.close()
	var directory := Directory.new()
	if file.file_exists(SAVE_PATH):
		directory.rename(SAVE_PATH, BACKUP_PATH)
	if directory.rename(TEMP_PATH, SAVE_PATH) != OK:
		if file.file_exists(BACKUP_PATH):
			directory.rename(BACKUP_PATH, SAVE_PATH)
		push_error("Could not replace learning profile")
		return
	emit_signal("changed")


func set_current_unit(unit_id: String) -> void:
	data.currentUnit = unit_id
	save_game()


func current_unit_id() -> String:
	return String(data.get("currentUnit", ""))


func is_completed(unit_id: String) -> bool:
	return bool(data.get("completed", {}).get(unit_id, false))


func completed_count() -> int:
	return data.get("completed", {}).size()


func best_score(unit_id: String) -> int:
	return int(data.get("scores", {}).get(unit_id, -1))


func record_result(unit_id: String, correct: int, total: int) -> void:
	if unit_id == "":
		return
	var score := 0 if total <= 0 else int(round(100.0 * float(correct) / float(total)))
	if is_completed(unit_id):
		if score > best_score(unit_id):
			data.scores[unit_id] = score
	else:
		data.completed[unit_id] = true
		data.scores[unit_id] = score
		data.xp = int(data.get("xp", 0)) + 10
	_update_streak()
	var history: Array = data.get("history", [])
	history.append({"unit": unit_id, "score": score, "day": _today()})
	if history.size() > 60:
		history = history.slice(history.size() - 60, history.size())
	data.history = history
	save_game()


func complete_reading(unit_id: String) -> void:
	if unit_id == "" or is_completed(unit_id):
		return
	data.completed[unit_id] = true
	data.scores[unit_id] = -1
	data.xp = int(data.get("xp", 0)) + 10
	_update_streak()
	save_game()


func _update_streak() -> void:
	var today := _today()
	if String(data.get("lastStudyDay", "")) == today:
		return
	data.lastStudyDay = today
	data.streak = int(data.get("streak", 0)) + 1


func _today() -> String:
	var time := OS.get_datetime()
	return "%04d-%02d-%02d" % [time.year, time.month, time.day]


func reset_game() -> void:
	data = default_data()
	save_game()
