extends Node

signal embedding_started
signal embedding_ready_to_save(input: String, embedding: Array)
signal embedding_ready_to_process(embedding: Array)
signal generation_started
signal generation_finished
signal chunk_processed(chunk: String)
signal title_creation_started
signal title_creationg_finished(title: String)

# Create separate HTTP clients
var generate_http := HTTPClient.new()
var embed_http := HTTPClient.new()
var title_http := HTTPClient.new()

var headers := ["User-Agent: Pirulo/1.0 (Godot)", "Accept: */*"]
var buffer: String


func _ready() -> void:
	# Connect all clients to the host
	_connect_client(generate_http)
	_connect_client(embed_http)
	_connect_client(title_http)

	buffer = ""


func _connect_client(client: HTTPClient) -> void:
	var err = client.connect_to_host("http://localhost", 11434)
	assert(err == OK)

	while (
		client.get_status() == HTTPClient.STATUS_CONNECTING
		or client.get_status() == HTTPClient.STATUS_RESOLVING
	):
		client.poll()
		await get_tree().process_frame

	assert(client.get_status() == HTTPClient.STATUS_CONNECTED)


func generate(model: String, messages: Array) -> void:
	generation_started.emit()
	buffer = ""

	var prompt := ""
	for message in messages:
		prompt += JSON.stringify(message)

	print(prompt)

	var json_data = {"model": model, "prompt": prompt, "stream": true}

	var err = generate_http.request(
		HTTPClient.METHOD_POST, "/api/generate", headers, JSON.stringify(json_data)
	)
	if err != OK:
		print("Request error: %s" % err)
		return

	var response_code = -1
	while generate_http.get_status() == HTTPClient.STATUS_REQUESTING:
		generate_http.poll()
		await get_tree().process_frame

	if generate_http.has_response():
		response_code = generate_http.get_response_code()
		if response_code != 200:
			print("HTTP Error: %s" % response_code)
			var error_body = generate_http.get_response_body().get_string_from_utf8()
			while generate_http.get_response_body_length() > 0:
				var chunk = generate_http.read_response_body_chunk()
				error_body.append_array(chunk)
			print("Error body: %s" % error_body)

		while generate_http.get_status() == HTTPClient.STATUS_BODY:
			generate_http.poll()
			var chunk = generate_http.read_response_body_chunk()
			if chunk.size() == 0:
				await get_tree().process_frame
			else:
				var parsed_chunk = JSON.parse_string(chunk.get_string_from_ascii())["response"]
				chunk_processed.emit(parsed_chunk)

	generation_finished.emit()


func create_title(context: Array) -> String:
	title_creation_started.emit()

	var messages := "Create a concise, single-sentence title for the following conversation: \n"
	for message in context:
		messages += JSON.stringify(message)

	var json_data = {"model": "olmo2:latest", "prompt": messages, "stream": true}

	var err = title_http.request(
		HTTPClient.METHOD_POST, "/api/generate", headers, JSON.stringify(json_data)
	)
	if err != OK:
		print("Request error: %s" % err)
		return "Error"

	var response_code = -1
	while title_http.get_status() == HTTPClient.STATUS_REQUESTING:
		title_http.poll()
		await get_tree().process_frame

	var title := ""
	if title_http.has_response():
		response_code = title_http.get_response_code()
		if response_code != 200:
			print("HTTP Error: %s" % response_code)
			var error_body = title_http.get_response_body().get_string_from_utf8()
			while title_http.get_response_body_length() > 0:
				var chunk = title_http.read_response_body_chunk()
				error_body.append_array(chunk)
			print("Error body: %s" % error_body)

		while title_http.get_status() == HTTPClient.STATUS_BODY:
			title_http.poll()
			var chunk = title_http.read_response_body_chunk()
			if chunk.size() == 0:
				await get_tree().process_frame
			else:
				var parsed_chunk = JSON.parse_string(chunk.get_string_from_ascii())["response"]
				title += parsed_chunk

	return title


func embed(input: String, save_to_database: bool) -> void:
	embedding_started.emit()
	var json_data = {"model": "snowflake-arctic-embed", "input": input}
	var err = embed_http.request(
		HTTPClient.METHOD_POST, "/api/embed", headers, JSON.stringify(json_data)
	)
	if err != OK:
		print("Request error: %s" % err)
		return

	while embed_http.get_status() == HTTPClient.STATUS_REQUESTING:
		embed_http.poll()
		await get_tree().process_frame

	if embed_http.has_response():
		var response_code = embed_http.get_response_code()
		if response_code != 200:
			print("HTTP Error: %s" % response_code)
			return

		var response_body = PackedByteArray()
		while embed_http.get_status() == HTTPClient.STATUS_BODY:
			embed_http.poll()
			var chunk = embed_http.read_response_body_chunk()
			if chunk.size() == 0:
				await get_tree().process_frame
			else:
				response_body.append_array(chunk)

		var response_text = response_body.get_string_from_utf8()
		var parsed_response = JSON.parse_string(response_text)

		if parsed_response and parsed_response.has("embeddings"):
			var embedding = parsed_response["embeddings"][0]
			if save_to_database:
				embedding_ready_to_save.emit(input, embedding)
			else:
				embedding_ready_to_process.emit(embedding)
		else:
			print("Invalid response format: ", response_text)
