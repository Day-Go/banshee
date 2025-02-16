extends PanelContainer

@onready var convo_card_scene := preload("res://ui/convo_card.tscn")
@onready var collapse_button: TextureButton = %CollapseButton
@onready var convo_container: VBoxContainer = %ConvoContainer

var convos := Array()


func _ready() -> void:
	collapse_button.pressed.connect(_on_collapse_button_pressed)
	SqliteClient.convo_created.connect(_on_convo_created)
	SqliteClient.convo_title_updated.connect(_on_convo_title_updated)

	convos = SqliteClient.get_n_latest_convos(10)
	for convo in convos:
		print(convo)
		create_convo_card(convo)


func _on_collapse_button_pressed() -> void:
	# visible = false
	pass


func _on_convo_created(convo_id: int, title: String):
	pass


func _on_convo_title_updated(convo_id: int, title: String):
	pass


func create_convo_card(convo: Dictionary) -> void:
	var convo_card = convo_card_scene.instantiate()
	convo_container.add_child(convo_card)
	convo_card.set_data(convo)
