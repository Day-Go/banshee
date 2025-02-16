extends PanelContainer

@onready var convo_card_scene := preload("res://ui/convo_card.tscn")
@onready var collapse_button: TextureButton = %CollapseButton
@onready var convo_container: VBoxContainer = %ConvoContainer

var convos := []
var convo_cards := {}


func _ready() -> void:
	collapse_button.pressed.connect(_on_collapse_button_pressed)
	SqliteClient.convo_created.connect(_on_convo_created)
	SqliteClient.convo_title_updated.connect(_on_convo_title_updated)

	convos = SqliteClient.get_n_latest_convos(10)
	for convo in convos:
		create_convo_card(convo)


func _on_collapse_button_pressed() -> void:
	# visible = false
	pass


func _on_convo_created(convo: Dictionary) -> void:
	var convo_card = create_convo_card(convo)
	convo_container.move_child(convo_card, 1)


func _on_convo_title_updated(convo_id: int, title: String):
	convo_cards[convo_id].set_title(title)


func create_convo_card(convo: Dictionary) -> PanelContainer:
	var convo_card = convo_card_scene.instantiate()
	convo_container.add_child(convo_card)
	convo_card.set_data(convo)
	convo_cards[convo["id"]] = convo_card
	return convo_card
