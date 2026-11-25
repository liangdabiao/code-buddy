extends SceneTree

var app


func _init() -> void:
	var packed := load("res://scenes/Main.tscn")
	app = packed.instance()
	get_root().add_child(app)
	yield(self, "idle_frame")
	yield(_shot("01_home"), "completed")

	app._show_modules()
	yield(self, "idle_frame")
	yield(_shot("02_modules"), "completed")

	app.module_page = 1
	app._show_modules()
	yield(self, "idle_frame")
	yield(_shot("03_modules_p2"), "completed")

	var module: Dictionary = app.repo.get_module(0)
	app.current_module_id = String(module.get("id", ""))
	app._show_units()
	yield(self, "idle_frame")
	yield(_shot("04_units"), "completed")

	app._open_unit(0)
	yield(self, "idle_frame")
	yield(_shot("05_reader"), "completed")

	var pages: int = app.body_pages.size()
	app.body_page = max(0, pages - 1)
	app._show_reader()
	yield(self, "idle_frame")
	yield(_shot("06_reader_last"), "completed")

	var quiz_index := -1
	for i in range(min(30, app.repo.unit_count())):
		if not app.repo.get_unit(i).get("questions", []).empty():
			quiz_index = i
			break
	if quiz_index >= 0:
		app._open_unit(quiz_index)
		yield(self, "idle_frame")
		app._reader_done()
		yield(self, "idle_frame")
		yield(_shot("07_quiz"), "completed")
		app._answer_question(0)
		yield(self, "idle_frame")
		yield(_shot("08_feedback"), "completed")

	app._show_controls()
	yield(self, "idle_frame")
	yield(_shot("09_controls"), "completed")

	# Track switching screen + Python track.
	app._show_tracks()
	yield(self, "idle_frame")
	yield(_shot("10_tracks"), "completed")

	app._switch_track(1)
	yield(self, "idle_frame")
	yield(_shot("11_python_home"), "completed")

	app._show_modules()
	yield(self, "idle_frame")
	yield(_shot("12_python_modules"), "completed")

	var pymod: Dictionary = app.repo.get_module(0)
	app.current_module_id = String(pymod.get("id", ""))
	app._show_units()
	yield(self, "idle_frame")
	yield(_shot("13_python_units"), "completed")

	app._open_unit(0)
	yield(self, "idle_frame")
	yield(_shot("14_python_reader"), "completed")

	print("RENDER_DONE units=", app.repo.unit_count(), " modules=", app.repo.module_count())
	quit(0)


func _shot(name: String) -> void:
	yield(self, "idle_frame")
	var img := get_root().get_texture().get_data()
	img.flip_y()
	img.lock()
	img.save_png("res://.build/screenshots/" + name + ".png")
	img.unlock()
