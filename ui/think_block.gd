extends PanelContainer
class_name ThinkBlockContainer

@onready var text_area: RichTextLabel = %TextArea


func _ready() -> void:
	text_area.fit_content = true
