import 'package:dart_uci/dart_uci.dart';

void main() async{
  // Replace with your preferred UCI chess engine (e.g., Stockfish)
    // const enginePath = 'path/to/your/chess/engine.exe'; 
    const enginePath = '"C:\\Users\\mem22\\Downloads\\stockfish-windows-x86-64-avx2\\stockfish\\stockfish-windows-x86-64-avx2.exe"';

  var engine = UCIChessEngine(enginePath);
  try{
    print('Starting chess engine...');
    await engine.start();
    
    print('Initializing UCI protocol...');
    final info = await engine.initialize();
    print('Engine: ${info.name} by ${info.author}');

    print('Setting up new game...');
    await engine.newGame();

    print('Setting position...');
    await engine.setPosition(fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');

    final bestMove = await engine.getBestMove(depth: 10);
    print('Best move: $bestMove');






  }catch (e) {
    print('Error: $e');
    
  } finally {
    print('Shutting down engine...');
    await engine.stop();
  }

  
}
