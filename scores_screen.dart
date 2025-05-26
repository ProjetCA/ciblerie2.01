import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import '../models/group_model.dart';
import 'classement_screen.dart';
import '../enums/game_phase.dart';

class ScoresScreen extends StatefulWidget {
  const ScoresScreen({super.key});

  @override
  State<ScoresScreen> createState() => _ScoresScreenState();
}

class _ScoresScreenState extends State<ScoresScreen> with TickerProviderStateMixin {
  // === ANIMATIONS ===
  late AnimationController _controller;
  late AnimationController _overlayController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;

  // === ÉTAT DU JEU ===
  GamePhase _gamePhase = GamePhase.waitingGroup;
  bool _showFinGameOverlay = false;
  bool _hasNavigatedToClassement = false;
  int _currentPlayerIndex = 0;
  int? _currentRound;
  StreamSubscription<String>? _messageSubscription;

  @override
  void initState() {
    super.initState();

    // Initialisation des contrôleurs d'animation
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _overlayController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _blinkController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    // Initialisation des animations
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(_controller);
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1).animate(_controller);
    _blinkAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _blinkController,
        curve: Curves.easeInOut,
      ),
    );

    // Démarrage des animations
    _controller.forward();

    // Configuration de l'écouteur WebSocket
    _setupWebSocketListener();
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    debugPrint('🔍 Vérification de l\'état initial');
    final prefs = await SharedPreferences.getInstance();
    final ws = Provider.of<WebSocketService>(context, listen: false);

    if (ws.isConnected && prefs.getString('selectedGroup') != null) {
      debugPrint('✅ Groupe déjà sélectionné, passage en mode readyToStart');
      if (mounted) {
        setState(() {
          _gamePhase = GamePhase.readyToStart;
        });
      }
    }
  }
  void _setupWebSocketListener() {
    final ws = Provider.of<WebSocketService>(context, listen: false);
    _messageSubscription = ws.messages.listen((message) {
      final data = json.decode(message) as Map<String, dynamic>;
      final type = data['type'] as String?;
      _handleWebSocketMessage(message);

      setState(() {
        if (type == 'start_game') {
          _gamePhase = GamePhase.starting;
          _blinkController.repeat(reverse: true);
        } else if (type == 'confirmed_game') {
          _gamePhase = GamePhase.inProgress;
          _blinkController.stop();
        } else if (type == 'fin_game') {
          _gamePhase = GamePhase.waitingGroup;
        }
      });
    });
  }

  void _handleWebSocketMessage(String message) {
    final data = json.decode(message) as Map<String, dynamic>;
    final type = data['type'] as String?;
    final status = data['status'] as String?; // Assurez-vous que le statut est extrait

    setState(() {
      switch (type) {
        case 'waiting_group':
          _gamePhase = GamePhase.waitingGroup;
          _blinkController.stop();
          break;
        case 'start_game': // Reçu quand l'Arduino envoie "START_GAME"
          _gamePhase = GamePhase.starting;
          _blinkController.repeat(reverse: true); // Clignotement orange
          break;
        case 'confirmed_game': // Reçu quand l'Arduino envoie "CONFIRMED_GAME"
          _gamePhase = GamePhase.inProgress;
          _blinkController.stop(); // Vert fixe
          break;
        case 'fin_game':
          _gamePhase = GamePhase.waitingGroup; // Retour au bleu
          break;
        case 'game_status': // Ajoutez ce cas pour gérer les statuts de jeu
          _handleGameStatus(status);
          break;
      }
    });
  }

  void _handleGameStatus(String? status) {
    if (!mounted) return;

    debugPrint('🔄 Traitement du statut: $status');

    setState(() {
      switch (status) {
        case 'starting':
          _gamePhase = GamePhase.inProgress;
          _blinkController.stop();
          break;
        case 'confirmed':
          if (_gamePhase == GamePhase.starting) {
            _gamePhase = GamePhase.inProgress;
          }
          break;
        case 'finished':
          _handleGameFinished();
          break;
        case 'waiting_group':
          _gamePhase = GamePhase.waitingGroup;
          break;
      }
    });
  }

  void _handleGameFinished() async {
    if (!mounted) return;
    debugPrint('🏁 Début du traitement de fin de jeu');

    setState(() {
      _gamePhase = GamePhase.finished;
      _showFinGameOverlay = true;
    });
    _overlayController.forward();

    await Future.delayed(const Duration(seconds: 5));
    if (!mounted) return;

    _overlayController.reverse();
    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted && !_hasNavigatedToClassement) {
      debugPrint('➡️ Navigation vers l\'écran de classement');
      _hasNavigatedToClassement = true;
      final scores = Provider.of<WebSocketService>(context, listen: false)
          .scoresNotifier.value;
      final finalScores = List.generate(4, (i) => scores[i] ?? 0);

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ClassementScreen(finalScores: finalScores),
        ),
      );
    }
  }

  void _startGame() async {
    if (_gamePhase != GamePhase.readyToStart) {
      debugPrint('⏸️ Démarrage impossible - mauvais état: $_gamePhase');
      return;
    }

    debugPrint('🔄 Tentative de démarrage de la partie...');

    if (mounted) {
      setState(() {
        _gamePhase = GamePhase.starting;
      });
    }

    final ws = Provider.of<WebSocketService>(context, listen: false);
    final success = await ws.sendCommand(
      'start_game',
      'START_GAME',
      timeout: const Duration(seconds: 5),
    );

    if (!mounted) return;

    if (!success) {
      debugPrint('❌ Échec de l\'envoi de START_GAME');
      if (mounted) {
        setState(() {
          _gamePhase = GamePhase.readyToStart;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Échec du démarrage - Timeout serveur')),
        );
      }
    } else {
      debugPrint('📤 START_GAME envoyé avec succès - Attente confirmation...');
    }
  }

  void _nextPlayer() {
    debugPrint('🔄 Passage au joueur suivant');
    final ws = Provider.of<WebSocketService>(context, listen: false);
    ws.sendMessage(json.encode({
      'type': 'next_player',
      'message': 'NEXT_PLAYER',
    }));

    if (mounted) {
      setState(() {
        _currentPlayerIndex = (_currentPlayerIndex + 1) % 4;
      });
    }
  }

  void _nextTurn() async {
    debugPrint('🔄 Passage au tour suivant');
    final ws = Provider.of<WebSocketService>(context, listen: false);
    ws.sendMessage(json.encode({
      'type': 'next_turn',
      'message': 'NEXT_TURN',
    }));

    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        if (_currentRound == null) {
          _currentRound = 1;
        } else if (_currentRound == 3) {
          _currentRound = null;
        } else {
          _currentRound = _currentRound! + 1;
        }
        _currentPlayerIndex = 0;
      });
      await prefs.setInt('currentRound', _currentRound ?? 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = Provider.of<WebSocketService>(context);
    final groupModel = Provider.of<GroupModel>(context);
    debugPrint('🏗️ Rebuild de l\'interface - État: $_gamePhase');

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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              child: Text(
                'Groupe ${groupModel.selectedGroup}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: ElevatedButton(
              onPressed: _gamePhase == GamePhase.readyToStart ? _startGame : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _getGameButtonColor(),
              ),
              child: Text(
                _getGameButtonText(),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: ElevatedButton(
              onPressed: _gamePhase == GamePhase.inProgress ? null : _nextPlayer,
              style: ElevatedButton.styleFrom(
                backgroundColor: _gamePhase == GamePhase.inProgress
                    ? Colors.green
                    : const Color(0xFF7DBFF8),
                disabledBackgroundColor: Colors.green,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text(
                'Joueur suivant',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: _currentRound != null
                ? Badge(
              label: Text('$_currentRound/3'),
              backgroundColor: Colors.orange,
              child: _buildTourSuivantButton(),
            )
                : _buildTourSuivantButton(),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_currentRound != null)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(0, 0, 0, 0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Tour $_currentRound/3',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          SafeArea(
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
          if (_showFinGameOverlay)
            Center(
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
        ],
      ),
    );
  }

  Widget _buildTourSuivantButton() {
    return ElevatedButton(
      onPressed: _gamePhase == GamePhase.inProgress ? null : _nextTurn,
      style: ElevatedButton.styleFrom(
        backgroundColor: _gamePhase == GamePhase.inProgress
            ? Colors.green
            : const Color(0xFF7DBFF8),
        disabledBackgroundColor: Colors.green,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
      ),
      child: const Text(
        'Tour suivant',
        style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black),
      ),
    );
  }

  Color _getGameButtonColor() {
    switch (_gamePhase) {
      case GamePhase.waitingGroup: return Colors.blue;
      case GamePhase.readyToStart: return Colors.orange;
      case GamePhase.inProgress: return Colors.green;
      default: return Colors.blue;
    }
  }

  String _getGameButtonText() {
    switch (_gamePhase) {
      case GamePhase.waitingGroup: return 'Attente groupe';
      case GamePhase.readyToStart: return 'Partie en attente';
      case GamePhase.inProgress: return 'Partie lancée';
      default: return 'Attente groupe';
    }
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
            _buildScoreCard(
                '${pseudos[0] ?? "J1"} : ${scores[0] ?? 0}',
                cardWidth,
                cardHeight,
                fontSize,
                const LinearGradient(colors: [
                  Color(0xFFAEDCFA),
                  Color(0xFF91C9F9)])),
            SizedBox(width: spacing),
            _buildScoreCard(
                '${pseudos[1] ?? "J2"} : ${scores[1] ?? 0}',
                cardWidth,
                cardHeight,
                fontSize,
                const LinearGradient(colors: [
                  Color(0xFF91C9F9),
                  Color(0xFF6AB8F7)])),
          ],
        ),
        SizedBox(height: spacing),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildScoreCard(
                '${pseudos[2] ?? "J3"} : ${scores[2] ?? 0}',
                cardWidth,
                cardHeight,
                fontSize,
                const LinearGradient(colors: [
                  Color(0xFF6AB8F7),
                  Color(0xFF429CF2)])),
            SizedBox(width: spacing),
            _buildScoreCard(
                '${pseudos[3] ?? "J4"} : ${scores[3] ?? 0}',
                cardWidth,
                cardHeight,
                fontSize,
                const LinearGradient(colors: [
                  Color(0xFF429CF2),
                  Color(0xFF1E88E5)])),
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
            color: Colors.white),
        textAlign: TextAlign.center,
      ),
    );
  }

  @override
  void dispose() {
    debugPrint('♻️ Disposing ScoresScreen');
    _controller.dispose();
    _overlayController.dispose();
    _blinkController.dispose();
    _messageSubscription?.cancel();
    super.dispose();
  }
}
