extends Node

signal chunk_processed(buffer: String)

var http := HTTPClient.new()
var headers := [
	"User-Agent: Pirulo/1.0 (Godot)",
	"Accept: */*"
]
var err: int
var buffer: String

func _ready() -> void:
	err = http.connect_to_host("http://localhost", 11434)
	assert(err==OK)
	
	while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
		http.poll()
		print("Connecting...")
		await get_tree().process_frame
		
	assert(http.get_status() == HTTPClient.STATUS_CONNECTED)
	
	clear_buffer()
	
func clear_buffer() -> void:
	buffer = ""	

func generate(prompt: String) -> void: 
	clear_buffer()
	
	var json_data = {
		"model": "qwen2.5-coder:32b",
		"prompt": prompt,
		"stream": true
	}

	err = http.request(HTTPClient.METHOD_POST, "/api/generate", headers, JSON.stringify(json_data))
	if err != OK:
		print("Request error: %s" % err)
		return
		
	var response_code = -1
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		print("Requesting...")
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
				buffer += JSON.parse_string(chunk.get_string_from_ascii())['response']
				chunk_processed.emit(buffer)
