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

  print('=== Example 2: Analysis Stream ===');
    // Use a working position for analysis
    const analysisFen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';
    await engine.setPosition(fen: analysisFen);

    print('Starting analysis stream...');
    final analysisStream = await engine.analyze(timeMs: 5000, depth: 30);
    
    print('Listening to analysis...');
    var count = 0;
    await for (final analysis in analysisStream) {
      count++;
      print('Analysis $count: Depth: ${analysis.depth}, Score: ${analysis.score}, PV: ${analysis.principalVariation.join(' ')}, Nodes: ${analysis.nodes}, Time: ${analysis.timeMs}ms');
       // Stop after 10 results for testing
    }
    
    print('Analysis completed with $count results');
    

    
    
    
   



  }catch (e) {
    print('Error: $e');
    
  } finally {
    print('Shutting down engine...');
    await engine.stop();
  }

  
}
