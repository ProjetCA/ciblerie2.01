import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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

  bool showFinGameOverlay = false;
  bool hasNavigatedToClassement = false;
  bool showNextPlayerOverlay = false; // Overlay for the new button
  bool isNextPlayerClicked = false; // State for the new button
  StreamSubscription<String>? _messageSubscription;

  bool isGameStarted = false; // Variable pour savoir si la partie est lancée

  String nextPlayerPseudo = "Joueur"; // Placeholder for the next player's pseudo

  @override
  void initState() {
    super.initState();

    // Animation initiale
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(_controller);
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1).animate(_controller);

    // Lancer l'animation au rendu de l'écran
    SchedulerBinding.instance.addPostFrameCallback((_) => _controller.forward());

    // Contrôleur de l'overlay
    _overlayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    // Abonnement aux messages WebSocket
    final webSocketService = Provider.of<WebSocketService>(context, listen: false);
    _messageSubscription = webSocketService.messages.listen(_handleWebSocketMessage);
  }

  void _handleWebSocketMessage(String message) {
    try {
      final data = json.decode(message);
      if (data is Map<String, dynamic>) {
        if (data['type'] == 'fin') {
          _showFinGameOverlay();
        } else if (data['type'] == 'start') {
          Provider.of<WebSocketService>(context, listen: false).resetAllScores();
        } else if (data['type'] == 'next_player') {
          setState(() {
            nextPlayerPseudo = data['pseudo'] ?? "Joueur";
          });
        }
      }
    } catch (e) {
      debugPrint('Erreur WebSocket : $e');
    }
  }

  void _showFinGameOverlay() async {
    if (!mounted) return;

    setState(() => showFinGameOverlay = true);
    _overlayController.forward();

    await Future.delayed(const Duration(seconds: 5));
    if (!mounted) return;
    _overlayController.reverse();

    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted && !hasNavigatedToClassement) {
      hasNavigatedToClassement = true;

      final scoresMap = Provider.of<WebSocketService>(context, listen: false).scoresNotifier.value;
      final finalScores = List.generate(4, (i) => scoresMap[i] ?? 0);

      setState(() => showFinGameOverlay = false);

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ClassementScreen(finalScores: finalScores),
        ),
      );
    }
  }

  void _sendStartGame() {
    final webSocketService = Provider.of<WebSocketService>(context, listen: false);
    webSocketService.sendMessage(json.encode({
      'type': 'start',
      'message': 'START_GAME',
    }));

    setState(() {
      isGameStarted = true;
    });
  }

  // Function to handle the new overlay and button logic
  void _handleNextPlayer() {
    final webSocketService = Provider.of<WebSocketService>(context, listen: false);
    webSocketService.sendMessage(json.encode({
      'type': 'next',
      'message': 'JOUEUR SUIVANT',
    }));

    setState(() {
      isNextPlayerClicked = true; // Mark the button as clicked
      showNextPlayerOverlay = false; // Hide the overlay
    });
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
          // Nouveau bouton : Joueur Suivant
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: ElevatedButton(
              onPressed: isNextPlayerClicked ? null : () => setState(() => showNextPlayerOverlay = true),
              style: ElevatedButton.styleFrom(
                backgroundColor: isNextPlayerClicked ? Colors.green : const Color(0xFF7DBFF8),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: Text(
                isNextPlayerClicked ? 'Activé' : 'Joueur Suivant',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ),
          ),
          // Bouton existant : Groupe
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
          // Bouton existant : Démarrer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: ElevatedButton(
              onPressed: isGameStarted ? null : _sendStartGame,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7DBFF8),
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
      body: SafeArea(
        child: Stack(
          alignment: Alignment.center,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final spacing = constraints.maxWidth * 0.02;
                final usableHeight = constraints.maxHeight - spacing * 3;
                final cardHeight = (usableHeight / 2) - spacing;
                final cardWidth = (constraints.maxWidth - spacing * 3) / 2;
                final fontSize = cardHeight * 0.4;

                return FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildScoreCard('${ws.pseudonymsNotifier.value[0] ?? "J1"} : ${ws.scoresNotifier.value[0] ?? 0}', cardWidth, cardHeight, fontSize, const LinearGradient(colors: [Color(0xFFAEDCFA), Color(0xFF91C9F9)])),
                            SizedBox(width: spacing),
                            _buildScoreCard('${ws.pseudonymsNotifier.value[1] ?? "J2"} : ${ws.scoresNotifier.value[1] ?? 0}', cardWidth, cardHeight, fontSize, const LinearGradient(colors: [Color(0xFF91C9F9), Color(0xFF6AB8F7)])),
                          ],
                        ),
                        SizedBox(height: spacing),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildScoreCard('${ws.pseudonymsNotifier.value[2] ?? "J3"} : ${ws.scoresNotifier.value[2] ?? 0}', cardWidth, cardHeight, fontSize, const LinearGradient(colors: [Color(0xFF6AB8F7), Color(0xFF429CF2)])),
                            SizedBox(width: spacing),
                            _buildScoreCard('${ws.pseudonymsNotifier.value[3] ?? "J4"} : ${ws.scoresNotifier.value[3] ?? 0}', cardWidth, cardHeight, fontSize, const LinearGradient(colors: [Color(0xFF429CF2), Color(0xFF1E88E5)])),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (showFinGameOverlay)
              FadeTransition(
                opacity: _overlayController,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.9, end: 1.0).animate(
                    CurvedAnimation(parent: _overlayController, curve: Curves.easeOut),
                  ),
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.75,
                    height: MediaQuery.of(context).size.height * 0.4,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFFFE0B2), Color(0xFFFFB74D)]),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'FIN GAME',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ),
            if (showNextPlayerOverlay)
              Container(
                width: MediaQuery.of(context).size.width * 0.90, //0.85,
                height: MediaQuery.of(context).size.height * 0.6, //0.5,
                decoration: BoxDecoration(
                  gradient:
                  const LinearGradient(
                    colors: //[Colors.grey, Colors.blueGrey],
                    [Color(0xFF1E88E5), Color(0xFFAEDCFA)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Joueur suivant\n$nextPlayerPseudo',
                  style: TextStyle(
                    fontSize: MediaQuery.of(context).size.height * 0.15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
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
