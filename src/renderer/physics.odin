package renderer

import "../game"
import "../physics"
import "core:math"
import b2 "vendor:box2d"
import rl "vendor:raylib"

// Draw a physics body
draw_body :: proc(
	renderer: ^Renderer,
	body_name: string,
	color: rl.Color,
	texture: rl.Texture2D = {},
) {
	if renderer.world == nil {
		return
	}

	body, exists := renderer.world.physics.bodies[body_name]
	if !exists {return}

	// Get body position
	position := b2.Body_GetPosition(body)
	body_x := position.x * PHYSICS_SCALE
	body_y := position.y * PHYSICS_SCALE

	// Get body angle
	rotation := b2.Body_GetRotation(body)
	angle := b2.Rot_GetAngle(rotation)

	// Get shape
	//shapes: [shape_count]b2.ShapeId
	shape_count := b2.Body_GetShapeCount(body)
	shapes := make([dynamic]b2.ShapeId, shape_count)
	defer (delete(shapes))

	shape := b2.Body_GetShapes(body, shapes[:])

	if shape == nil {
		return
	}

	shape_type := b2.Shape_GetType(shape[0])

	#partial switch shape_type {
	case .circleShape:
		circle_shape := b2.Shape_GetCircle(shape[0])
		radius := circle_shape.radius * PHYSICS_SCALE

		if texture.id != 0 {
			// Draw textured circle
			source_rec := rl.Rectangle{0, 0, f32(texture.width), f32(texture.height)}
			dest_rec := rl.Rectangle{body_x, body_y, radius * 2, radius * 2}
			origin := rl.Vector2{radius, radius}

			rl.DrawTexturePro(
				texture,
				source_rec,
				dest_rec,
				origin,
				angle * 180.0 / 3.14159,
				rl.WHITE,
			)
		} else {
			// Draw colored circle
			rl.DrawCircleV(rl.Vector2{body_x, body_y}, radius, color)

			// Draw a line to show rotation
			end_x := body_x + radius * math.cos(angle)
			end_y := body_y + radius * math.sin(angle)
			rl.DrawLineV(rl.Vector2{body_x, body_y}, rl.Vector2{end_x, end_y}, rl.BLACK)
		}
	case .polygonShape:
		polygon_shape := b2.Shape_GetPolygon(shape[0])
		polygon_transform := b2.Body_GetTransform(body)
		//vertex_count := polygon_shape.count
		vertex_count := 4

		if vertex_count > 0 {
			// Draw polygon
			for i in 0 ..< vertex_count {
				startV := polygon_shape.vertices[i]
				screenStartV := rl.Vector2 {
					body_x + startV.x * PHYSICS_SCALE,
					body_y + startV.y * PHYSICS_SCALE,
				}
				j := (i + 1) % vertex_count
				endV := polygon_shape.vertices[j]
				screenEndV := rl.Vector2 {
					body_x + endV.x * PHYSICS_SCALE,
					body_y + endV.y * PHYSICS_SCALE,
				}
				rl.DrawLineV(screenStartV, screenEndV, rl.BLACK)
			}
		}
	}

	// Draw debug info if enabled
	if renderer.debug_mode {
		// Draw body type indicator
		body_type := b2.Body_GetType(body)
		debug_color: rl.Color

		if body_type == .staticBody {
			debug_color = DEBUG_COLOR_STATIC
		} else if body_type == .dynamicBody {
			debug_color = DEBUG_COLOR_DYNAMIC
		} else {
			debug_color = DEBUG_COLOR_JOINT
		}

		// Draw a small indicator circle
		rl.DrawCircleV(rl.Vector2{body_x, body_y}, 3, debug_color)

		// Draw sensor indicator if it's a sensor
		if b2.Shape_IsSensor(shape[0]) {
			rl.DrawCircleLines(cast(i32)body_x, cast(i32)body_y, 5, DEBUG_COLOR_SENSOR)
		}
	}
}

