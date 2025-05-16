import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import 'classement_screen.dart';

class ScoresScreen extends StatefulWidget {
  const ScoresScreen({super.key});

  @override
  State<ScoresScreen> createState() => _ScoresScreenState();
}

class _ScoresScreenState extends State<ScoresScreen> with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _overlayController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  bool isGameStarted = false; // Variable pour savoir si la partie est lancée
  bool showFinGameOverlay = false; // Variable pour afficher l'overlay "FIN GAME"
  bool hasNavigatedToClassement = false; // Empêche plusieurs navigations
  StreamSubscription<String>? _messageSubscription;

  @override
  void initState() {
    super.initState();

    // Animation d'entrée de l'écran
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(_controller);
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1).animate(_controller);

    _controller.forward();

    // Animation d'overlay
    _overlayController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    // Charger l'état du bouton à partir des préférences partagées
    _loadGameState();

    // Écoute des messages WebSocket
    final webSocketService = Provider.of<WebSocketService>(context, listen: false);
    _messageSubscription = webSocketService.messages.listen((message) {
      _handleWebSocketMessage(message); // Corrigé pour passer le message attendu
    });
  }

  Future<void> _loadGameState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isGameStarted = prefs.getBool('isGameStarted') ?? false;
    });
  }

  Future<void> _saveGameState(bool started) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isGameStarted', started);
  }

  void _handleWebSocketMessage(String message) {
    try {
      final data = json.decode(message);
      if (data is Map<String, dynamic>) {
        if (data['type'] == 'fin') {
          _resetGameState(); // Réinitialisation de l'état du bouton
          _showFinGameOverlay(); // Afficher l'overlay et rediriger
        }
      }
    } catch (e) {
      debugPrint('Erreur WebSocket : $e');
    }
  }

  void _resetGameState() {
    // Supprimer la réinitialisation des scores ici
    setState(() {
      isGameStarted = false; // Réinitialise le bouton à "Démarrer"
    });

    // Sauvegarder l'état réinitialisé
    _saveGameState(false);
  }

  void _showFinGameOverlay() async {
    if (!mounted) return;

    setState(() => showFinGameOverlay = true);
    _overlayController.forward();

    // Affiche l'overlay pendant 3 secondes
    await Future.delayed(const Duration(seconds: 5));
    if (!mounted) return;
    _overlayController.reverse();

    // Attendre la fin de l'overlay et naviguer
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted && !hasNavigatedToClassement) {
      hasNavigatedToClassement = true;

      // Obtenir les scores finaux
      final scoresMap = Provider.of<WebSocketService>(context, listen: false).scoresNotifier.value;
      final finalScores = List.generate(4, (i) => scoresMap[i] ?? 0);

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ClassementScreen(finalScores: finalScores),
        ),
      );
    }
  }

  void _startGame() {
    final webSocketService = Provider.of<WebSocketService>(context, listen: false);
    webSocketService.sendMessage(json.encode({
      'type': 'start',
      'message': 'START_GAME',
    }));

    setState(() {
      isGameStarted = true;
    });
    _saveGameState(true);
  }

  @override
  void dispose() {
    _controller.dispose();
    _overlayController.dispose();
    _messageSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ws = Provider.of<WebSocketService>(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Row(
          children: [
            Icon(Icons.bar_chart, color: Colors.white),
            SizedBox(width: 8),
            Text('Scores', style: TextStyle(color: Colors.white)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: ElevatedButton(
              onPressed: null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7DBFF8),
                disabledBackgroundColor: const Color(0xFF7DBFF8),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: Text(
                'Groupe ${ws.group}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: ElevatedButton(
              onPressed: isGameStarted ? null : _startGame,
              style: ElevatedButton.styleFrom(
                backgroundColor: isGameStarted ? Colors.green : const Color(0xFF7DBFF8),
                disabledBackgroundColor: Colors.green,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: Text(
                isGameStarted ? 'Partie lancée' : 'Démarrer',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: ValueListenableBuilder<Map<int, String>>(
                  valueListenable: ws.pseudonymsNotifier,
                  builder: (context, pseudos, _) {
                    return ValueListenableBuilder<Map<int, int>>(
                      valueListenable: ws.scoresNotifier,
                      builder: (context, scores, _) {
                        return _buildScoresGrid(pseudos, scores);
                      },
                    );
                  },
                ),
              ),
            ),
          ),

          // Overlay "FIN GAME"
          if (showFinGameOverlay)
            FadeTransition(
              opacity: _overlayController,
              child: Center(
                child: Container(
                  width: 2000,
                  height: 2000,
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: Text(
                      'FIN GAME',
                      style: TextStyle(fontSize: 240, color: Colors.black),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScoresGrid(Map<int, String> pseudos, Map<int, int> scores) {
    final spacing = MediaQuery.of(context).size.width * 0.02;
    final usableHeight = MediaQuery.of(context).size.height - spacing * 3;
    final cardHeight = (usableHeight / 2) - spacing;
    final cardWidth = (MediaQuery.of(context).size.width - spacing * 3) / 2;
    final fontSize = cardHeight * 0.4;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildScoreCard('${pseudos[0] ?? "J1"} : ${scores[0] ?? 0}', cardWidth, cardHeight, fontSize, const LinearGradient(colors: [Color(0xFFAEDCFA), Color(0xFF91C9F9)])),
            SizedBox(width: spacing),
            _buildScoreCard('${pseudos[1] ?? "J2"} : ${scores[1] ?? 0}', cardWidth, cardHeight, fontSize, const LinearGradient(colors: [Color(0xFF91C9F9), Color(0xFF6AB8F7)])),
          ],
        ),
        SizedBox(height: spacing),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildScoreCard('${pseudos[2] ?? "J3"} : ${scores[2] ?? 0}', cardWidth, cardHeight, fontSize, const LinearGradient(colors: [Color(0xFF6AB8F7), Color(0xFF429CF2)])),
            SizedBox(width: spacing),
            _buildScoreCard('${pseudos[3] ?? "J4"} : ${scores[3] ?? 0}', cardWidth, cardHeight, fontSize, const LinearGradient(colors: [Color(0xFF429CF2), Color(0xFF1E88E5)])),
          ],
        ),
      ],
    );
  }

  Widget _buildScoreCard(String text, double width, double height, double fontSize, LinearGradient gradient) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
