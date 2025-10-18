package main

import "core:fmt"
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

		// Calculate delta time
		delta_time := rl.GetFrameTime()

		// Update game
		game.update_game(&game_state, delta_time)

		// Draw game
		renderer.draw_game(&game_renderer)

		free_all(context.temp_allocator)
	}
}
