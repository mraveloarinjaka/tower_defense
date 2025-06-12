# Tower Defense Game

A single-tower defense game created with the Odin programming language, using Box2D for physics and Raylib for graphics.

## Overview

This tower defense game features a single tower that must defend against waves of enemies approaching from all sides. The game demonstrates the integration between Box2D physics and Raylib rendering.

## Features

- Single tower with attack capabilities
- Multiple enemy types with different characteristics
- Physics-based movement and collisions using Box2D
- Real-time rendering with Raylib
- Score tracking and wave progression
- Debug mode to visualize physics bodies

## Game Mechanics

- The tower automatically targets and fires at the closest enemy
- Enemies spawn from the edges of the screen and move toward the tower
- When enemies reach the tower, they damage it and reduce player lives
- The game ends when all lives are lost
- Waves become progressively more difficult with faster spawn rates and tougher enemies

## Controls

- **Enter**: Start game from menu / Restart after game over
- **F1**: Toggle debug mode (shows physics bodies and debug information)
- **ESC**: Exit game

## Technical Implementation

### Box2D and Raylib Integration

This game serves as a demonstration of how Raylib can render Box2D physics objects. The integration works as follows:

1. **Physics System (Box2D)**
   - Handles all collision detection and resolution
   - Manages object movement and forces
   - Maintains the physical state of all game entities

2. **Rendering System (Raylib)**
   - Translates physical positions to screen coordinates
   - Renders game objects based on their physical properties
   - Provides visual feedback for game state

3. **Coordinate Conversion**
   - Box2D uses a meter-based coordinate system
   - Raylib uses a pixel-based coordinate system
   - The `PHYSICS_SCALE` constant (30 pixels per meter) handles the conversion

### Project Structure

- `src/`: Contains all source code files
  - `main.odin`: Entry point of the application
  - `game/game.odin`: Game logic and mechanics
  - `physics/physics.odin`: Box2D physics integration
  - `renderer/renderer.odin`: Raylib rendering of Box2D objects

## Building and Running

## Requirements

- macOS operating system
- Odin programming language
- LLVM
- Xcode Command Line Tools

## License

This project is provided as-is for educational purposes.

## Acknowledgments

- The Odin programming language team
- Raylib developers
- Box2D physics engine
