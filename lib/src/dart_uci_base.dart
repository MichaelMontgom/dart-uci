import 'dart:async';
import 'dart:convert';
import 'dart:io';

class UCIChessEngine {
  final String _enginePath;
  Process? _process;
  StreamController<String>? _outputController;
  StreamController<String>? _errorController;
  bool _isInitialized = false;
  EngineInfo? _engineInfo;
  
  UCIChessEngine(this._enginePath);

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

  void _ensureInitialized() {
    if (_isInitialized == false || _process == null) {
      throw UCIException('Engine not initialized. Call initialize() first.');
    }
  }

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

  Future<void> sendCommand(String command) async {
      if (_process == null) {
        throw UCIException('Engine process not running');
      }
      
      // Send the command to the engine
      _process!.stdin.writeln(command);
      await _process!.stdin.flush();
    }

    // Sets up a new game
  Future<void> newGame() async {
    _ensureInitialized();
    await sendCommand('ucinewgame');
  }

  // Sets the current position using FEN notation
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

  // Sets an engine option
  Future<void> setOption(String name, dynamic value) async {
    _ensureInitialized();
    await sendCommand('setoption name $name value $value');
  }

  // Checks if the engine is ready
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

  // Analyzes the current position and returns analysis data
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

  // Stops the current analysis or search
  Future<void> stopAnalysis() async {
    _ensureInitialized();
    await sendCommand('stop');
  }

  // Gets the best move from the current position
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

class EngineInfo {
  final String name;
  final String author;
  final Map<String, dynamic> options;
  
  EngineInfo({
    required this.name,
    required this.author,
    this.options = const {},
  });
  
  @override
  String toString() => 'Engine: $name by $author \nOptions: ${options.isEmpty ? 'None' : options}';
}

class UCIException implements Exception {
  final String message;
  UCIException(this.message);
  
  @override
  String toString() => 'UCIException: $message';
}

// Represents engine analysis result
class EngineAnalysis {
  final int depth;
  final int score;
  final List<UCIMove> principalVariation;
  final int nodes;
  final int timeMs;
  
  EngineAnalysis({
    required this.depth,
    required this.score,
    required this.principalVariation,
    required this.nodes,
    required this.timeMs,
  });
  
  @override
  String toString() => 'Depth: $depth, Score: $score, PV: ${principalVariation.join(' ')}';
}

// Represents a chess move in UCI format
class UCIMove {
  final String from;
  final String to;
  final String? promotion;
  
  UCIMove({
    required this.from,
    required this.to,
    this.promotion,
  });
  
  @override
  String toString() => '$from$to${promotion ?? ''}';
  
  // Creates a UCIMove from a string like "e2e4" or "e7e8q"
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
