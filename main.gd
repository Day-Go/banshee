extends Node

@onready var code_block_container_scene = preload("res://code_block.tscn")
@onready var button: Button = %Button
@onready var input: TextEdit = %Input
@onready var output_container: VBoxContainer = %OutputContainer

var buffer := ""
var write_target: RichTextLabel
var is_in_code_block := false
var is_in_inline_code := false
var partial_backtick_sequence := ""
var is_collecting_language := false
var partial_language := ""
var current_rich_text_label: RichTextLabel
var current_code_block := ""
var current_language := ""


func _ready() -> void:
	button.pressed.connect(_on_button_pressed)

	LlmBackend.generation_started.connect(_on_generation_started)
	LlmBackend.chunk_processed.connect(_on_chunk_processed)
	LlmBackend.generation_finished.connect(_on_generation_finished)
	LlmBackend.embedding_finished.connect(_on_embedding_finished)

	create_rich_text_label()
	input.text = "write hello world in python."


func _on_generation_started() -> void:
	button.disabled = true


func _on_generation_finished() -> void:
	button.disabled = false


func _on_embedding_finished(embedding: Array) -> void:
	print("Inserting embedding")
	SqliteClient.insert_embedding("57f8gf", "Test query", embedding)


func _on_button_pressed() -> void:
	for child in output_container.get_children():
		child.queue_free()
	is_in_code_block = false
	is_in_inline_code = false
	is_collecting_language = false
	partial_backtick_sequence = ""
	partial_language = ""
	current_code_block = ""
	current_language = ""
	create_rich_text_label()
	LlmBackend.generate(input.text)


func create_rich_text_label() -> void:
	current_rich_text_label = RichTextLabel.new()
	current_rich_text_label.fit_content = true
	current_rich_text_label.bbcode_enabled = true
	output_container.add_child(current_rich_text_label)
	current_rich_text_label.text = ""
	write_target = current_rich_text_label


func create_code_block(language: String) -> void:
	var code_block_container = code_block_container_scene.instantiate()
	output_container.add_child(code_block_container)
	code_block_container.set_language(language.strip_edges())
	write_target = code_block_container.get_code_area()


func _on_chunk_processed(chunk: String) -> void:
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
