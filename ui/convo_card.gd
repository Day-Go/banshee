extends PanelContainer

@onready var title_label: Label = %TitleLabel
@onready var datetime_label: Label = %DateTimeLabel
var convo_id: int

var default_style: StyleBoxFlat
var hover_style: StyleBoxFlat


func _ready() -> void:
	default_style = get_theme_stylebox("panel").duplicate()
	hover_style = default_style.duplicate()

	# Set border width in both styles to prevent jittering
	for style in [default_style, hover_style]:
		style.border_width_bottom = 2
		style.border_width_top = 2
		style.border_width_left = 2
		style.border_width_right = 2

	# Default style has transparent border
	default_style.border_color = Color(0, 0, 0, 0)

	# Hover style modifications
	hover_style.bg_color = default_style.bg_color.lightened(0.1)
	hover_style.border_color = Color(0.5, 0.5, 0.5)

	# Apply the default style initially
	add_theme_stylebox_override("panel", default_style)


func set_title(title: String) -> void:
	title_label.text = title


func set_data(data: Dictionary) -> void:
	convo_id = data["id"]
	title_label.text = data["title"]
	datetime_label.text = data["created_at"]


func _on_mouse_entered() -> void:
	add_theme_stylebox_override("panel", hover_style)


func _on_mouse_exited() -> void:
	add_theme_stylebox_override("panel", default_style)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			SignalBus.convo_selected.emit(convo_id)
			print("card clicked for convo %s" % convo_id)
