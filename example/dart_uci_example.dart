import 'package:dart_uci/dart_uci.dart';

void main() async{
  // Replace with your preferred UCI chess engine (e.g., Stockfish)
    const enginePath = 'path/to/your/chess/engine.exe'; 

  var engine = UCIChessEngine(enginePath);
  try{
    print('Starting chess engine...');
    await engine.start();
    
    print('Initializing UCI protocol...');
    final info = await engine.initialize();
    print('Engine: ${info.name} by ${info.author}');

  }catch (e) {
    print('Error: $e');
    
  } finally {
    print('Shutting down engine...');
    await engine.stop();
  }

  
}
