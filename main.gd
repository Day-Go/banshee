extends Node

@onready var code_block_container_scene = preload("res://code_block.tscn")

@onready var button: Button = %Button
@onready var input: TextEdit = %Input
@onready var output_container: VBoxContainer = %OutputContainer

var current_rich_text_label: RichTextLabel
var is_in_code_block := false
var current_code_block := ""
var current_language := ""

func _ready() -> void:
	button.pressed.connect(_on_button_pressed)
	LlmBackend.chunk_processed.connect(_on_chunk_processed)
	_create_new_rich_text_label()  # Initialize the first label

func _on_button_pressed() -> void:
	# Clear existing output (important for repeated presses)
	for child in output_container.get_children():
		child.queue_free()

	# Reset state
	is_in_code_block = false
	current_code_block = ""
	current_language = ""
	_create_new_rich_text_label()  # Create the initial label for the new output

	LlmBackend.generate(input.text)

func _create_new_rich_text_label() -> void:
	current_rich_text_label = RichTextLabel.new()
	output_container.add_child(current_rich_text_label)
	current_rich_text_label.text = ""

func _on_chunk_processed(buffer: String) -> void:
	var buffer_index := 0
	while buffer_index < buffer.length():
		if is_in_code_block:
			var end_block_index = buffer.find("```", buffer_index)
			if end_block_index != -1:
				# Code block ends in this chunk
				current_code_block += buffer.substr(buffer_index, end_block_index - buffer_index)
				_create_code_block()  # Create the code block container *now*
				is_in_code_block = false
				buffer_index = end_block_index + 3  # Skip the closing backticks
			else:
				# Code block continues in the next chunk
				current_code_block += buffer.substr(buffer_index)
				buffer_index = buffer.length()  # Consume the entire chunk
		else:
			var start_block_index = buffer.find("```", buffer_index)
			if start_block_index != -1:
				# Code block starts in this chunk
				current_rich_text_label.text += buffer.substr(buffer_index, start_block_index - buffer_index)

				# Extract language
				var language_start = start_block_index + 3
				var language_end = buffer.find("\n", language_start)
				if language_end != -1:
					current_language = buffer.substr(language_start, language_end - language_start).strip_edges().to_lower()
					buffer_index = language_end + 1
					is_in_code_block = true
					current_code_block = "" # Initialize for the new code block
				else:
					# Invalid code block format - treat as plain text.
					current_rich_text_label.text += buffer.substr(start_block_index)
					buffer_index = buffer.length()

			else:
				# No code block in this chunk, append to current RichTextLabel
				current_rich_text_label.text += buffer.substr(buffer_index)
				buffer_index = buffer.length()


func _create_code_block() -> void:
	var code_block_container = code_block_container_scene.instantiate()
	output_container.add_child(code_block_container)
	code_block_container.set_code(current_code_block)
	code_block_container.set_language(current_language)
	_create_new_rich_text_label()  # Create a new RichTextLabel *after* the code block
	current_code_block = ""		   # Reset for potential future code blocks
	current_language = ""
