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
      _outputController = StreamController<String>();
      _errorController = StreamController<String>();
      
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
    await _sendCommand('uci');
    
    String? engineName;
    String? engineAuthor;
    Map<String, dynamic> options = {};
    
    // gather engine information
    await for (String line in _outputController!.stream) {
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
        break;
      }
    }
    
    if (engineName == null) {
      throw UCIException('Engine did not provide a name');
    }
    
    // Create EngineInfo object with gathered data
    _engineInfo = EngineInfo(
      name: engineName,
      author: engineAuthor ?? 'Unknown',
      options: options,
    );
    
    _isInitialized = true;
    return _engineInfo!;
  }

  Future<void> stop() async {
    if (_process == null) {
      return;
    }

    //tell the engine to quit
    await _sendCommand('quit');
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

  Future<void> _sendCommand(String command) async {
      if (_process == null) {
        throw UCIException('Engine process not running');
      }
      
      // Send the command to the engine
      _process!.stdin.writeln(command);
      await _process!.stdin.flush();
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
  String toString() => 'Engine: $name by $author';
}

class UCIException implements Exception {
  final String message;
  UCIException(this.message);
  
  @override
  String toString() => 'UCIException: $message';
}
