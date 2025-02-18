extends Node


func get_formatted_datetime():
	var dt = Time.get_datetime_dict_from_system()

	# Convert 24-hour to 12-hour format with AM/PM
	var hour = dt.hour
	var period = "AM"
	if hour >= 12:
		period = "PM"
		if hour > 12:
			hour -= 12
	elif hour == 0:
		hour = 12

	# Format with leading zeros where needed
	var formatted = (
		"%02d/%02d/%04d %02d:%02d %s" % [dt.day, dt.month, dt.year, hour, dt.minute, period]
	)

	return formatted
