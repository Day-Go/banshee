extends SubViewportContainer

# Configuration parameters
@export var point_radius: float = 5.0
@export var line_width: float = 2.0
@export var point_color: Color = Color.AZURE
@export var line_color: Color = Color.BLACK
@export var scale_padding: float = 20.0  # Padding around the visualization
@export var use_umap: bool = true  # Set to true to use UMAP, false for PCA

# Canvas properties
var canvas_center: Vector2
var scale_factor: float = 1.0
var last_point: Vector2 = Vector2.ZERO
var first_point: bool = true

# Storage for points and embeddings
var data_center: Vector2 = Vector2.ZERO
var points_2d: Array[Vector2] = []
var all_embeddings: Array = []

# PCA variables
var mean_vector: Array = []
var eigenvectors: Array = []

# Node references
@onready var sub_viewport: SubViewport = %SubViewport
@onready var canvas: Node2D = %Canvas
@onready var timer: Timer = %UpdateTimer


func _ready() -> void:
	# Initialize nodes and properties
	canvas_center = Vector2(sub_viewport.size.x / 2, sub_viewport.size.y / 2)
	print(canvas_center)
	timer.connect("timeout", _on_update_timer_timeout)

	# Set up the initial canvas state
	canvas.draw.connect(_draw_visualization)

	# Configure the container
	stretch = true
	stretch_shrink = 1

	# Start the timer for periodic updates
	timer.start()


# Main function to receive and process new embeddings
func add_embedding(embedding: Array) -> void:
	all_embeddings.append(embedding)

	# If we have only one embedding, create an initial point
	if all_embeddings.size() == 1:
		points_2d.append(Vector2(0, 0))
		_normalize_points()
		canvas.queue_redraw()
		return

	# Once we have multiple embeddings, we can start dimensional reduction
	var points: Array[Vector2] = _reduce_dimensions()
	update_visualization(points)


# Perform dimensional reduction on all embeddings
func _reduce_dimensions() -> Array[Vector2]:
	if use_umap:
		return _reduce_with_umap()
	else:
		return _reduce_with_pca()


# Basic PCA implementation
func _reduce_with_pca() -> Array[Vector2]:
	var data_matrix: Array = all_embeddings.duplicate()
	var dimension: int = data_matrix[0].size()
	var num_samples: int = data_matrix.size()

	# Calculate mean of each dimension
	mean_vector = []
	for i in range(dimension):
		var sum: float = 0.0
		for j in range(num_samples):
			sum += data_matrix[j][i]
		mean_vector.append(sum / num_samples)

	# Center the data
	for i in range(num_samples):
		for j in range(dimension):
			data_matrix[i][j] -= mean_vector[j]

	# Calculate covariance matrix
	var covariance_matrix: Array = []
	for i in range(dimension):
		covariance_matrix.append([])
		for j in range(dimension):
			covariance_matrix[i].append(0.0)

	for i in range(dimension):
		for j in range(dimension):
			for k in range(num_samples):
				covariance_matrix[i][j] += data_matrix[k][i] * data_matrix[k][j]
			covariance_matrix[i][j] /= num_samples - 1

	# For simplicity, we'll use a basic power iteration to find the 2 principal components
	# In a real implementation, you'd want to use a library or more robust method
	eigenvectors = _power_iteration(covariance_matrix, 2)

	# Project the data onto the principal components
	var result: Array[Vector2] = []
	for sample in data_matrix:
		var x: float = 0.0
		var y: float = 0.0
		for i in range(dimension):
			x += sample[i] * eigenvectors[0][i]
			y += sample[i] * eigenvectors[1][i]
		result.append(Vector2(x, y))

	return result


# Simple power iteration method to find eigenvectors
# This is a basic implementation and might not be numerically stable
func _power_iteration(matrix: Array, num_vectors: int) -> Array:
	var dimension: int = matrix.size()
	var result: Array = []
	var orthogonal_space: Array = []

	for vector_index in range(num_vectors):
		# Initialize a random vector
		var v: Array = []
		for i in range(dimension):
			v.append(randf_range(-1.0, 1.0))

		# Orthogonalize against previously found eigenvectors
		for basis in orthogonal_space:
			var dot_product: float = 0.0
			for i in range(dimension):
				dot_product += v[i] * basis[i]
			for i in range(dimension):
				v[i] -= dot_product * basis[i]

		# Normalize
		var norm: float = 0.0
		for i in range(dimension):
			norm += v[i] * v[i]
		norm = sqrt(norm)
		for i in range(dimension):
			v[i] /= norm

		# Power iteration
		for iteration in range(20):  # Typically 10-20 iterations is enough
			var new_v: Array = []
			for i in range(dimension):
				new_v.append(0.0)

			# Matrix-vector multiplication
			for i in range(dimension):
				for j in range(dimension):
					new_v[i] += matrix[i][j] * v[j]

			# Normalize
			norm = 0.0
			for i in range(dimension):
				norm += new_v[i] * new_v[i]
			norm = sqrt(norm)
			for i in range(dimension):
				new_v[i] /= norm

			v = new_v

		result.append(v)
		orthogonal_space.append(v)

	return result


# Simple UMAP-inspired approach (not true UMAP)
# For a real implementation, consider using a GDNative plugin with scikit-learn
func _reduce_with_umap() -> Array[Vector2]:
	# This is a simplified approach that mimics some UMAP concepts
	# We'll use a force-directed layout algorithm as a stand-in

	var num_samples: int = all_embeddings.size()
	if num_samples < 2:
		return []

	# Initialize random positions for each point
	var positions: Array[Vector2] = []
	for i in range(num_samples):
		positions.append(Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)))

	# Calculate pairwise distances in high-dimensional space
	var distances: Array = []
	for i in range(num_samples):
		distances.append([])
		for j in range(num_samples):
			var dist: float = 0.0
			for k in range(all_embeddings[i].size()):
				dist += pow(all_embeddings[i][k] - all_embeddings[j][k], 2)
			distances[i].append(sqrt(dist))

	# Simple force-directed layout algorithm
	# Run multiple iterations to stabilize the layout
	for iteration in range(50):
		var forces: Array[Vector2] = []
		for i in range(num_samples):
			forces.append(Vector2.ZERO)

		# Calculate forces
		for i in range(num_samples):
			for j in range(num_samples):
				if i == j:
					continue

				var direction: Vector2 = positions[j] - positions[i]
				var distance_2d: float = direction.length()
				if distance_2d < 0.001:
					direction = Vector2(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1))
					distance_2d = direction.length()

				direction = direction.normalized()

				# Attractive forces for close points in high-dim space
				var attraction: float = -distances[i][j] * 0.01
				# Repulsive forces to prevent overlap
				var repulsion: float = 0.05 / max(0.1, distance_2d * distance_2d)

				forces[i] += direction * (attraction + repulsion)

		# Apply forces with dampening
		var dampening: float = 0.9 / (iteration + 1)
		for i in range(num_samples):
			positions[i] += forces[i] * dampening

	return positions


# Update the visualization with new 2D points
func update_visualization(new_points: Array[Vector2]) -> void:
	points_2d = new_points
	_normalize_points()
	canvas.queue_redraw()


# Scale and center points to fit in the viewport
func _normalize_points() -> void:
	if points_2d.size() < 1:
		return

	# Find min/max coordinates
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF

	for point in points_2d:
		min_x = min(min_x, point.x)
		max_x = max(max_x, point.x)
		min_y = min(min_y, point.y)
		max_y = max(max_y, point.y)

	# Calculate scale factor to fit all points with padding
	var width: float = max_x - min_x
	var height: float = max_y - min_y

	if width < 0.001 or height < 0.001:
		scale_factor = 1.0
	else:
		var viewport_width: float = sub_viewport.size.x - 2 * scale_padding
		var viewport_height: float = sub_viewport.size.y - 2 * scale_padding
		scale_factor = min(viewport_width / width, viewport_height / height) * 0.9  # 10% extra margin

	# Calculate center offset - THIS IS THE KEY PART THAT WAS MISSING
	var center_offset_x: float = (min_x + max_x) / 2
	var center_offset_y: float = (min_y + max_y) / 2

	# Store center offset for use in transform_point
	canvas_center = Vector2(sub_viewport.size.x / 2, sub_viewport.size.y / 2)
	# Store the data center for transformation
	data_center = Vector2(center_offset_x, center_offset_y)


# Draw the visualization
func _draw_visualization() -> void:
	if points_2d.size() < 1:
		return

	var draw = canvas.get_canvas_item()

	# Debug: Draw viewport boundaries
	var boundary_color = Color.RED
	canvas.draw_rect(Rect2(Vector2(0, 0), sub_viewport.size), boundary_color, false, 2.0)

	# Debug: Draw center point
	canvas.draw_circle(canvas_center, 5.0, Color.GREEN)

	# Draw lines connecting points
	if points_2d.size() > 1:
		for i in range(1, points_2d.size()):
			var start_pos = _transform_point(points_2d[i - 1])
			var end_pos = _transform_point(points_2d[i])
			canvas.draw_line(start_pos, end_pos, line_color, line_width)

	# Draw points
	for point in points_2d:
		var pos = _transform_point(point)
		canvas.draw_circle(pos, point_radius, point_color)

	# Debug: Print transformation info
	print("Canvas center: ", canvas_center)
	print("Data center: ", data_center)
	print("Scale factor: ", scale_factor)
	if points_2d.size() > 0:
		print("First point raw: ", points_2d[0])
		print("First point transformed: ", _transform_point(points_2d[0]))


# Transform a point from normalized space to canvas space
func _transform_point(point: Vector2) -> Vector2:
	# Apply offset from data center, then scale, then position at canvas center
	var centered_point = point - data_center
	return Vector2(
		canvas_center.x + centered_point.x * scale_factor,
		canvas_center.y + centered_point.y * scale_factor
	)


# Handle periodic updates (optional)
func _on_update_timer_timeout() -> void:
	# This could be used for animations or dynamic layout adjustments
	if points_2d.size() > 0:
		canvas.queue_redraw()


# Resize handler
func _on_sub_viewport_size_changed() -> void:
	print("Viewport size changed to: ", sub_viewport.size)
	canvas_center = Vector2(sub_viewport.size.x / 2, sub_viewport.size.y / 2)
	_normalize_points()
	canvas.queue_redraw()
