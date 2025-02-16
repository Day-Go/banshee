extends PanelContainer

@onready var title_label: Label = %TitleLabel
@onready var datetime_label: Label = %DateTimeLabel
var convo_id: int


func _ready() -> void:
	pass


func set_data(data: Dictionary) -> void:
	convo_id = data["id"]
	title_label.text = data["title"]
	datetime_label.text = data["created_at"]
