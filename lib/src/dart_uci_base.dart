import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A UCI (Universal Chess Interface) chess engine wrapper for Dart.
/// 
/// This class provides a high-level interface for communicating with UCI-compatible
/// chess engines like Stockfish, allowing you to:
/// - Start and initialize engines
/// - Set board positions using FEN notation or move sequences
/// - Get best moves with various search parameters
/// - Analyze positions and receive real-time analysis streams
/// - Configure engine options
/// 
/// Example usage:
/// ```dart
/// final engine = UCIChessEngine('/path/to/stockfish');
/// await engine.start();
/// await engine.initialize();
/// await engine.setPosition(fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
/// final bestMove = await engine.getBestMove(depth: 15);
/// await engine.stop();
/// ```
class UCIChessEngine {
  /// Path to the UCI chess engine executable
  final String _enginePath;
  
  /// The running engine process
  Process? _process;
  
  /// Broadcast stream controller for engine output lines
  StreamController<String>? _outputController;
  
  /// Broadcast stream controller for engine error output
  StreamController<String>? _errorController;
  
  /// Whether the engine has been successfully initialized
  bool _isInitialized = false;
  
  /// Information about the engine (name, author, options)
  EngineInfo? _engineInfo;
  
  /// Creates a new UCI chess engine instance.
  /// 
  /// [enginePath] The file system path to the UCI chess engine executable.
  /// This should be an absolute path to ensure the engine can be found.
  /// 
  /// Example:
  /// ```dart
  /// final engine = UCIChessEngine('/usr/local/bin/stockfish');
  /// // or on Windows:
  /// final engine = UCIChessEngine(r'C:\chess\stockfish.exe');
  /// ```
  UCIChessEngine(this._enginePath);

/// Starts the chess engine process and sets up communication streams.
/// 
/// This method launches the engine executable as a separate process and establishes
/// bidirectional communication through stdin/stdout. It creates broadcast streams
/// for both regular output and error output from the engine.
/// 
/// Must be called before any other engine operations.
/// 
/// Throws [UCIException] if:
/// - The engine is already running
/// - The engine executable cannot be found or started
/// - There are permission issues accessing the executable
/// 
/// Example:
/// ```dart
/// try {
///   await engine.start();
///   print('Engine started successfully');
/// } catch (e) {
///   print('Failed to start engine: $e');
/// }
/// ```
Future<void> start() async {
    if (_process != null) {
      throw UCIException('Engine is already running');
    }
    
    try {
      // Start the engine process
      _process = await Process.start(_enginePath, []);
      _outputController = StreamController<String>.broadcast();
      _errorController = StreamController<String>.broadcast();

      // Listen to engine output
      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _outputController!.add(line);
      });
      
      // Listen to engine errors
      _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _errorController!.add(line);
      });
      
    } catch (e) {
      throw UCIException('Failed to start engine at $_enginePath: $e');
    }
  }

    /// Initializes the UCI protocol with the engine and retrieves engine information.
    /// 
    /// This method sends the 'uci' command to the engine and waits for the engine
    /// to respond with its identification and available options. The engine must
    /// respond with 'uciok' to indicate successful UCI protocol initialization.
    /// 
    /// Returns an [EngineInfo] object containing:
    /// - Engine name and author
    /// - Available engine options and their types
    /// 
    /// Must be called after [start] and before other engine operations.
    /// 
    /// Throws [UCIException] if:
    /// - The engine process is not running
    /// - The engine doesn't provide a name
    /// - The engine doesn't respond with 'uciok'
    /// 
    /// Example:
    /// ```dart
    /// final info = await engine.initialize();
    /// print('Engine: ${info.name} by ${info.author}');
    /// print('Available options: ${info.options.keys}');
    /// ```
    Future<EngineInfo> initialize() async {
    if (_process == null) {
      throw UCIException('Engine not started. Call start() first.');
    }
    
    // tell the engine to use UCI protocol
    await sendCommand('uci');
    
    String? engineName;
    String? engineAuthor;
    Map<String, dynamic> options = {};
    
    final completer = Completer<EngineInfo>();
    late StreamSubscription subscription;
    
    subscription = _outputController!.stream.listen((line) {
      if (line.startsWith('id name ')) {
        engineName = line.substring(8);
      } else if (line.startsWith('id author ')) {
        engineAuthor = line.substring(10);
      } else if (line.startsWith('option name ')) {
        // Parse engine options
        final parts = line.split(' ');
        
        if (parts.length >= 3) {
          final optionName = parts[2];
          options[optionName] = line;
        }
      } else if (line == 'uciok') {
        subscription.cancel();
        
        if (engineName == null) {
          completer.completeError(UCIException('Engine did not provide a name'));
          return;
        }
        
        // Create EngineInfo object with gathered data
        _engineInfo = EngineInfo(
          name: engineName!,
          author: engineAuthor ?? 'Unknown',
          options: options,
        );

        print(_engineInfo.toString());

        _isInitialized = true;
        completer.complete(_engineInfo!);
      }
    });
    
    return completer.future;
  }

  /// Ensures the engine is properly initialized before executing commands.
  /// 
  /// This is an internal helper method that validates the engine state.
  /// 
  /// Throws [UCIException] if the engine is not initialized or not running.
  void _ensureInitialized() {
    if (_isInitialized == false || _process == null) {
      throw UCIException('Engine not initialized. Call initialize() first.');
    }
  }

  /// Stops the engine process and cleans up all resources.
  /// 
  /// This method sends a 'quit' command to the engine, terminates the process,
  /// and closes all communication streams. It's safe to call multiple times.
  /// 
  /// Should be called when you're done using the engine to prevent resource leaks.
  /// After calling this method, you must call [start] and [initialize] again
  /// before using the engine.
  /// 
  /// Example:
  /// ```dart
  /// try {
  ///   // ... use engine
  /// } finally {
  ///   await engine.stop(); // Always clean up
  /// }
  /// ```
  Future<void> stop() async {
    if (_process == null) {
      return;
    }

    //tell the engine to quit
    await sendCommand('quit');
    // Wait for the process to exit
    _process!.kill();
    await _process!.exitCode;
    _process = null;
    
    // Close the output and error streams
    await _outputController?.close();
    await _errorController?.close();
    _outputController = null;
    _errorController = null;
    _isInitialized = false;
  }

  /// Sends a raw UCI command to the engine.
  /// 
  /// This is a low-level method for sending commands directly to the engine.
  /// Most users should use the higher-level methods like [getBestMove],
  /// [analyze], [setPosition], etc.
  /// 
  /// [command] The UCI command string to send to the engine.
  /// 
  /// Throws [UCIException] if the engine process is not running.
  /// 
  /// Example:
  /// ```dart
  /// await engine.sendCommand('isready');
  /// await engine.sendCommand('go depth 15');
  /// ```
  Future<void> sendCommand(String command) async {
      if (_process == null) {
        throw UCIException('Engine process not running');
      }
      
      // Send the command to the engine
      _process!.stdin.writeln(command);
      await _process!.stdin.flush();
    }

    /// Sets up a new game, clearing the engine's internal state.
    /// 
    /// This sends the 'ucinewgame' command to the engine, which tells it to
    /// reset its internal state as if starting a new game. This is useful
    /// when switching between different games or positions.
    /// 
    /// Should be called before setting up a new position if you want to ensure
    /// the engine doesn't use any information from previous positions.
    /// 
    /// Throws [UCIException] if the engine is not initialized.
    /// 
    /// Example:
    /// ```dart
    /// await engine.newGame();
    /// await engine.setPosition(fen: startingPosition);
    /// ```
  Future<void> newGame() async {
    _ensureInitialized();
    await sendCommand('ucinewgame');
  }

  /// Sets the current board position for analysis or move generation.
  /// 
  /// This method configures the engine with a specific chess position using either:
  /// - A FEN (Forsyth-Edwards Notation) string for any position
  /// - A sequence of moves from the starting position
  /// - Both FEN and additional moves from that position
  /// 
  /// [fen] A FEN string representing the board position. If null, uses the
  /// standard starting position.
  /// 
  /// [moves] A list of moves to apply after setting the FEN position.
  /// Moves should be in UCI format (e.g., 'e2e4', 'e7e8q' for promotion).
  /// 
  /// Throws [UCIException] if the engine is not initialized.
  /// 
  /// Examples:
  /// ```dart
  /// // Set starting position
  /// await engine.setPosition();
  /// 
  /// // Set specific position via FEN
  /// await engine.setPosition(fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1');
  /// 
  /// // Set position via move sequence
  /// await engine.setPosition(moves: [
  ///   UCIMove.fromString('e2e4'),
  ///   UCIMove.fromString('e7e5'),
  /// ]);
  /// 
  /// // Combine FEN with additional moves
  /// await engine.setPosition(
  ///   fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
  ///   moves: [UCIMove.fromString('e2e4')]
  /// );
  /// ```
  Future<void> setPosition({String? fen, List<UCIMove>? moves}) async {
    _ensureInitialized();
    
    String command = 'position ';
    if (fen != null) {
      command += 'fen $fen';
    } else {
      command += 'startpos';
    }
    
    if (moves != null && moves.isNotEmpty) {
      command += ' moves ${moves.join(' ')}';
    }

    print(command);
    
    await sendCommand(command);
  }

  /// Sets an engine-specific option.
  /// 
  /// UCI engines support various configuration options that can modify their
  /// behavior. Common options include:
  /// - Hash: Hash table size in MB
  /// - Threads: Number of search threads
  /// - Ponder: Whether to think during opponent's time
  /// - MultiPV: Number of principal variations to show
  /// 
  /// [name] The name of the option to set
  /// [value] The value to set for the option
  /// 
  /// Throws [UCIException] if the engine is not initialized.
  /// 
  /// Example:
  /// ```dart
  /// await engine.setOption('Hash', 256);        // 256MB hash table
  /// await engine.setOption('Threads', 4);       // Use 4 threads
  /// await engine.setOption('Ponder', true);     // Enable pondering
  /// await engine.setOption('MultiPV', 3);       // Show 3 best lines
  /// ```
  Future<void> setOption(String name, dynamic value) async {
    _ensureInitialized();
    await sendCommand('setoption name $name value $value');
  }

  /// Checks if the engine is ready to receive commands.
  /// 
  /// This method sends an 'isready' command to the engine and waits for
  /// the 'readyok' response. This is useful to ensure the engine has
  /// finished processing previous commands before sending new ones.
  /// 
  /// Returns `true` if the engine responds with 'readyok', `false` if
  /// the engine is not running or not initialized.
  /// 
  /// Example:
  /// ```dart
  /// if (await engine.isReady()) {
  ///   print('Engine is ready for commands');
  ///   final move = await engine.getBestMove(depth: 15);
  /// }
  /// ```
  Future<bool> isReady() async {
    if (_process == null || !_isInitialized) return false;
    
    await sendCommand('isready');
    
    final completer = Completer<bool>();
    late StreamSubscription subscription;
    
    subscription = _outputController!.stream.listen((line) {
      if (line == 'readyok') {
        subscription.cancel();
        completer.complete(true);
      }
    });
    
    return completer.future;
  }

  /// Parses a UCI 'info' line into structured analysis data.
  /// 
  /// This internal method extracts analysis information from UCI info lines,
  /// including depth, score, principal variation, nodes searched, and time spent.
  /// 
  /// [line] A UCI info line starting with 'info'
  /// 
  /// Returns an [EngineAnalysis] object if the line contains sufficient data
  /// (at minimum depth and score), or `null` if the line cannot be parsed.
  /// 
  /// Handles various UCI info formats:
  /// - `score cp X` for centipawn scores
  /// - `depth X` for search depth
  /// - `pv move1 move2 ...` for principal variation
  /// - `nodes X` for nodes searched
  /// - `time X` for time spent in milliseconds
  EngineAnalysis? _parseInfoLine(String line) {
    final parts = line.split(' ');
    
    int? depth;
    int? score;
    List<UCIMove> pv = [];
    int? nodes;
    int? timeMs;
    
    for (int i = 0; i < parts.length; i++) {
      switch (parts[i]) {
        case 'depth':
          if (i + 1 < parts.length) depth = int.tryParse(parts[i + 1]);
          break;
        case 'score':
          if (i + 2 < parts.length && parts[i + 1] == 'cp') {
            score = int.tryParse(parts[i + 2]);
          }
          break;
        case 'pv':
          for (int j = i + 1; j < parts.length; j++) {
            try {
              pv.add(UCIMove.fromString(parts[j]));
            } catch (e) {
              break;
            }
          }
          break;
        case 'nodes':
          if (i + 1 < parts.length) nodes = int.tryParse(parts[i + 1]);
          break;
        case 'time':
          if (i + 1 < parts.length) timeMs = int.tryParse(parts[i + 1]);
          break;
      }
    }
    
    if (depth != null && score != null) {
      return EngineAnalysis(
        depth: depth,
        score: score,
        principalVariation: pv,
        nodes: nodes ?? 0,
        timeMs: timeMs ?? 0,
      );
    }
    
    return null;
  }

  /// Analyzes the current position and returns a stream of analysis data.
  /// 
  /// This method starts engine analysis of the current position and provides
  /// real-time analysis results as they become available. The analysis continues
  /// until the specified time limit or depth is reached, or until the engine
  /// finds a forced mate.
  /// 
  /// [depth] Maximum search depth (number of half-moves to search ahead).
  /// If null, uses time-based search.
  /// 
  /// [timeMs] Maximum time to spend analyzing in milliseconds.
  /// If null, uses depth-based search.
  /// 
  /// If both [depth] and [timeMs] are null, the engine will search indefinitely
  /// until [stopAnalysis] is called.
  /// 
  /// Returns a [Stream<EngineAnalysis>] that emits analysis results as they
  /// become available. Each result contains:
  /// - Search depth reached
  /// - Position evaluation score (in centipawns)
  /// - Principal variation (best line of play)
  /// - Number of positions searched
  /// - Time spent searching
  /// 
  /// The stream automatically closes when the engine completes its analysis.
  /// 
  /// Throws [UCIException] if the engine is not initialized.
  /// 
  /// Examples:
  /// ```dart
  /// // Analyze for 5 seconds
  /// final stream = await engine.analyze(timeMs: 5000);
  /// await for (final analysis in stream) {
  ///   print('Depth ${analysis.depth}: ${analysis.score} cp');
  ///   print('Best line: ${analysis.principalVariation.join(' ')}');
  /// }
  /// 
  /// // Analyze to depth 20
  /// final stream = await engine.analyze(depth: 20);
  /// await for (final analysis in stream) {
  ///   print('${analysis.nodes} nodes, ${analysis.timeMs}ms');
  /// }
  /// 
  /// // Infinite analysis (stop manually)
  /// final stream = await engine.analyze();
  /// final subscription = stream.listen((analysis) {
  ///   print('Analysis: ${analysis}');
  /// });
  /// // Later: await engine.stopAnalysis();
  /// ```
  Future<Stream<EngineAnalysis>> analyze({
    int? depth,
    int? timeMs,
  }) async {
    _ensureInitialized();
    
    final controller = StreamController<EngineAnalysis>();
    
    String command = 'go';
    if (depth != null) command += ' depth $depth';
    if (timeMs != null) command += ' movetime $timeMs';
    if (depth == null && timeMs == null) command += ' infinite';

    print(command);
    
    // Set up the listener before sending the command
    late StreamSubscription subscription;
    subscription = _outputController!.stream.listen((line) {
      if (line.startsWith('info ')) {
        final analysis = _parseInfoLine(line);
        if (analysis != null) {
          controller.add(analysis);
        }
      } else if (line.startsWith('bestmove ')) {
        subscription.cancel();
        controller.close();
      }
    });
    
    // Send the command after setting up the listener
    await sendCommand(command);
    
    return controller.stream;
  }

  /// Stops the current analysis or search operation.
  /// 
  /// This method sends a 'stop' command to the engine, instructing it to
  /// halt any ongoing analysis and return the best move found so far.
  /// 
  /// Useful when running infinite analysis or when you want to interrupt
  /// a long-running search operation.
  /// 
  /// Throws [UCIException] if the engine is not initialized.
  /// 
  /// Example:
  /// ```dart
  /// // Start infinite analysis
  /// final stream = await engine.analyze();
  /// final subscription = stream.listen((analysis) {
  ///   print('Analysis: ${analysis}');
  /// });
  /// 
  /// // Stop after 10 seconds
  /// await Future.delayed(Duration(seconds: 10));
  /// await engine.stopAnalysis();
  /// ```
  Future<void> stopAnalysis() async {
    _ensureInitialized();
    await sendCommand('stop');
  }

  /// Gets the best move for the current position.
  /// 
  /// This method instructs the engine to search for the best move in the
  /// current position and returns it when the search completes. The search
  /// can be limited by depth, time, or number of nodes.
  /// 
  /// [depth] Maximum search depth (number of half-moves to search ahead)
  /// [timeMs] Maximum time to spend searching in milliseconds
  /// [nodes] Maximum number of positions to search
  /// 
  /// If no search parameters are specified, uses a default 1-second time limit
  /// to prevent infinite searching.
  /// 
  /// Returns the best [UCIMove] found by the engine.
  /// 
  /// Throws [UCIException] if:
  /// - The engine is not initialized
  /// - The search times out (after 30 seconds)
  /// - The engine doesn't provide a valid move
  /// 
  /// Examples:
  /// ```dart
  /// // Search to depth 15
  /// final move = await engine.getBestMove(depth: 15);
  /// print('Best move: $move');
  /// 
  /// // Search for 2 seconds
  /// final move = await engine.getBestMove(timeMs: 2000);
  /// 
  /// // Search 1 million nodes
  /// final move = await engine.getBestMove(nodes: 1000000);
  /// 
  /// // Quick search with default 1-second limit
  /// final move = await engine.getBestMove();
  /// ```
  Future<UCIMove> getBestMove({
    int? depth,
    int? timeMs,
    int? nodes,
  }) async {
    _ensureInitialized();
    
    String command = 'go';
    if (depth != null) command += ' depth $depth';
    if (timeMs != null) command += ' movetime $timeMs';
    if (nodes != null) command += ' nodes $nodes';
    
    // If no parameters specified, use a default time limit to prevent hanging
    if (depth == null && timeMs == null && nodes == null) {
      command += ' movetime 1000';
    }

    await sendCommand(command);

    final completer = Completer<UCIMove>();
    late StreamSubscription subscription;
    
    subscription = _outputController!.stream.listen((line) {
      if (line.startsWith('bestmove ')) {
        final parts = line.split(' ');
        if (parts.length >= 2) {
          subscription.cancel();
          completer.complete(UCIMove.fromString(parts[1]));
        }
      }
    });

    // Add a timeout to prevent hanging indefinitely
    return completer.future.timeout(
      Duration(seconds: 30),
      onTimeout: () {
        subscription.cancel();
        throw UCIException('getBestMove timed out after 30 seconds');
      },
    );
  }

}

/// Contains information about a UCI chess engine.
/// 
/// This class holds metadata about the engine including its name, author,
/// and available configuration options. It's returned by the [UCIChessEngine.initialize]
/// method after successful UCI protocol initialization.
class EngineInfo {
  /// The name of the chess engine
  final String name;
  
  /// The author(s) of the chess engine
  final String author;
  
  /// Available engine options with their UCI option strings
  /// 
  /// Keys are option names, values are the full UCI option declaration strings.
  /// Common options include 'Hash', 'Threads', 'Ponder', 'MultiPV', etc.
  final Map<String, dynamic> options;
  
  /// Creates a new engine information object.
  /// 
  /// [name] The engine's name
  /// [author] The engine's author(s) 
  /// [options] Map of available options, defaults to empty map
  EngineInfo({
    required this.name,
    required this.author,
    this.options = const {},
  });
  
  /// Returns a human-readable string representation of the engine information.
  @override
  String toString() => 'Engine: $name by $author \nOptions: ${options.isEmpty ? 'None' : options}';
}

/// Exception thrown by UCI chess engine operations.
/// 
/// This exception is thrown when UCI operations fail, such as:
/// - Engine process fails to start
/// - Engine doesn't respond to UCI commands
/// - Invalid engine responses
/// - Timeout errors
/// - Engine not properly initialized
class UCIException implements Exception {
  /// The error message describing what went wrong
  final String message;
  
  /// Creates a new UCI exception with the given error message.
  /// 
  /// [message] A description of the error that occurred
  UCIException(this.message);
  
  /// Returns the error message as a string.
  @override
  String toString() => 'UCIException: $message';
}

/// Represents the result of engine analysis for a chess position.
/// 
/// This class contains comprehensive analysis information returned by a chess
/// engine, including the search depth, position evaluation, best line of play,
/// and search statistics.
/// 
/// Scores are typically in centipawns (1/100th of a pawn), where:
/// - Positive scores favor the side to move
/// - Negative scores favor the opponent
/// - Score of 100 = approximately 1 pawn advantage
class EngineAnalysis {
  /// The search depth reached (number of half-moves searched ahead)
  final int depth;
  
  /// The position evaluation score in centipawns
  /// 
  /// Positive values favor the side to move, negative values favor the opponent.
  /// A score of 100 centipawns is approximately equal to a 1-pawn advantage.
  final int score;
  
  /// The principal variation (best line of play found)
  /// 
  /// This is the sequence of moves the engine considers best for both sides,
  /// starting from the current position.
  final List<UCIMove> principalVariation;
  
  /// The number of positions (nodes) searched to reach this analysis
  final int nodes;
  
  /// The time spent searching in milliseconds
  final int timeMs;
  
  /// Creates a new engine analysis result.
  /// 
  /// [depth] Search depth in half-moves
  /// [score] Position evaluation in centipawns
  /// [principalVariation] Best line of play
  /// [nodes] Number of positions searched
  /// [timeMs] Time spent searching in milliseconds
  EngineAnalysis({
    required this.depth,
    required this.score,
    required this.principalVariation,
    required this.nodes,
    required this.timeMs,
  });
  
  /// Returns a human-readable string representation of the analysis.
  @override
  String toString() => 'Depth: $depth, Score: $score, PV: ${principalVariation.join(' ')}';
}

/// Represents a chess move in UCI (Universal Chess Interface) format.
/// 
/// UCI moves are represented as strings in the format "from-square to-square [promotion]":
/// - Normal moves: "e2e4", "g1f3"
/// - Castling: "e1g1" (kingside), "e1c1" (queenside)
/// - En passant: "e5d6" (capturing pawn moves to empty square)
/// - Promotion: "e7e8q" (pawn promotes to queen)
/// 
/// Square names use algebraic notation (a1-h8).
class UCIMove {
  /// The starting square in algebraic notation (e.g., "e2")
  final String from;
  
  /// The destination square in algebraic notation (e.g., "e4")
  final String to;
  
  /// The promotion piece for pawn promotion moves
  /// 
  /// One of: 'q' (queen), 'r' (rook), 'b' (bishop), 'n' (knight).
  /// Null for non-promotion moves.
  final String? promotion;
  
  /// Creates a new UCI move.
  /// 
  /// [from] Starting square (e.g., "e2")
  /// [to] Destination square (e.g., "e4") 
  /// [promotion] Promotion piece ('q', 'r', 'b', 'n') or null
  UCIMove({
    required this.from,
    required this.to,
    this.promotion,
  });
  
  /// Returns the UCI string representation of this move.
  /// 
  /// Examples: "e2e4", "g1f3", "e7e8q"
  @override
  String toString() => '$from$to${promotion ?? ''}';
  
  /// Creates a UCI move from a string representation.
  /// 
  /// Parses UCI move strings like "e2e4", "g1f3", "e7e8q" into UCIMove objects.
  /// 
  /// [moveString] A UCI move string (minimum 4 characters: from + to squares)
  /// 
  /// Returns a new [UCIMove] object.
  /// 
  /// Throws [ArgumentError] if the move string is invalid (less than 4 characters).
  /// 
  /// Examples:
  /// ```dart
  /// final move1 = UCIMove.fromString('e2e4');     // Normal move
  /// final move2 = UCIMove.fromString('e7e8q');    // Promotion to queen
  /// final move3 = UCIMove.fromString('e1g1');     // Kingside castling
  /// ```
  factory UCIMove.fromString(String moveString) {
    if (moveString.length < 4) {
      throw ArgumentError('Invalid move string: $moveString');
    }
    
    return UCIMove(
      from: moveString.substring(0, 2),
      to: moveString.substring(2, 4),
      promotion: moveString.length > 4 ? moveString.substring(4) : null,
    );
  }
}
