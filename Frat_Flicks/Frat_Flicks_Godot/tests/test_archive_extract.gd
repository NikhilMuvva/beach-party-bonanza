extends SceneTree
## Regression test for ProjectDialog's ZIP extraction algorithm in Godot 4.5.
## Uses make_dir (not recursive) and never creates file parents implicitly.
## Run with -- --archive=/absolute/file.zip --destination=/fresh/folder

func _initialize() -> void:
	var archive_path := ""
	var destination := ""
	var expected_failures := 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--archive="):
			archive_path = argument.trim_prefix("--archive=")
		elif argument.begins_with("--destination="):
			destination = argument.trim_prefix("--destination=")
		elif argument.begins_with("--expect-failures="):
			expected_failures = int(argument.trim_prefix("--expect-failures="))
	if archive_path.is_empty() or destination.is_empty() or DirAccess.dir_exists_absolute(destination):
		push_error("Provide an archive and a new, nonexistent destination")
		quit(1)
		return
	var archive := ZIPReader.new()
	if archive.open(archive_path) != OK:
		quit(1)
		return
	var entries := archive.get_files()
	var zip_root := ""
	for entry in entries:
		if entry.get_file() == "project.godot":
			zip_root = entry.get_base_dir()
			break
	if zip_root.is_empty():
		push_error("Missing project.godot")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(destination)
	var failed: Array[String] = []
	var extracted := 0
	var directories := 0
	for entry in entries:
		var relative := entry.trim_prefix(zip_root)
		if relative.is_empty():
			continue
		elif relative.ends_with("/"):
			DirAccess.make_dir_absolute(destination.path_join(relative))
			directories += 1
		else:
			var file := FileAccess.open(destination.path_join(relative), FileAccess.WRITE)
			if file == null:
				failed.append(relative)
			else:
				file.store_buffer(archive.read_file(entry))
				file.close()
				extracted += 1
	archive.close()
	print("ZIP_EXTRACTION ", JSON.stringify({"extracted": extracted, "directories": directories, "failed_count": failed.size(), "first_failures": failed.slice(0, 3)}))
	quit(0 if failed.size() == expected_failures else 1)
