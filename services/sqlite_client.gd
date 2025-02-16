extends Node

var db: SQLite = null
const verbosity_level: int = SQLite.QUIET

var db_name := "res://data/test"

signal convo_created(convo: Dictionary)
signal convo_title_updated(convo_id: int, title: String)


func _ready() -> void:
	db = SQLite.new()
	db.path = db_name
	db.verbosity_level = verbosity_level

	var schema = define_schema()
	connect_db(schema)


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


func create_conversation() -> int:
	var title: String = "New Conversation"
	var convo_hash: String = generate_uuid()

	print("No conversation found, creating a new conversation")

	var convo_insert_query = """
        INSERT INTO conversations (hash, title)
        VALUES (?, ?);
    """
	if !db.query_with_bindings(convo_insert_query, [convo_hash, title]):
		push_error("Failed to insert conversation: " + db.error_message)
		return -1

	var convo_id_query = """
        SELECT id, created_at FROM conversations 
        WHERE hash = ?;
    """
	if !db.query_with_bindings(convo_id_query, [convo_hash]):
		push_error("Failed to get conversation ID: " + db.error_message)
		return -1

	if db.query_result.size() > 0:
		var convo_id = db.query_result[0]["id"]
		var convo = {
			"id": convo_id,
			"hash": hash,
			"title": title,
			"created_at": db.query_result[0]["created_at"]
		}
		convo_created.emit(convo)
		return convo_id

	push_error("Coudln't retrieve id of newly created conversation.")
	return -1


func update_conversation_title(convo_id: int, title: String) -> void:
	var title_update_query := """
		UPDATE conversations
		SET title = ?
		WHERE id = ?
	"""
	if !db.query_with_bindings(title_update_query, [title, convo_id]):
		push_error("Couldn't update the title of conversation %s" % convo_id)

	convo_title_updated.emit(convo_id, title)


func save_message(convo_id: int, content: String, role: String) -> int:
	var message_insert_query = """
        INSERT INTO messages (conversation_id, content, role)
        VALUES (?, ?, ?);
    """
	if !db.query_with_bindings(message_insert_query, [convo_id, content, role]):
		push_error("Failed to insert message: " + db.error_message)
		return -1

	var message_id_query = """
        SELECT id FROM messages 
        WHERE conversation_id = ? 
        ORDER BY id DESC LIMIT 1;
    """
	if !db.query_with_bindings(message_id_query, [convo_id]):
		push_error("Failed to get message ID: " + db.error_message)
		return -1

	if db.query_result.size() > 0:
		return db.query_result[0]["id"]

	push_error("No message found after insert")
	return -1


func get_n_latest_convos(n: int) -> Array:
	var n_latest_convo_query := """
        SELECT id, hash, title, created_at
        FROM conversations
        ORDER BY created_at DESC
        LIMIT ?
	"""
	if !db.query_with_bindings(n_latest_convo_query, [n]):
		push_error("Failed to retrieve %s most recent conversations")

	if db.query_result.size() > 0:
		return db.query_result
	else:
		return Array()


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
	db.query(insert_query)


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
