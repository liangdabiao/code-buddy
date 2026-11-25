extends SceneTree

var app
var failures: Array = []


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		print("FAIL: ", label)


func _init() -> void:
	var packed := load("res://scenes/Main.tscn")
	app = packed.instance()
	get_root().add_child(app)
	yield(self, "idle_frame")

	_check(app.repo.track_count() == 2, "track count")
	_check(app.repo.track_id == "javascript", "default track is javascript")
	_check(app.repo.unit_count() > 200, "unit count")
	_check(app.repo.module_count() >= 30, "module count")
	var units_with_questions := 0
	var total_questions := 0
	for unit in app.repo.units:
		var q: Array = unit.get("questions", [])
		if not q.empty():
			units_with_questions += 1
		total_questions += q.size()
	_check(units_with_questions > 20, "units with questions")
	_check(total_questions >= 900, "question count")
	print("DATA units=", app.repo.unit_count(), " modules=", app.repo.module_count(),
		" quizUnits=", units_with_questions, " questions=", total_questions)

	# Navigate through module -> unit -> reading -> quiz -> result.
	app._show_modules()
	_check(app.screen == "modules", "modules screen")
	var module: Dictionary = app.repo.get_module(0)
	app.current_module_id = String(module.get("id", ""))
	app._show_units()
	_check(app.screen == "units", "units screen")

	var quiz_index := -1
	for i in range(min(30, app.repo.unit_count())):
		if not app.repo.get_unit(i).get("questions", []).empty():
			quiz_index = i
			break
	_check(quiz_index >= 0, "quiz unit exists")
	if quiz_index >= 0:
		app._open_unit(quiz_index)
		_check(app.screen == "reader", "reader screen")
		_check(app.body_pages.size() > 0, "reader pages")
		app._reader_done()
		_check(app.screen == "quiz", "quiz screen")
		var unit: Dictionary = app.repo.get_unit(quiz_index)
		var first: Dictionary = unit.questions[0]
		app._answer_question(int(first.get("answer", 0)))
		_check(app.quiz_state == "feedback", "feedback state")
		_check(app.quiz_correct == 1, "correct answer counted")
		# Finish all questions.
		var total: int = unit.questions.size()
		for i in range(total - 1):
			app._accept()
			var q: Dictionary = app.quiz_items[app.quiz_index]
			app._answer_question(int(q.get("answer", 0)))
		app._accept()
		_check(app.quiz_state == "result", "result state")
		_check(app.progress.completed_count() >= 1, "progress recorded")
		print("QUIZ total=", total, " correct=", app.quiz_correct,
			" score=", app.progress.best_score(String(unit.get("id", ""))))

	app._show_home()
	_check(app.screen == "home", "home after result")
	app._start_random_quiz()
	_check(app.quiz_items.size() > 0, "random quiz pool")
	app._show_controls()
	_check(app.screen == "controls", "controls screen")

	# Track switching: switch to Python, verify its data loads, then back.
	app._show_tracks()
	_check(app.screen == "tracks", "tracks screen")
	app._switch_track(1)
	_check(app.repo.track_id == "python", "switched to python")
	_check(app.repo.unit_count() > 150, "python unit count")
	_check(app.repo.module_count() >= 20, "python module count")
	app._show_home()
	_check(app.screen == "home", "home after track switch")
	app._switch_track(0)
	_check(app.repo.track_id == "javascript", "switched back to javascript")

	# Save/load round trip.
	app.progress.save_game()
	var snapshot: Dictionary = app.progress.data.duplicate(true)
	app.progress.data = app.progress.default_data()
	app.progress.load_game()
	_check(app.progress.completed_count() == int(snapshot.get("completed", {}).size()), "save/load")

	if failures.empty():
		print("SMOKE_OK failures=0")
	else:
		print("SMOKE_FAIL failures=", failures.size())
		for f in failures:
			print("  - ", f)
	quit(1 if not failures.empty() else 0)
