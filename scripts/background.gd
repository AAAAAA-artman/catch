extends Control


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("11141f"))
	var horizon := Vector2(size.x * 0.5, size.y * 0.38)
	for i in range(1, 6):
		var y := lerpf(horizon.y, size.y, float(i * i) / 36.0)
		draw_line(Vector2(0, y), Vector2(size.x, y), Color("44313d"), 1.0)
	for x in [0.0, size.x * 0.2, size.x * 0.8, size.x]:
		draw_line(horizon, Vector2(x, size.y), Color("513943"), 2.0)
	draw_circle(horizon, 28.0, Color("86605e"))
