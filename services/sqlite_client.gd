extends Node

var db: SQLite = null
const verbosity_level: int = SQLite.VERBOSE

var db_name := "res://data/test"
var current_conversation_id: int = -1

signal output_received(text)


func _ready() -> void:
	db = SQLite.new()
	db.path = db_name
	db.verbosity_level = verbosity_level

	var schema = define_schema()
	connect_db(schema)


func cprint(text: String) -> void:
	print(text)
	output_received.emit(text)


func define_schema() -> Dictionary:
	var tables_dict := Dictionary()

	# Conversations table
	var convo_dict := Dictionary()
	convo_dict["id"] = {
		"data_type": "INTEGER", "primary_key": true, "not_null": true, "auto_increment": true
	}
	convo_dict["hash"] = {"data_type": "TEXT", "not_null": true, "unique": true}
	convo_dict["title"] = {"data_type": "TEXT"}
	convo_dict["created_at"] = {
		"data_type": "TIMESTAMP", "not_null": true, "default": "CURRENT_TIMESTAMP"
	}

	# Messages table
	var message_dict := Dictionary()
	message_dict["id"] = {
		"data_type": "INTEGER", "primary_key": true, "not_null": true, "auto_increment": true
	}
	message_dict["conversation_id"] = {
		"data_type": "INTEGER",
		"not_null": true,
		"foreign_key": {"table": "conversations", "column": "id", "on_delete": "CASCADE"}
	}
	message_dict["content"] = {"data_type": "TEXT", "not_null": true}
	message_dict["created_at"] = {
		"data_type": "TIMESTAMP", "not_null": true, "default": "CURRENT_TIMESTAMP"
	}
	message_dict["role"] = {"data_type": "TEXT", "not_null": true}

	# Embeddings table
	var embeddings_dict := Dictionary()
	embeddings_dict["id"] = {
		"data_type": "INTEGER", "primary_key": true, "not_null": true, "auto_increment": true
	}
	embeddings_dict["message_id"] = {
		"data_type": "INTEGER",
		"not_null": true,
		"foreign_key": {"table": "messages", "column": "id", "on_delete": "CASCADE"}
	}
	embeddings_dict["content"] = {"data_type": "TEXT", "not_null": true}
	embeddings_dict["embedding"] = {"data_type": "float[1024]", "not_null": true}
	embeddings_dict["created_at"] = {
		"data_type": "TIMESTAMP", "not_null": true, "default": "CURRENT_TIMESTAMP"
	}

	tables_dict["conversations"] = convo_dict
	tables_dict["messages"] = message_dict
	tables_dict["embeddings"] = embeddings_dict

	return tables_dict


func connect_db(schema: Dictionary) -> void:
	db.open_db()
	for table_name in schema.keys():
		var table_schema = schema[table_name]
		db.create_table(table_name, table_schema)

	db.enable_load_extension(true)
	db.load_extension("/usr/lib/python3.13/site-packages/sqlite_vec/vec0.so", "sqlite3_vec_init")
	db.enable_load_extension(false)


func create_tables(db: SQLite, schema: Dictionary) -> void:
	# Enable foreign key support
	db.query("PRAGMA foreign_keys = ON;")

	for table_name in schema.keys():
		var table_schema = schema[table_name]
		var create_query = "CREATE TABLE IF NOT EXISTS " + table_name + " ("
		var columns := []
		var foreign_keys := []

		for column_name in table_schema.keys():
			var column_def = table_schema[column_name]
			var column_str = column_name + " " + column_def["data_type"]

			if column_def.get("primary_key", false):
				column_str += " PRIMARY KEY"
			if column_def.get("auto_increment", false):
				column_str += " AUTOINCREMENT"
			if column_def.get("not_null", false):
				column_str += " NOT NULL"
			if column_def.get("unique", false):
				column_str += " UNIQUE"
			if column_def.get("default", null) != null:
				column_str += " DEFAULT " + column_def["default"]

			columns.append(column_str)

			# Handle foreign key constraints
			if column_def.get("foreign_key", null) != null:
				var fk = column_def["foreign_key"]
				var fk_str = (
					"FOREIGN KEY ("
					+ column_name
					+ ") REFERENCES "
					+ fk["table"]
					+ "("
					+ fk["column"]
					+ ")"
				)
				if fk.get("on_delete", null) != null:
					fk_str += " ON DELETE " + fk["on_delete"]
				foreign_keys.append(fk_str)

		create_query += ", ".join(columns)
		if foreign_keys.size() > 0:
			create_query += ", " + ", ".join(foreign_keys)
		create_query += ");"

		var result = db.query(create_query)
		print("Created table " + table_name + ": " + str(result))


func init_conversation() -> void:
	var init_query = """
        SELECT id FROM conversations 
        ORDER BY created_at DESC 
        LIMIT 1;
    """
	if !db.query(init_query):  # No bindings needed for this query
		push_error("Failed to check for existing conversations: " + db.error_message)
		return

	if db.query_result.size() > 0:
		current_conversation_id = db.query_result[0]["id"]
	else:
		# Create a new conversation if none exists
		current_conversation_id = create_conversation()


func create_conversation(title: String = "New Conversation") -> int:
	var hash = generate_uuid()

	var convo_insert_query = """
        INSERT INTO conversations (hash, title)
        VALUES (?, ?);
    """
	if !db.query_with_bindings(convo_insert_query, [hash, title]):
		push_error("Failed to insert conversation: " + db.error_message)
		return -1

	var convo_id_query = """
        SELECT id FROM conversations 
        WHERE hash = ?;
    """
	if !db.query_with_bindings(convo_id_query, [hash]):
		push_error("Failed to get conversation ID: " + db.error_message)
		return -1

	if db.query_result.size() > 0:
		current_conversation_id = db.query_result[0]["id"]
		return current_conversation_id

	push_error("No conversation found after insert")
	return -1


func save_message(content: String, role: String) -> int:
	if current_conversation_id == -1:
		# No active conversation, create one
		current_conversation_id = create_conversation()
		if current_conversation_id == -1:
			push_error("Failed to create conversation for message")
			return -1

	var message_insert_query = """
        INSERT INTO messages (conversation_id, content, role)
        VALUES (?, ?, ?);
    """
	if !db.query_with_bindings(message_insert_query, [current_conversation_id, content, role]):
		push_error("Failed to insert message: " + db.error_message)
		return -1

	var message_id_query = """
        SELECT id FROM messages 
        WHERE conversation_id = ? 
        ORDER BY id DESC LIMIT 1;
    """
	if !db.query_with_bindings(message_id_query, [current_conversation_id]):
		push_error("Failed to get message ID: " + db.error_message)
		return -1

	if db.query_result.size() > 0:
		return db.query_result[0]["id"]

	push_error("No message found after insert")
	return -1


func insert_embedding(message_id: int, content: String, embedding: Array) -> void:
	# godot-sqlite doesn't support arrays in query_with_binding so use string interpolation
	# and strip any apostrophes from the content for now
	var insert_query = (
		"""
        INSERT OR REPLACE INTO embeddings (message_id, content, embedding) VALUES
        (%s, '%s', '%s');
    """
		% [message_id, content.replace("'", ""), embedding]
	)
	var result = db.query(insert_query)
	cprint("Insert result: " + str(result))


func generate_uuid() -> String:
	var rng = RandomNumberGenerator.new()
	rng.randomize()

	var hex_chars = "0123456789abcdef"
	var uuid_format = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
	var uuid = ""

	for c in uuid_format:
		if c == "-":
			uuid += "-"
		elif c == "4":
			uuid += "4"
		elif c == "y":
			# Version 4 UUID specific bits
			var rand = rng.randi_range(8, 11)  # 8,9,a,b
			uuid += hex_chars[rand]
		else:
			uuid += hex_chars[rng.randi() & 0xf]

	return uuid
