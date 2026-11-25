extends Node

const DATA_PATH := "res://data/curriculum.json"

var meta: Dictionary = {}
var tracks: Array = []
var track_id: String = ""
var track_title: String = ""
var chapters: Array = []
var units: Array = []
var module_units: Dictionary = {}


func _ready() -> void:
	_load()


func _load() -> void:
	var file := File.new()
	if file.open(DATA_PATH, File.READ) != OK:
		push_error("Cannot open curriculum data: " + DATA_PATH)
		return
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK or not parsed.result is Dictionary:
		push_error("Invalid curriculum JSON")
		return
	meta = parsed.result.get("meta", {})
	tracks = parsed.result.get("tracks", [])
	if tracks.empty():
		# Backward compatibility with the single-track javascript-buddy pack.
		tracks = [{"id": "javascript", "title": "JavaScript 编程", "chapters": parsed.result.get("chapters", [])}]
	select_track(0)


func track_count() -> int:
	return tracks.size()


func get_track(index: int) -> Dictionary:
	if index < 0 or index >= tracks.size():
		return {}
	return tracks[index]


func select_track(index: int) -> void:
	var track: Dictionary = get_track(index)
	if track.empty():
		return
	track_id = String(track.get("id", ""))
	track_title = String(track.get("title", ""))
	chapters = track.get("chapters", [])
	_flatten()


func select_track_id(wanted: String) -> bool:
	for index in range(tracks.size()):
		if String(get_track(index).get("id", "")) == wanted:
			select_track(index)
			return true
	return false


func _flatten() -> void:
	units.clear()
	module_units.clear()
	for chapter in chapters:
		for module in chapter.get("modules", []):
			var module_id := String(module.get("id", ""))
			var bucket: Array = []
			for block in module.get("blocks", []):
				var unit := {
					"id": track_id + "::" + String(block.get("id", "")),
					"title": String(block.get("title", "")),
					"kind": String(block.get("kind", "")),
					"chapterTitle": String(chapter.get("title", "")),
					"moduleId": module_id,
					"moduleTitle": String(module.get("title", "")),
					"lessons": block.get("lessons", []),
				}
				unit["questions"] = _collect_questions(block.get("lessons", []))
				unit["body"] = _collect_body(block.get("lessons", []), unit.title)
				units.append(unit)
				bucket.append(unit)
			module_units[module_id] = bucket


func _collect_questions(lessons: Array) -> Array:
	var result: Array = []
	for lesson in lessons:
		for question in lesson.get("questions", []):
			var q: Dictionary = question.duplicate(true)
			q["options"] = _trim_options(q.get("options", []))
			q["answer"] = int(q.get("answer", 0))
			if q.options.size() >= 2 and q.answer >= 0 and q.answer < q.options.size():
				result.append(q)
	return result


func _trim_options(options: Array) -> Array:
	var result: Array = []
	for option in options:
		var text := String(option).strip_edges()
		if text.length() > 120:
			text = text.substr(0, 118) + "…"
		if text != "":
			result.append(text)
	return result


func _collect_body(lessons: Array, fallback_title: String) -> Array:
	var result: Array = []
	for lesson in lessons:
		var title := String(lesson.get("title", ""))
		if title == "":
			title = fallback_title
		result.append({"kind": "heading", "text": title})
		for paragraph in lesson.get("body", []):
			var text := String(paragraph).strip_edges()
			if text != "":
				result.append({"kind": "text", "text": text})
		for code in lesson.get("code", []):
			var snippet := String(code).strip_edges()
			if snippet != "":
				result.append({"kind": "code", "text": snippet})
	return result


func unit_count() -> int:
	return units.size()


func get_unit(index: int) -> Dictionary:
	if index < 0 or index >= units.size():
		return {}
	return units[index]


func index_of_unit_id(unit_id: String) -> int:
	for index in range(units.size()):
		if String(units[index].get("id", "")) == unit_id:
			return index
	return -1


func module_count() -> int:
	var count := 0
	for chapter in chapters:
		count += chapter.get("modules", []).size()
	return count


func get_module(index: int) -> Dictionary:
	var current := 0
	for chapter in chapters:
		for module in chapter.get("modules", []):
			if current == index:
				return module
			current += 1
	return {}


func units_for_module(module_id: String) -> Array:
	return module_units.get(module_id, [])
