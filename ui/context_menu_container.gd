extends PanelContainer

@onready var file_menu: PopupMenu = %File
@onready var view_menu: PopupMenu = %View


func _ready() -> void:
	view_menu.index_pressed.connect(_on_view_index_pressed)
	file_menu.index_pressed.connect(_on_file_index_pressed)


func _on_view_index_pressed(index: int) -> void:
	print("view menu pressed at index %s" % index)
	print(view_menu.get_item_text(index))


func _on_file_index_pressed(index: int) -> void:
	var file_dialog := FileDialog.new()
	add_child(file_dialog)

	file_dialog.access = FileDialog.ACCESS_FILESYSTEM  # Allow accessing the whole filesystem
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE  # Set to open file mode
	file_dialog.title = "Open a File"  # Set dialog title

	# Optional: Set filters for specific file types
	file_dialog.filters = ["*.txt ; Text Files", "*.png ; PNG Images"]

	# Connect the file_selected signal
	file_dialog.file_selected.connect(_on_file_selected)

	file_dialog.popup_centered(Vector2(800, 600))


func _on_file_selected(path):
	print("Selected file: ", path)
