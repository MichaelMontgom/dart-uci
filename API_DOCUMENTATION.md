# Dart UCI Package API Documentation

## Overview

The Dart UCI package provides a high-level interface for communicating with UCI (Universal Chess Interface) compatible chess engines like Stockfish. This package allows you to:

- Start and manage chess engine processes
- Set board positions using FEN notation or move sequences  
- Get best moves with various search parameters
- Analyze positions with real-time analysis streams
- Configure engine options
- Handle engine communication robustly with proper error handling

## Quick Start

```dart
import 'package:dart_uci/dart_uci.dart';

void main() async {
  final engine = UCIChessEngine('/path/to/stockfish');
  
  try {
    await engine.start();
    await engine.initialize();
    
    await engine.setPosition(fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1');
    final bestMove = await engine.getBestMove(depth: 15);
    print('Best move: $bestMove');
    
    final analysisStream = await engine.analyze(timeMs: 5000);
    await for (final analysis in analysisStream) {
      print('Depth: ${analysis.depth}, Score: ${analysis.score}');
    }
  } finally {
    await engine.stop();
  }
}
```

## Classes

### UCIChessEngine

The main class for interacting with UCI chess engines.

#### Constructor

```dart
UCIChessEngine(String enginePath)
```

Creates a new UCI chess engine instance.

**Parameters:**
- `enginePath`: File system path to the UCI chess engine executable

#### Methods

##### start()

```dart
Future<void> start()
```

Starts the chess engine process and sets up communication streams.

**Throws:** `UCIException` if engine is already running or cannot be started.

##### initialize()

```dart
Future<EngineInfo> initialize()
```

Initializes the UCI protocol and retrieves engine information.

**Returns:** `EngineInfo` containing engine name, author, and options.

**Throws:** `UCIException` if engine doesn't respond properly.

##### setPosition()

```dart
Future<void> setPosition({String? fen, List<UCIMove>? moves})
```

Sets the current board position for analysis or move generation.

**Parameters:**
- `fen`: FEN string representing the position (optional)
- `moves`: List of UCI moves to apply (optional)

**Examples:**
```dart
// Starting position
await engine.setPosition();

// Specific position via FEN
await engine.setPosition(fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1');

// Position via moves
await engine.setPosition(moves: [UCIMove.fromString('e2e4'), UCIMove.fromString('e7e5')]);
```

##### getBestMove()

```dart
Future<UCIMove> getBestMove({int? depth, int? timeMs, int? nodes})
```

Gets the best move for the current position.

**Parameters:**
- `depth`: Maximum search depth in half-moves (optional)
- `timeMs`: Maximum search time in milliseconds (optional)  
- `nodes`: Maximum number of positions to search (optional)

**Returns:** The best `UCIMove` found by the engine.

**Throws:** `UCIException` if search times out or engine doesn't respond.

**Examples:**
```dart
final move1 = await engine.getBestMove(depth: 15);
final move2 = await engine.getBestMove(timeMs: 2000);
final move3 = await engine.getBestMove(nodes: 1000000);
```

##### analyze()

```dart
Future<Stream<EngineAnalysis>> analyze({int? depth, int? timeMs})
```

Analyzes the current position and returns a stream of analysis data.

**Parameters:**
- `depth`: Maximum search depth (optional)
- `timeMs`: Maximum search time in milliseconds (optional)

**Returns:** `Stream<EngineAnalysis>` providing real-time analysis updates.

**Examples:**
```dart
// Analyze for 5 seconds
final stream = await engine.analyze(timeMs: 5000);
await for (final analysis in stream) {
  print('Depth ${analysis.depth}: ${analysis.score} cp');
}

// Analyze to specific depth
final stream = await engine.analyze(depth: 20);
await for (final analysis in stream) {
  print('${analysis.nodes} nodes searched');
}
```

##### setOption()

```dart
Future<void> setOption(String name, dynamic value)
```

Sets an engine-specific option.

**Parameters:**
- `name`: Name of the option to set
- `value`: Value for the option

**Examples:**
```dart
await engine.setOption('Hash', 256);        // 256MB hash table
await engine.setOption('Threads', 4);       // Use 4 threads
await engine.setOption('Ponder', true);     // Enable pondering
```

##### isReady()

```dart
Future<bool> isReady()
```

Checks if the engine is ready to receive commands.

**Returns:** `true` if engine is ready, `false` otherwise.

##### stopAnalysis()

```dart
Future<void> stopAnalysis()
```

Stops the current analysis or search operation.

##### newGame()

```dart
Future<void> newGame()
```

Sets up a new game, clearing the engine's internal state.

##### stop()

```dart
Future<void> stop()
```

Stops the engine process and cleans up all resources.

### EngineInfo

Contains information about a UCI chess engine.

#### Properties

- `String name`: The engine's name
- `String author`: The engine's author(s)
- `Map<String, dynamic> options`: Available engine options

### EngineAnalysis

Represents the result of engine analysis for a chess position.

#### Properties

- `int depth`: Search depth reached (half-moves)
- `int score`: Position evaluation in centipawns
- `List<UCIMove> principalVariation`: Best line of play found
- `int nodes`: Number of positions searched
- `int timeMs`: Time spent searching in milliseconds

### UCIMove

Represents a chess move in UCI format.

#### Properties

- `String from`: Starting square (e.g., "e2")
- `String to`: Destination square (e.g., "e4")
- `String? promotion`: Promotion piece ('q', 'r', 'b', 'n') or null

#### Methods

##### fromString()

```dart
static UCIMove fromString(String moveString)
```

Creates a UCI move from a string representation.

**Examples:**
```dart
final move1 = UCIMove.fromString('e2e4');     // Normal move
final move2 = UCIMove.fromString('e7e8q');    // Promotion to queen
final move3 = UCIMove.fromString('e1g1');     // Castling
```

### UCIException

Exception thrown by UCI chess engine operations.

#### Properties

- `String message`: Error description

## Common Patterns

### Basic Engine Usage

```dart
final engine = UCIChessEngine('/path/to/engine');
try {
  await engine.start();
  await engine.initialize();
  // ... use engine
} finally {
  await engine.stop();  // Always clean up
}
```

### Position Setup

```dart
// From starting position with moves
await engine.setPosition(moves: [
  UCIMove.fromString('e2e4'),
  UCIMove.fromString('e7e5'),
]);

// From FEN notation
await engine.setPosition(fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1');
```

### Analysis Stream Processing

```dart
final analysisStream = await engine.analyze(timeMs: 10000);
var bestScore = -999999;
UCIMove? bestMove;

await for (final analysis in analysisStream) {
  if (analysis.score > bestScore) {
    bestScore = analysis.score;
    if (analysis.principalVariation.isNotEmpty) {
      bestMove = analysis.principalVariation.first;
    }
  }
  
  if (analysis.depth >= 15) break; // Stop at desired depth
}
```

### Engine Configuration

```dart
await engine.setOption('Hash', 512);           // 512MB hash
await engine.setOption('Threads', 8);          // 8 threads
await engine.setOption('MultiPV', 3);          // Show 3 best lines
await engine.setOption('UCI_ShowWDL', true);   // Show win/draw/loss

if (await engine.isReady()) {
  print('Engine configured and ready');
}
```

## Error Handling

All methods that communicate with the engine can throw `UCIException`. Always use try-catch blocks and ensure proper cleanup:

```dart
try {
  final move = await engine.getBestMove(depth: 20);
  print('Best move: $move');
} on UCIException catch (e) {
  print('Engine error: ${e.message}');
} finally {
  await engine.stop();
}
```

## Performance Considerations

- Use appropriate search limits (depth/time/nodes) based on your needs
- Configure engine options like hash size and thread count for your hardware
- Close analysis streams when done to free resources
- Always call `stop()` to clean up engine processes
- Consider using `isReady()` before critical operations

## Thread Safety

This package is not thread-safe. Use a single instance per engine process and don't call methods concurrently from multiple isolates.
