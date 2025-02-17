extends PanelContainer

@onready var file_menu: PopupMenu = %File
@onready var view_menu: PopupMenu = %View


func _ready() -> void:
	view_menu.index_pressed.connect(_on_view_index_pressed)


func _on_view_index_pressed(index: int) -> void:
	print("view menu pressed at index %s" % index)
	print(view_menu.get_item_text(index))
