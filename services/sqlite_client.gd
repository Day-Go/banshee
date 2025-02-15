extends Node

var db: SQLite = null
const verbosity_level: int = SQLite.VERBOSE

var db_name := "res://data/test"

signal output_received(text)


func _ready() -> void:
	db = SQLite.new()
	db.path = db_name
	db.verbosity_level = verbosity_level

	var schema = define_schema()
	connect_db(schema)
	#insert_chat()


func cprint(text: String) -> void:
	print(text)
	output_received.emit(text)


func define_schema() -> Dictionary:
	var tables_dict := Dictionary()

	var chat_history_dict := Dictionary()
	chat_history_dict["id"] = {"data_type": "int", "primary_key": true, "not_null": true}
	chat_history_dict["convo_hash"] = {"data_type": "text"}
	chat_history_dict["title"] = {"data_type": "text"}
	chat_history_dict["content"] = {"data_type": "text"}
	chat_history_dict["embedding"] = {"data_type": "float[1024]"}

	tables_dict["chat_history"] = chat_history_dict

	return tables_dict


func connect_db(schema: Dictionary) -> void:
	db.open_db()
	for table_name in schema.keys():
		var table_schema = schema[table_name]
		db.create_table(table_name, table_schema)

	db.enable_load_extension(true)
	db.load_extension("/usr/lib/python3.13/site-packages/sqlite_vec/vec0.so", "sqlite3_vec_init")
	db.enable_load_extension(false)


func insert_embedding(convo_hash: String, title: String, content: String, embedding: Array) -> void:
	var insert_query = (
		"""
		INSERT OR REPLACE INTO chat_history (convo_hash, title, content, embedding) VALUES
		('%s', '%s', '%s', '%s');
	"""
		% [convo_hash, title, content, embedding]
	)

	var result = db.query(insert_query)
	cprint("Insert result: " + str(result))
