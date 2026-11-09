package renderer

import "../game"
import "../physics"
import "core:c"
import "core:fmt"
import "core:math"
import "core:strings"
import b2 "vendor:box2d"
import rl "vendor:raylib"

// Debug drawing colors
DEBUG_COLOR_STATIC :: rl.BLUE
DEBUG_COLOR_DYNAMIC :: rl.RED
DEBUG_COLOR_SENSOR :: rl.GREEN
DEBUG_COLOR_JOINT :: rl.PURPLE
DEBUG_COLOR_AABB :: rl.SKYBLUE
DEBUG_COLOR_SHAPE :: rl.DARKBLUE

// Enemy colors, indexed by enemy type
ENEMY_COLORS := [game.EnemyType]rl.Color {
	.BASIC = rl.ORANGE,
	.FAST  = {255, 220, 0, 255}, // yellow
	.TANK  = {160, 60, 200, 255}, // purple
}
PROJECTILE_COLOR :: rl.Color{57, 255, 20, 255} // bright neon green

PHYSICS_SCALE :: physics.PHYSICS_SCALE

// --- World (meters) <-> render (pixels) conversion --------------------------
// The renderer is the only layer that knows about pixels for world geometry.
// Physics and game data are always expressed in meters.

// Convert a world position in meters to a render-space position in pixels.
world_to_render :: proc(x, y: f32) -> rl.Vector2 {
	return rl.Vector2{x * PHYSICS_SCALE, y * PHYSICS_SCALE}
}

// Convert a world distance/radius in meters to render pixels.
meters_to_render :: proc(meters: f32) -> f32 {
	return meters * PHYSICS_SCALE
}

// Convert a render distance/radius in pixels back to world meters.
render_to_meters :: proc(pixels: f32) -> f32 {
	return pixels / PHYSICS_SCALE
}

// Convert a screen position in pixels to a world position in meters.
// Screen pixels are first unprojected through the active Camera2D (offset,
// target, zoom), then the resulting render-space pixels are scaled to meters.
screen_to_world :: proc(renderer: ^Renderer, screen_pos: rl.Vector2) -> physics.WorldPosition {
	render_pos := rl.GetScreenToWorld2D(screen_pos, renderer.camera)
	return physics.WorldPosition{render_pos.x / PHYSICS_SCALE, render_pos.y / PHYSICS_SCALE}
}

// Debug overlay marker sizes in render pixels. These are screen-space
// decorations, not world sizes, so they are not converted from meters.
DEBUG_BODY_MARKER_RADIUS :: 3
DEBUG_SENSOR_RADIUS :: 5
PATH_POINT_RADIUS :: 3

// Camera zoom limits and wheel sensitivity. Zoom is a multiplier applied by
// Camera2D around the render-space point under the cursor.
DEFAULT_CAMERA_ZOOM :: 1.0
MIN_CAMERA_ZOOM :: 0.25
MAX_CAMERA_ZOOM :: 4.0
CAMERA_ZOOM_STEP :: 0.125

// Renderer context
Renderer :: struct {
	world:         ^game.Game,
	debug_mode:    bool,
	panel_visible: bool,
	camera:        rl.Camera2D,
}

// Initialize renderer
init_renderer :: proc(world: ^game.Game) -> Renderer {
	renderer: Renderer
	renderer.world = world
	renderer.debug_mode = true
	renderer.panel_visible = false

	// Keep the tower tuning panel readable with the default font
	rl.GuiSetStyle(.DEFAULT, c.int(rl.GuiDefaultProperty.TEXT_SIZE), 18)

	reset_camera(&renderer)

	return renderer
}

// Restore the camera to its default: 1:1 render pixels, centered on the arena.
// The target is the arena center in render pixels; the offset stays at the
// viewport center so that point appears in the middle of the screen.
reset_camera :: proc(renderer: ^Renderer) {
	center := rl.Vector2{f32(game.SCREEN_WIDTH) / 2.0, f32(game.SCREEN_HEIGHT) / 2.0}
	renderer.camera.offset = center
	renderer.camera.target = world_to_render(game.WORLD_WIDTH / 2.0, game.WORLD_HEIGHT / 2.0)
	renderer.camera.rotation = 0.0
	renderer.camera.zoom = DEFAULT_CAMERA_ZOOM
}

// Cursor-centered mouse-wheel zoom during gameplay.
// The world point under the cursor is computed before the camera changes, then
// kept anchored by moving both the camera offset and target to it. Wheel input
// over the visible tuning panel is ignored so raygui stays usable.
update_camera_zoom :: proc(renderer: ^Renderer) {
	if renderer.world == nil || renderer.world.state != .PLAYING {
		return
	}

	if rl.IsKeyPressed(.R) || rl.IsMouseButtonPressed(.MIDDLE) {
		reset_camera(renderer)
	}

	wheel := rl.GetMouseWheelMove()
	if wheel == 0 {
		return
	}

	mouse_screen := rl.GetMousePosition()
	if renderer.panel_visible && rl.CheckCollisionPointRec(mouse_screen, TUNING_PANEL) {
		return
	}

	// Unproject the cursor through the current camera before mutating it.
	mouse_world := rl.GetScreenToWorld2D(mouse_screen, renderer.camera)
	renderer.camera.offset = mouse_screen
	renderer.camera.target = mouse_world
	renderer.camera.zoom = clamp(
		renderer.camera.zoom + wheel * CAMERA_ZOOM_STEP,
		MIN_CAMERA_ZOOM,
		MAX_CAMERA_ZOOM,
	)
}

// Begin rendering frame. Screen-space drawing only; world geometry must be
// wrapped in begin_world/end_world so the HUD, menus and raygui stay unaffected
// by the camera.
begin_render :: proc(renderer: ^Renderer, clear_color: rl.Color) {
	rl.BeginDrawing()
	rl.ClearBackground(clear_color)
}

// End rendering frame
end_render :: proc(renderer: ^Renderer) {
	rl.EndDrawing()
}

// Begin drawing world geometry (boundaries, entities, debug overlays).
// Everything drawn here is expressed in meters and converted to render pixels.
begin_world :: proc(renderer: ^Renderer) {
	rl.BeginMode2D(renderer.camera)
}

// End world geometry drawing, returning to screen space for UI.
end_world :: proc(renderer: ^Renderer) {
	rl.EndMode2D()
}

// Draw the game
draw_game :: proc(renderer: ^Renderer) {
	begin_render(renderer, rl.RAYWHITE)
	defer end_render(renderer)

	if renderer.world.state == .MENU {
		draw_menu()
	} else if renderer.world.state == .PLAYING {
		begin_world(renderer)
		draw_boundaries(renderer)
		draw_tower(renderer, renderer.world.tower.id, {}, renderer.world.tower.range)
		for enemy in renderer.world.enemies {
			if enemy.active {
				draw_enemy(renderer, enemy.id, enemy.type, {}, enemy.health, enemy.max_health)
			}
		}
		for projectile in renderer.world.projectiles {
			if projectile.active {
				draw_projectile(renderer, projectile.id)
			}
		}
		end_world(renderer)

		// Screen-space UI
		draw_hud(renderer)
		draw_tower_panel(renderer)
	} else if renderer.world.state == .GAME_OVER {
		draw_game_over(renderer.world.score)
	}
}

// Draw a tower
draw_tower :: proc(
	renderer: ^Renderer,
	body_name: string,
	texture: rl.Texture2D = {},
	range: f32 = 0,
) {
	if renderer.world == nil {
		return
	}

	// Draw the tower body
	draw_body(renderer, body_name, rl.BLUE, texture)

	// Draw range indicator if specified (range is in meters)
	if range > 0 {
		x, y := physics.get_body_position(&renderer.world.physics, body_name)
		center := world_to_render(x, y)

		// Draw range circle with transparency
		range_color := rl.SKYBLUE
		range_color.a = 100
		rl.DrawCircleLines(cast(i32)center.x, cast(i32)center.y, meters_to_render(range), range_color)
	}
}

// Draw an enemy
draw_enemy :: proc(
	renderer: ^Renderer,
	body_name: string,
	enemy_type: game.EnemyType,
	texture: rl.Texture2D = {},
	health: int = 0,
	max_health: int = 0,
) {
	if renderer.world == nil {
		return
	}

	// Draw the enemy body, colored by enemy type
	draw_body(renderer, body_name, ENEMY_COLORS[enemy_type], texture)

	// Draw health bar if health is provided
	//if max_health > 0 {
	//   x, y := physics.get_body_position(renderer.world.physics, body_name)

	//   // Get body radius (assuming circular shape)
	//   body, exists := renderer.world.physics.bodies[body_name]
	//   if !exists {
	//      return
	//   }

	//   fixture := b2.get_fixture_list(body)
	//   if fixture == nil {
	//      return
	//   }

	//   shape := b2.get_shape(fixture)
	//   shape_type := b2.get_type(shape)

	//   radius: f32 = 10 // Default radius
	//   if shape_type == .CIRCLE {
	//      circle_shape := b2.get_circle(shape)
	//      radius = circle_shape.radius * physics.PHYSICS_SCALE
	//   }

	//   // Draw health bar above enemy
	//   bar_width := radius * 2
	//   bar_height := 5.0
	//   bar_x := x - radius
	//   bar_y := y - radius - 10

	//   // Background (empty) health bar
	//   rl.draw_rectangle(
	//      cast(i32)bar_x,
	//      cast(i32)bar_y,
	//      cast(i32)bar_width,
	//      cast(i32)bar_height,
	//      rl.GRAY,
	//   )

	//   // Filled health bar
	//   health_percent := f32(health) / f32(max_health)
	//   filled_width := bar_width * health_percent

	//   // Color based on health percentage
	//   health_color: rl.Color
	//   if health_percent > 0.6 {
	//      health_color = rl.GREEN
	//   } else if health_percent > 0.3 {
	//      health_color = rl.YELLOW
	//   } else {
	//      health_color = rl.RED
	//   }

	//   rl.draw_rectangle(
	//      cast(i32)bar_x,
	//      cast(i32)bar_y,
	//      cast(i32)filled_width,
	//      cast(i32)bar_height,
	//      health_color,
	//   )
	//}
}

// Draw a projectile
draw_projectile :: proc(renderer: ^Renderer, body_name: string, texture: rl.Texture2D = {}) {
	if renderer.world == nil {
		return
	}

	// Draw the projectile body
	draw_body(renderer, body_name, PROJECTILE_COLOR, texture)
}

// Draw game boundaries
draw_boundaries :: proc(renderer: ^Renderer) {
	draw_body(renderer, physics.WALLS[.TOP], rl.DARKGRAY)
	draw_body(renderer, physics.WALLS[.BOTTOM], rl.DARKGRAY)
	draw_body(renderer, physics.WALLS[.LEFT], rl.DARKGRAY)
	draw_body(renderer, physics.WALLS[.RIGHT], rl.DARKGRAY)
}

// Draw a path (for enemy movement). Points are world positions in meters.
draw_path :: proc(renderer: ^Renderer, points: []physics.WorldPosition, color: rl.Color) {
	if len(points) < 2 {
		return
	}

	// Draw lines connecting the points
	for i := 0; i < len(points) - 1; i += 1 {
		start := world_to_render(points[i][0], points[i][1])
		end := world_to_render(points[i + 1][0], points[i + 1][1])
		rl.DrawLineV(start, end, color)
	}

	// Draw points
	for point in points {
		rl.DrawCircleV(world_to_render(point[0], point[1]), PATH_POINT_RADIUS, color)
	}
}

// Draw explosion effect. Position is in world meters, radius in meters.
draw_explosion :: proc(renderer: ^Renderer, position: physics.WorldPosition, radius: f32, color: rl.Color) {
	center := world_to_render(position[0], position[1])
	render_radius := meters_to_render(radius)

	// Draw outer circle
	outer_color := color
	outer_color.a = 100
	rl.DrawCircleV(center, render_radius, outer_color)

	// Draw inner circle
	inner_color := color
	inner_color.a = 200
	rl.DrawCircleV(center, render_radius * 0.7, inner_color)

	// Draw center
	rl.DrawCircleV(center, render_radius * 0.3, rl.WHITE)
}

// Set camera position (world meters)
set_camera_position :: proc(renderer: ^Renderer, x, y: f32) {
	renderer.camera.target = world_to_render(x, y)
}

// Set camera zoom
set_camera_zoom :: proc(renderer: ^Renderer, zoom: f32) {
	renderer.camera.zoom = zoom
}

// Toggle debug mode
toggle_debug_mode :: proc(renderer: ^Renderer) {
	renderer.debug_mode = !renderer.debug_mode
}

// Toggle the tower tuning panel
toggle_tower_panel :: proc(renderer: ^Renderer) {
	renderer.panel_visible = !renderer.panel_visible
}
