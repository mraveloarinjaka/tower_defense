package renderer

import "core:c"
import "core:math"
import "../game"
import "../physics"
import rl "vendor:raylib"

// Debug drawing colors
DEBUG_COLOR_STATIC :: rl.BLUE
DEBUG_COLOR_DYNAMIC :: rl.RED
DEBUG_COLOR_SENSOR :: rl.GREEN
DEBUG_COLOR_JOINT :: rl.PURPLE

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

// Arrow-key pan speed in screen pixels per second at 1.0x zoom. The applied
// render-space step is divided by the camera zoom so on-screen speed is
// consistent at every zoom level.
CAMERA_PAN_SPEED :: 500.0

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

// True when the renderer has a world and that world is actively playing.
// Gameplay-only systems (camera input, etc.) guard on this so they stay inert
// while the menu or game-over screen is showing.
is_playing :: proc(renderer: ^Renderer) -> bool {
	return renderer != nil && renderer.world != nil && renderer.world.state == .PLAYING
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
	if !is_playing(renderer) {
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

// Arrow-key camera panning during gameplay.
// Held arrow keys pan the world camera at a frame-rate-independent speed that
// is divided by the camera zoom, so on-screen motion stays constant across zoom
// levels. Diagonal input is normalized to cardinal speed. The viewport center
// (not the raw camera target) is clamped to the arena bounds, which keeps the
// bounds correct even after cursor-anchored zoom moved camera.offset/target.
update_camera_pan :: proc(renderer: ^Renderer, delta_time: f32) {
	if !is_playing(renderer) {
		return
	}

	dir: rl.Vector2
	if rl.IsKeyDown(.LEFT) {dir.x -= 1.0}
	if rl.IsKeyDown(.RIGHT) {dir.x += 1.0}
	if rl.IsKeyDown(.UP) {dir.y -= 1.0}
	if rl.IsKeyDown(.DOWN) {dir.y += 1.0}

	// Normalize so diagonal panning is not sqrt(2) faster than cardinal.
	// Zero input leaves dir at zero, so no pan step is applied this frame.
	len := math.sqrt(dir.x * dir.x + dir.y * dir.y)
	if len > 0 {
		dir.x /= len
		dir.y /= len
	}

	step := (CAMERA_PAN_SPEED / renderer.camera.zoom) * delta_time
	renderer.camera.target += dir * step

	// Clamp the viewport center to the arena on every .PLAYING frame, not only
	// while an arrow is held. Deriving it from the camera transform handles
	// non-centered offsets left by cursor-anchored zoom.
	screen_center := rl.Vector2{f32(game.SCREEN_WIDTH) / 2.0, f32(game.SCREEN_HEIGHT) / 2.0}
	world_max := world_to_render(game.WORLD_WIDTH, game.WORLD_HEIGHT)
	view_center := rl.GetScreenToWorld2D(screen_center, renderer.camera)
	clamped_center := rl.Vector2 {
		clamp(view_center.x, 0, world_max.x),
		clamp(view_center.y, 0, world_max.y),
	}
	renderer.camera.target += clamped_center - view_center
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
		draw_tower(renderer, renderer.world.tower.id, renderer.world.tower.range)
		for enemy in renderer.world.enemies {
			if enemy.active {
				draw_enemy(renderer, enemy.id, enemy.type)
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
draw_tower :: proc(renderer: ^Renderer, body_name: string, range: f32 = 0) {
	if renderer.world == nil {
		return
	}

	// Draw the tower body
	draw_body(renderer, body_name, rl.BLUE)

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
draw_enemy :: proc(renderer: ^Renderer, body_name: string, enemy_type: game.EnemyType) {
	if renderer.world == nil {
		return
	}

	// Draw the enemy body, colored by enemy type
	draw_body(renderer, body_name, ENEMY_COLORS[enemy_type])
}

// Draw a projectile
draw_projectile :: proc(renderer: ^Renderer, body_name: string) {
	if renderer.world == nil {
		return
	}

	// Draw the projectile body
	draw_body(renderer, body_name, PROJECTILE_COLOR)
}

// Draw game boundaries
draw_boundaries :: proc(renderer: ^Renderer) {
	draw_body(renderer, physics.WALLS[.TOP], rl.DARKGRAY)
	draw_body(renderer, physics.WALLS[.BOTTOM], rl.DARKGRAY)
	draw_body(renderer, physics.WALLS[.LEFT], rl.DARKGRAY)
	draw_body(renderer, physics.WALLS[.RIGHT], rl.DARKGRAY)
}

// Toggle debug mode
toggle_debug_mode :: proc(renderer: ^Renderer) {
	renderer.debug_mode = !renderer.debug_mode
}

// Toggle the tower tuning panel
toggle_tower_panel :: proc(renderer: ^Renderer) {
	renderer.panel_visible = !renderer.panel_visible
}
