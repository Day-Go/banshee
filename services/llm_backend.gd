extends Node

signal embedding_started
signal embedding_finished
signal generation_started(content: String, embedding: Array)
signal generation_finished
signal chunk_processed(chunk: String)
signal title_creation_started
signal title_creationg_finished(title: String)

var http := HTTPClient.new()
var headers := ["User-Agent: Pirulo/1.0 (Godot)", "Accept: */*"]
var err: int
var buffer: String


func _ready() -> void:
	err = http.connect_to_host("http://localhost", 11434)
	assert(err == OK)

	while (
		http.get_status() == HTTPClient.STATUS_CONNECTING
		or http.get_status() == HTTPClient.STATUS_RESOLVING
	):
		http.poll()
		await get_tree().process_frame

	assert(http.get_status() == HTTPClient.STATUS_CONNECTED)

	buffer = ""


func generate(model: String, prompt: String) -> void:
	generation_started.emit()
	buffer = ""

	prompt += " Dont output any markdown when writing code blocks."
	var json_data = {"model": model, "prompt": prompt, "stream": true}

	err = http.request(HTTPClient.METHOD_POST, "/api/generate", headers, JSON.stringify(json_data))
	if err != OK:
		print("Request error: %s" % err)
		return

	var response_code = -1
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		await get_tree().process_frame

	if http.has_response():
		response_code = http.get_response_code()
		if response_code != 200:
			print("HTTP Error: %s" % response_code)
			var error_body = http.get_response_body().get_string_from_utf8()
			while http.get_response_body_length() > 0:
				var chunk = http.read_response_body_chunk()
				error_body.append_array(chunk)
			print("Error body: %s" % error_body)

		while http.get_status() == HTTPClient.STATUS_BODY:
			http.poll()
			var chunk = http.read_response_body_chunk()
			if chunk.size() == 0:
				await get_tree().process_frame
			else:
				var parsed_chunk = JSON.parse_string(chunk.get_string_from_ascii())["response"]
				chunk_processed.emit(parsed_chunk)

	generation_finished.emit()


func create_title(context: Array) -> String:
	title_creation_started.emit()

	var messages := "Create a concise, to-the-point, title for the following conversation: "
	for message in context:
		messages += JSON.stringify(message)

	var json_data = {"model": "olmo2:latest", "prompt": messages, "stream": true}

	err = http.request(HTTPClient.METHOD_POST, "/api/generate", headers, JSON.stringify(json_data))
	if err != OK:
		print("Request error: %s" % err)
		return "Error"

	var response_code = -1
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		await get_tree().process_frame

	var title := ""
	if http.has_response():
		response_code = http.get_response_code()
		if response_code != 200:
			print("HTTP Error: %s" % response_code)
			var error_body = http.get_response_body().get_string_from_utf8()
			while http.get_response_body_length() > 0:
				var chunk = http.read_response_body_chunk()
				error_body.append_array(chunk)
			print("Error body: %s" % error_body)

		while http.get_status() == HTTPClient.STATUS_BODY:
			http.poll()
			var chunk = http.read_response_body_chunk()
			if chunk.size() == 0:
				await get_tree().process_frame
			else:
				var parsed_chunk = JSON.parse_string(chunk.get_string_from_ascii())["response"]
				title += parsed_chunk

	return title


func embed(input: String) -> void:
	embedding_started.emit()
	var json_data = {"model": "snowflake-arctic-embed", "input": input}
	err = http.request(HTTPClient.METHOD_POST, "/api/embed", headers, JSON.stringify(json_data))
	if err != OK:
		print("Request error: %s" % err)
		return

	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		print("Requesting...")
		await get_tree().process_frame

	if http.has_response():
		var response_code = http.get_response_code()
		if response_code != 200:
			print("HTTP Error: %s" % response_code)
			return

		var response_body = PackedByteArray()
		while http.get_status() == HTTPClient.STATUS_BODY:
			http.poll()
			var chunk = http.read_response_body_chunk()
			if chunk.size() == 0:
				await get_tree().process_frame
			else:
				response_body.append_array(chunk)

		var response_text = response_body.get_string_from_utf8()
		var parsed_response = JSON.parse_string(response_text)

		if parsed_response and parsed_response.has("embeddings"):
			print(parsed_response["embeddings"][0].size())
			embedding_finished.emit(input, parsed_response["embeddings"][0])
		else:
			print("Invalid response format: ", response_text)
