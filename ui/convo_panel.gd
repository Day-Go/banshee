extends PanelContainer

@onready var collapse_button: TextureButton = %CollapseButton


func _ready() -> void:
	collapse_button.pressed.connect(_on_collapse_button_pressed)


func _on_collapse_button_pressed() -> void:
	# visible = false
	pass
