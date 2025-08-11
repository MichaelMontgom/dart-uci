# Dart UCI

A Dart package for interfacing with UCI (Universal Chess Interface) chess engines like Stockfish.

## Features

- **Engine Management**: Start, initialize, and stop UCI chess engines
- **Position Setup**: Set board positions using FEN notation or move sequences  
- **Move Analysis**: Get best moves with configurable search depth and time limits
- **Real-time Analysis**: Stream live engine evaluations with depth, score, and principal variations
- **Engine Configuration**: Set hash size, threads, and other engine-specific options
- **Robust Error Handling**: Comprehensive exception handling with timeouts

## Quick Start

```dart
import 'package:dart_uci/dart_uci.dart';

void main() async {
  final engine = UCIChessEngine('/path/to/stockfish');
  
  try {
    // Start and initialize engine
    await engine.start();
    await engine.initialize();
    
    // Set position and get best move
    await engine.setPosition(moves: [
      UCIMove.fromString('e2e4'),
      UCIMove.fromString('e7e5'),
    ]);
    
    final bestMove = await engine.getBestMove(depth: 15);
    print('Best move: $bestMove');
    
    // Analyze position with real-time updates
    final analysisStream = await engine.analyze(timeMs: 5000);
    await for (final analysis in analysisStream) {
      print('Depth: ${analysis.depth}, Score: ${analysis.score}');
    }
  } finally {
    await engine.stop();
  }
}
```

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  dart_uci: ^1.0.0
```

Then run:
```bash
dart pub get
```

## Requirements

- A UCI-compatible chess engine (e.g., [Stockfish](https://stockfishchess.org/))
- Dart SDK 2.17.0 or higher

## Documentation

- [API Documentation](API_DOCUMENTATION.md) - Complete API reference with examples
- [Example Usage](example/dart_uci_example.dart) - Working example with analysis streams

## License

This project is licensed under the MIT License.
