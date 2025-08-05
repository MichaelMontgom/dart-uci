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

    // print('Setting position...');
    // await engine.setPosition(fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');

    // final bestMove = await engine.getBestMove(depth: 10);
    // print('Best move: $bestMove');


    // Example: Set a specific position (Scandinavian Defense, my favorite opening against e4)
    print('\nAnalyzing specific position...');
    await engine.setPosition(moves: [
      UCIMove.fromString('e2e4'),
      UCIMove.fromString('d7d5'),
    ]);
    
    final bestMoveScandinavian = await engine.getBestMove(depth: 12);
    print('Best move in Scandinavian: $bestMoveScandinavian');

  print('=== Example 2: Complex Middlegame Position ===');
    const complexFen = 'r2qkb1r/ppp2ppp/2n1bn2/2bpp3/3PP3/2N2N2/PPP2PPP/R1BQKB1R w KQkq - 0 6';
    await engine.setPosition(fen: complexFen);
    
    print('Analyzing complex position for 5 seconds...');
    final analysisStream = await engine.analyze(timeMs: 5000);
    
    
    
   



  }catch (e) {
    print('Error: $e');
    
  } finally {
    print('Shutting down engine...');
    await engine.stop();
  }

  
}
