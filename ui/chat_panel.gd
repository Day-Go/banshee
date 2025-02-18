extends Node

@onready var message_scene = preload("res://ui/message.tscn")
@onready var code_block_scene = preload("res://ui/code_block.tscn")
@onready var think_block_scene = preload("res://ui/think_block.tscn")
@onready var scroll_container: ScrollContainer = %ScrollContainer
@onready var model_dropdown: OptionButton = %ModelDropdown
@onready var button: Button = %SendButton
@onready var input: TextEdit = %InputTextArea
@onready var output_container: VBoxContainer = %OutputContainer

enum Sender { USER, ASSISTANT }

var models := ["deepseek-r1:32b", "qwen2.5-coder:32b", "openthinker:32b", "olmo2:latest"]
var selected_model := "deepseek-r1:32b"

var thought_begin_patterns = ["<|begin_of_thought|>", "<think>"]
var thought_end_patterns = ["<|end_of_thought|>", "</think>"]

var buffer := ""
var write_target: RichTextLabel
var is_in_code_block := false
var is_collecting_language := false
var is_in_think_block := false
var is_scrolling := false
var partial_backtick_sequence := ""
var partial_thought_pattern := ""
var partial_language := ""
var rich_text_label: RichTextLabel
var code_block := ""
var language := ""

var current_assistant_response := ""
var message: PanelContainer
var message_container: VBoxContainer
var convo_id: int = -1
var convo_context := []


func _ready() -> void:
	button.pressed.connect(_on_button_pressed)

	LlmBackend.generation_started.connect(_on_generation_started)
	LlmBackend.chunk_processed.connect(_on_chunk_processed)
	LlmBackend.generation_finished.connect(_on_generation_finished)
	LlmBackend.embedding_finished.connect(_on_embedding_finished)
	SignalBus.convo_selected.connect(load_convo)
	SignalBus.new_convo_requested.connect(create_new_convo)

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

	var message_id: int = SqliteClient.get_latest_message_id(convo_id)
	if message_id > 0:
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
	is_in_think_block = false
	is_collecting_language = false
	partial_backtick_sequence = ""
	partial_thought_pattern = ""
	partial_language = ""
	code_block = ""
	language = ""
	create_rich_text_label()
	LlmBackend.generate(selected_model, convo_context)


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
			is_in_think_block = false
			is_collecting_language = false
			partial_backtick_sequence = ""
			partial_thought_pattern = ""
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


func create_new_convo() -> void:
	for child in output_container.get_children():
		child.queue_free()

	# Reset conversation context and ID
	convo_context.clear()
	convo_id = -1


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
		datetime_label.text = Utils.get_formatted_datetime()
		text_label.size_flags_horizontal = Control.SIZE_SHRINK_END | Control.SIZE_FILL
		text_label.text_direction = Control.TEXT_DIRECTION_RTL
	else:
		name_label.text = selected_model
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
	var code_block = code_block_scene.instantiate()
	message_container.add_child(code_block)
	code_block.set_language(language.strip_edges())
	write_target = code_block.get_code_area()


func create_think_block() -> void:
	var think_block = think_block_scene.instantiate()
	message_container.add_child(think_block)
	write_target = think_block.get_node("%TextArea") as RichTextLabel
	# Ensure the write target is valid
	if write_target == null:
		push_error("Failed to get %TextArea in think block")
		create_rich_text_label()  # Fallback to regular text if something went wrong


func _on_chunk_processed(chunk: String) -> void:
	current_assistant_response += chunk

	# Handle any remaining patterns from previous chunk
	if partial_backtick_sequence.length() > 0:
		chunk = partial_backtick_sequence + chunk
		partial_backtick_sequence = ""

	if partial_thought_pattern.length() > 0:
		print("Processing partial thought pattern: ", partial_thought_pattern)
		chunk = partial_thought_pattern + chunk
		partial_thought_pattern = ""

	var i := 0
	while i < chunk.length():
		var char = chunk[i]
		var remaining_chunk = chunk.substr(i)

		# Check for think block patterns
		var is_think_begin = false
		var is_think_end = false
		var pattern_length = 0
		var matched_pattern = ""

		for pattern in thought_begin_patterns:
			if remaining_chunk.begins_with(pattern):
				is_think_begin = true
				pattern_length = pattern.length()
				matched_pattern = pattern
				break

		for pattern in thought_end_patterns:
			if remaining_chunk.begins_with(pattern):
				is_think_end = true
				pattern_length = pattern.length()
				matched_pattern = pattern
				break

		# Handle think block start
		if is_think_begin and !is_in_think_block and !is_in_code_block:
			is_in_think_block = true
			create_think_block()
			print("Think block started with pattern: ", matched_pattern)
			i += pattern_length
			continue

		# Handle think block end
		elif is_think_end and is_in_think_block:
			is_in_think_block = false
			print("Think block ended with pattern: ", matched_pattern)
			create_rich_text_label()
			i += pattern_length
			continue

		# Check for triple backticks (only process if not in think block)
		if !is_in_think_block and remaining_chunk.begins_with("```"):
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

		# Check for single backtick (inline code) - only process if not in think block
		elif char == "`" and !is_in_code_block and !is_in_think_block:
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

		# Check for potential partial patterns at chunk end
		if i >= chunk.length() - 20:  # Allow for longest think pattern
			var remaining = chunk.substr(i)

			# First check for partial think patterns at end (higher priority)
			var found_partial_pattern = false
			for pattern in thought_begin_patterns + thought_end_patterns:
				if (
					pattern.begins_with(remaining)
					or remaining.begins_with(pattern.substr(0, remaining.length()))
				):
					partial_thought_pattern = remaining
					found_partial_pattern = true
					print("Found partial thought pattern at end: ", remaining)
					break

			# Then check for partial backticks at end
			if !found_partial_pattern and remaining.begins_with("`") and !is_in_think_block:
				partial_backtick_sequence = remaining
				break

			if found_partial_pattern:
				break
			else:
				if write_target != null:
					write_target.append_text(char)
				else:
					push_error("Write target is null when trying to append text")
					create_rich_text_label()
					write_target.append_text(char)
				i += 1
		else:
			if write_target != null:
				write_target.append_text(char)
			else:
				push_error("Write target is null when trying to append text")
				create_rich_text_label()
				write_target.append_text(char)
			i += 1

	await get_tree().process_frame
	if !is_scrolling:
		scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value
