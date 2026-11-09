package renderer

import "../game"
import "core:c"
import rl "vendor:raylib"

// Tower tuning panel geometry
PANEL_WIDTH :: 340
PANEL_HEIGHT :: 190
PANEL_PADDING :: 12
PANEL_TOP_OFFSET :: 34
ROW_HEIGHT :: 26
ROW_SPACING :: 8
LABEL_COLUMN :: 80 // Room for the label raygui draws left of a control
VALUE_COLUMN :: 70 // Room for the value raygui draws right of a slider

TUNING_PANEL :: rl.Rectangle {
	game.SCREEN_WIDTH - PANEL_WIDTH - 20,
	90,
	PANEL_WIDTH,
	PANEL_HEIGHT,
}

// Bounds of a panel row, laid out top to bottom.
// Raygui draws a control's label left of its bounds and a slider's value
// right of them, so both columns are reserved inside the panel.
tuning_row :: proc(index: int) -> rl.Rectangle {
	return rl.Rectangle {
		TUNING_PANEL.x + PANEL_PADDING + LABEL_COLUMN,
		TUNING_PANEL.y + PANEL_TOP_OFFSET + f32(index) * (ROW_HEIGHT + ROW_SPACING),
		TUNING_PANEL.width - 2 * PANEL_PADDING - LABEL_COLUMN - VALUE_COLUMN,
		ROW_HEIGHT,
	}
}

// Draw the interactive tower tuning panel (raygui).
// Changes are written straight to the tower and applied on the next update.
draw_tower_panel :: proc(renderer: ^Renderer) {
	if !renderer.panel_visible || renderer.world == nil {
		return
	}

	tower := &renderer.world.tower

	rl.GuiPanel(TUNING_PANEL, "Tower Tuning")

	// Damage affects projectiles fired after this frame.
	// The spinner arrows work without edit mode, which raygui requires the
	// caller to track for keyboard input.
	damage := c.int(tower.damage)
	rl.GuiSpinner(
		tuning_row(0),
		"Damage",
		&damage,
		c.int(game.MIN_TOWER_DAMAGE),
		c.int(game.MAX_TOWER_DAMAGE),
		false,
	)
	tower.damage = int(damage)

	// Range is gameplay data in meters; the range circle is redrawn from it
	range := tower.range
	rl.GuiSliderBar(
		tuning_row(1),
		"Range",
		rl.TextFormat("%.1f m", range),
		&range,
		game.MIN_TOWER_RANGE,
		game.MAX_TOWER_RANGE,
	)
	tower.range = range

	cooldown := tower.cooldown
	rl.GuiSliderBar(
		tuning_row(2),
		"Cooldown",
		rl.TextFormat("%.2f s", cooldown),
		&cooldown,
		game.MIN_TOWER_COOLDOWN,
		game.MAX_TOWER_COOLDOWN,
	)
	tower.cooldown = cooldown

	if rl.GuiButton(tuning_row(3), "Reset defaults") {
		game.reset_tower_tuning(tower)
	}

	// Value boxes accept typed input, so validate every frame
	game.clamp_tower_tuning(tower)
}
