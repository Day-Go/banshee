extends PanelContainer
class_name CodeBlockContainer

@onready var code_area: RichTextLabel = %CodeArea
@onready var copy_button: Button = %CopyButton
@onready var language_label: Label = %LanguageLabel


func _ready() -> void:
	copy_button.pressed.connect(_on_copy_button_pressed)
	code_area.fit_content = true


func set_code(code: String) -> void:
	code_area.text = code


func get_code_area() -> RichTextLabel:
	return code_area


func set_language(language: String) -> void:
	language_label.text = language


func _on_copy_button_pressed() -> void:
	DisplayServer.clipboard_set(code_area.get_parsed_text())
	print("Copied to clipboard")
