extends Node

@onready var message_scene = preload("res://ui/message.tscn")
@onready var code_block_container_scene = preload("res://ui/code_block.tscn")
@onready var scroll_container: ScrollContainer = %ScrollContainer
@onready var model_dropdown: OptionButton = %ModelDropdown
@onready var button: Button = %SendButton
@onready var input: TextEdit = %InputTextArea
@onready var output_container: VBoxContainer = %OutputContainer

enum Sender { USER, ASSISTANT }

var models := ["qwen2.5-coder:32b", "deepseek-r1:32b", "openthinker:32b", "olmo2:latest"]
var selected_model := "qwen2.5-coder:32b"

var buffer := ""
var write_target: RichTextLabel
var is_in_code_block := false
var partial_backtick_sequence := ""
var is_collecting_language := false
var partial_language := ""
var rich_text_label: RichTextLabel
var code_block := ""
var language := ""

var current_assistant_response := ""
var message: PanelContainer
var message_container: VBoxContainer
var convo_id: int = -1
var is_scrolling: bool = false
var convo_context := Array()


func _ready() -> void:
	button.pressed.connect(_on_button_pressed)

	LlmBackend.generation_started.connect(_on_generation_started)
	LlmBackend.chunk_processed.connect(_on_chunk_processed)
	LlmBackend.generation_finished.connect(_on_generation_finished)
	LlmBackend.embedding_finished.connect(_on_embedding_finished)
	SignalBus.convo_selected.connect(load_convo)

	input.text = "write hello world in python"

	model_dropdown.item_selected.connect(_on_model_selected)
	for model in models:
		model_dropdown.add_item(model)


func _input(event):
	if event is InputEventMouseButton:
		if (
			event.button_index == MOUSE_BUTTON_WHEEL_UP
			or event.button_index == MOUSE_BUTTON_WHEEL_DOWN
		):
			is_scrolling = true


func _on_model_selected(idx: int) -> void:
	selected_model = model_dropdown.get_item_text(idx)


func _on_generation_started() -> void:
	button.disabled = true


func _on_generation_finished() -> void:
	button.disabled = false
	is_scrolling = false

	convo_context.append({"assistant": current_assistant_response})

	if !current_assistant_response.is_empty():
		var assistant_message_id = SqliteClient.save_message(
			convo_id, current_assistant_response, "assistant"
		)
		if assistant_message_id == -1:
			push_error("Failed to save assistant message")
		current_assistant_response = ""

	if convo_context.size() == 2:
		var title = await LlmBackend.create_title(convo_context)
		SqliteClient.update_conversation_title(convo_id, title.replace('"', ""))


func _on_embedding_finished(content: String, embedding: Array) -> void:
	print("Inserting embedding")
	var message_id_query = """
        SELECT id FROM messages 
        WHERE conversation_id = ? 
        ORDER BY id DESC LIMIT 1;
    """
	if !SqliteClient.db.query_with_bindings(message_id_query, [convo_id]):
		push_error("Failed to get message for embedding: " + SqliteClient.db.error_message)
		return

	if SqliteClient.db.query_result.size() > 0:
		var message_id = SqliteClient.db.query_result[0]["id"]
		SqliteClient.insert_embedding(message_id, content, embedding)
	else:
		push_error("No message found for embedding")


func _on_button_pressed() -> void:
	if convo_id == -1:
		convo_id = SqliteClient.create_conversation()

	create_message(Sender.USER)
	write_target.text = input.text

	convo_context.append({"user": input.text})

	var user_message_id = SqliteClient.save_message(convo_id, input.text, "user")
	if user_message_id == -1:
		push_error("Failed to save user message")

	start_generation()
	input.text = ""


func start_generation() -> void:
	create_message(Sender.ASSISTANT)

	is_in_code_block = false
	is_collecting_language = false
	partial_backtick_sequence = ""
	partial_language = ""
	code_block = ""
	language = ""
	create_rich_text_label()
	LlmBackend.generate(selected_model, input.text)


func load_convo(id: int) -> void:
	# Clear existing messages
	for child in output_container.get_children():
		child.queue_free()

	# Reset conversation context and ID
	convo_context.clear()
	convo_id = id

	# Get all messages for this conversation
	var messages = SqliteClient.get_conversation_messages(id)

	# Render each message
	for msg in messages:
		print(msg)
		# Create appropriate message type based on role
		var sender = Sender.USER if msg.role == "user" else Sender.ASSISTANT

		# Create message container
		message = message_scene.instantiate()
		output_container.add_child(message)
		message_container = message.get_node("%MessageContainer") as VBoxContainer

		# Set up labels
		var name_label := message_container.get_node("%NameLabel") as Label
		var datetime_label := message_container.get_node("%DateTimeLabel") as Label

		if sender == Sender.USER:
			name_label.size_flags_horizontal = Control.SIZE_SHRINK_END
			name_label.text = "User"
			datetime_label.size_flags_horizontal = Control.SIZE_SHRINK_END
			datetime_label.text = msg.created_at

			# Create and configure text label for user message
			var text_label = create_rich_text_label()
			text_label.size_flags_horizontal = Control.SIZE_SHRINK_END | Control.SIZE_FILL
			text_label.text_direction = Control.TEXT_DIRECTION_RTL
			text_label.text = msg.content
		else:
			name_label.text = "Assistant"
			datetime_label.visible = false

			# Process assistant message with code block handling
			is_in_code_block = false
			is_collecting_language = false
			partial_backtick_sequence = ""
			partial_language = ""
			code_block = ""
			language = ""

			# Create initial rich text label
			create_rich_text_label()

			# Process the message content
			_on_chunk_processed(msg.content)

		# Add to conversation context
		if sender == Sender.USER:
			convo_context.append({"user": msg.content})
		else:
			convo_context.append({"assistant": msg.content})

	# Scroll to top after loading
	await get_tree().process_frame
	scroll_container.scroll_vertical = 0


func create_message(sender: Sender) -> void:
	message = message_scene.instantiate()
	output_container.add_child(message)
	message_container = message.get_node("%MessageContainer") as VBoxContainer

	var text_label = create_rich_text_label()
	var name_label := message_container.get_node("%NameLabel") as Label
	var datetime_label := message_container.get_node("%DateTimeLabel") as Label

	if sender == Sender.USER:
		name_label.size_flags_horizontal = Control.SIZE_SHRINK_END
		name_label.text = "User"
		datetime_label.size_flags_horizontal = Control.SIZE_SHRINK_END
		datetime_label.text = get_formatted_datetime()
		text_label.size_flags_horizontal = Control.SIZE_SHRINK_END | Control.SIZE_FILL
		text_label.text_direction = Control.TEXT_DIRECTION_RTL
	else:
		name_label.text = "Assistant"
		datetime_label.visible = false


func create_rich_text_label() -> RichTextLabel:
	rich_text_label = RichTextLabel.new()
	rich_text_label.fit_content = true
	rich_text_label.bbcode_enabled = true
	rich_text_label.selection_enabled = true
	message_container.add_child(rich_text_label)
	rich_text_label.text = ""
	write_target = rich_text_label
	return rich_text_label


func create_code_block(language: String) -> void:
	var code_block_container = code_block_container_scene.instantiate()
	message_container.add_child(code_block_container)
	code_block_container.set_language(language.strip_edges())
	write_target = code_block_container.get_code_area()


func _on_chunk_processed(chunk: String) -> void:
	current_assistant_response += chunk

	# First, handle any remaining backticks from previous chunk
	if partial_backtick_sequence.length() > 0:
		chunk = partial_backtick_sequence + chunk
		partial_backtick_sequence = ""

	var i := 0
	while i < chunk.length():
		var char = chunk[i]
		var remaining_chunk = chunk.substr(i)

		# Check for triple backticks
		if remaining_chunk.begins_with("```"):
			if !is_in_code_block:
				# Starting a code block
				is_in_code_block = true
				is_collecting_language = true
				partial_language = ""
			else:
				# Ending a code block
				is_in_code_block = false
				create_rich_text_label()
			i += 3
			continue

		# Check for single backtick (inline code)
		elif char == "`" and !is_in_code_block:
			# Just write the backtick as-is
			write_target.append_text(char)
			i += 1
			continue

		# Handle language collection
		if is_collecting_language:
			if char == "\n":
				is_collecting_language = false
				create_code_block(partial_language if !partial_language.is_empty() else "plain")
				i += 1
			elif char != " ":
				partial_language += char
				i += 1
			else:
				i += 1
			continue

		# Check for potential partial backticks at chunk end
		if i >= chunk.length() - 3:
			var remaining = chunk.substr(i)
			# If we're at the end and see backticks, store them for next chunk
			if remaining.begins_with("`"):
				partial_backtick_sequence = remaining
				break
			else:
				write_target.append_text(char)
				i += 1
		else:
			write_target.append_text(char)
			i += 1

	await get_tree().process_frame
	if !is_scrolling:
		scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value


func get_formatted_datetime():
	var dt = Time.get_datetime_dict_from_system()

	# Convert 24-hour to 12-hour format with AM/PM
	var hour = dt.hour
	var period = "AM"
	if hour >= 12:
		period = "PM"
		if hour > 12:
			hour -= 12
	elif hour == 0:
		hour = 12

	# Format with leading zeros where needed
	var formatted = (
		"%02d/%02d/%04d %02d:%02d %s" % [dt.day, dt.month, dt.year, hour, dt.minute, period]
	)

	return formatted
