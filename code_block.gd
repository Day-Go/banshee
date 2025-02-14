extends PanelContainer
class_name CodeBlockContainer

@onready var code_area: RichTextLabel = %CodeArea
@onready var copy_button: Button = %CopyButton
@onready var language_label: Label = %LanguageLabel

func _ready() -> void:
	copy_button.pressed.connect(_on_copy_button_pressed)

func set_code(code: String) -> void:
	code_area.text = code

func set_language(language: String) -> void:
	language_label.text = language
	
func _on_copy_button_pressed() -> void:
	pass
