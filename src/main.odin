package main

import "core:log"
import "core:math/rand"
import "core:time"
import "game"
import "renderer"

import rl "vendor:raylib"

main :: proc() {
	context.logger = log.create_console_logger()
	context.logger.lowest_level = log.Level.Debug

	// Initialize window
	rl.InitWindow(game.SCREEN_WIDTH, game.SCREEN_HEIGHT, game.TITLE)
	defer rl.CloseWindow()
	rl.SetExitKey(.KEY_NULL)

	rl.SetTargetFPS(game.TARGET_FPS)

	// Initialize random seed
	rand.reset(u64(time.now()._nsec))

	// Initialize game
	game_state := game.init_game()
	defer game.destroy_game(&game_state)
	game_renderer := renderer.init_renderer(&game_state)

	// Main game loop
	game_loop: for !rl.WindowShouldClose() {
		// Handle input
		if game.handle_input(&game_state) == .QUIT {
			break game_loop
		}

		if rl.IsKeyPressed(.F1) {
			renderer.toggle_debug_mode(&game_renderer)
		}
		if rl.IsKeyPressed(.F2) {
			renderer.toggle_tower_panel(&game_renderer)
		}

		renderer.update_camera_zoom(&game_renderer)

		delta_time := rl.GetFrameTime()

		game.update_game(&game_state, delta_time)

		renderer.draw_game(&game_renderer)

		free_all(context.temp_allocator)
	}
}
