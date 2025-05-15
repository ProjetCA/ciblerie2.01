import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

enum ConnectionStatus {
  connected,
  disconnected,
  connecting,
}

enum GameState {
  idle,
  config, // État pour la configuration des pseudos
  started,
  finished,
}

class WebSocketService with ChangeNotifier {
  WebSocketChannel? _channel;
  final StreamController<String> _messageController = StreamController.broadcast();

  // Scores et données
  final ValueNotifier<Map<int, int>> scoresNotifier = ValueNotifier({
    0: 0,
    1: 0,
    2: 0,
    3: 0,
  });

  // Gestion des pseudonymes
  final ValueNotifier<Map<int, String>> pseudonymsNotifier = ValueNotifier({
    0: 'J1',
    1: 'J2',
    2: 'J3',
    3: 'J4',
  });

  final ValueNotifier<Map<int, Map<int, int>>> frequenciesNotifier = ValueNotifier({
    0: {5: 0, 10: 0, 15: 0, 25: 0, 50: 0, 100: 0, 150: 0, 200: 0, 250: 0},
    1: {5: 0, 10: 0, 15: 0, 25: 0, 50: 0, 100: 0, 150: 0, 200: 0, 250: 0},
    2: {5: 0, 10: 0, 15: 0, 25: 0, 50: 0, 100: 0, 150: 0, 200: 0, 250: 0},
    3: {5: 0, 10: 0, 15: 0, 25: 0, 50: 0, 100: 0, 150: 0, 200: 0, 250: 0},
  });

  final ValueNotifier<List<int>?> lastFinalScores = ValueNotifier(null);
  final ValueNotifier<bool> showSaveButton = ValueNotifier(false);
  final ValueNotifier<String> groupNotifier = ValueNotifier("A");

  // Ajout : Notifier pour afficher les messages temporaires
  final ValueNotifier<String?> feedbackNotifier = ValueNotifier(null);

  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  String _serverIp = '';
  Timer? _reconnectTimer;

  GameState _gameState = GameState.idle;
  GameState get gameState => _gameState;

  String _group = "A";
  String get group => _group;

  WebSocketService() {
    _loadSavedIP();
  }

  Future<void> _loadSavedIP() async {
    final prefs = await SharedPreferences.getInstance();
    _serverIp = prefs.getString('server_ip') ?? '';
    notifyListeners();
  }

  Future<void> setServerIp(String ip) async {
    if (!_validateIp(ip)) {
      debugPrint('IP invalide : $ip');
      return;
    }

    _serverIp = ip;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_ip', ip);
    notifyListeners();
  }

  void connect() {
    if (_serverIp.isEmpty) {
      debugPrint("IP serveur manquante.");
      return;
    }

    final uri = Uri.parse('ws://$_serverIp');
    _updateStatus(ConnectionStatus.connecting);

    try {
      _channel = WebSocketChannel.connect(uri);
      debugPrint("Connexion WebSocket établie à $uri");

      _channel!.stream.listen(
            (data) {
          debugPrint("Message reçu : $data");
          _messageController.add(data);
          _handleIncomingMessage(data);
        },
        onDone: _handleDisconnection,
        onError: (error) {
          debugPrint("Erreur WebSocket : $error");
          _handleDisconnection();
        },
        cancelOnError: true,
      );

      _updateStatus(ConnectionStatus.connected);
      _cancelReconnectTimer();
    } catch (e) {
      debugPrint("Exception à la connexion WebSocket : $e");
      _handleDisconnection();
    }
  }

  void disconnect() {
    _channel?.sink.close(ws_status.normalClosure);
    _channel = null;
    _updateStatus(ConnectionStatus.disconnected);
    _cancelReconnectTimer();
  }

  void _handleDisconnection() {
    debugPrint("WebSocket déconnectée.");
    _channel = null;
    _updateStatus(ConnectionStatus.disconnected);
    _startReconnectTimer();
  }

  void _startReconnectTimer() {
    if (_reconnectTimer?.isActive ?? false) return;

    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_connectionStatus == ConnectionStatus.disconnected && _serverIp.isNotEmpty) {
        debugPrint("Tentative de reconnexion WebSocket...");
        connect();
      }
    });
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _updateStatus(ConnectionStatus newStatus) {
    _connectionStatus = newStatus;
    notifyListeners();
  }

  bool _validateIp(String ip) {
    final regex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}(:\d+)?$');
    return regex.hasMatch(ip);
  }

  void setPseudonyms(Map<int, String> pseudonyms) {
    pseudonymsNotifier.value = Map<int, String>.from(pseudonyms);
    notifyListeners();
  }

  void startGame() {
    sendMessage('{"type": "start_game"}'); // Simplification du message
    setGameState(GameState.started);
  }

  void _handleIncomingMessage(String data) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) return;

      final type = decoded['type'];

      switch (type) {
        case 'config_pseudos':
          setGameState(GameState.config);
          break;
        case 'start':
          resetAllScores();
          resetFrequencies();
          setGameState(GameState.started);
          showSaveButton.value = false;
          break;
        case 'fin':
          setGameState(GameState.finished);
          showSaveButton.value = true;
          feedbackNotifier.value = "Fin de la partie !";
          break;
        case 'groupe':
          _group = decoded["value"];
          groupNotifier.value = _group;
          notifyListeners();
          break;
        case 'JOUEUR_SUIVANT':
          feedbackNotifier.value = "Joueur_suivant";
          break;
        case 'TOUR_SUIVANT':
          feedbackNotifier.value = "Tour_suivant";
          break;
        case 'SCORES':
        // Récupérer les informations du joueur et du tour
          final int joueur = decoded['data']['joueur'];
          final int tour = decoded['data']['tour'];
          final String scoresString = decoded['data']['scores']; // Récupérer le tableau JSON sous forme de chaîne

          // Convertir la chaîne JSON en liste d'entiers
          List<dynamic> scores = jsonDecode(scoresString);

          // Traiter les scores
          for (int i = 0; i < scores.length; i++) {
            final int score = scores[i];
            // Mettre à jour les scores du joueur (vous devrez adapter cette partie)
            scoresNotifier.value = {
              ...scoresNotifier.value,
              joueur: score,
            };

            // Mettre à jour les fréquences (vous devrez adapter cette partie)
            final current = Map<int, Map<int, int>>.from(frequenciesNotifier.value);
            final playerFreq = Map<int, int>.from(current[joueur] ?? {});
            playerFreq[score] = (playerFreq[score] ?? 0) + 1;
            current[joueur] = playerFreq;
            frequenciesNotifier.value = current;
          }
          break;
      }
    } catch (e) {
      debugPrint("Erreur WebSocket : $e");
    }
  }

  void sendMessage(String message) {
    if (_channel != null && _connectionStatus == ConnectionStatus.connected) {
      try {
        _channel!.sink.add(message);
      } catch (e) {
        debugPrint("Erreur à l'envoi du message : $e");
      }
    } else {
      debugPrint("Impossible d'envoyer le message : WebSocket non connectée.");
    }
  }

  void resetAllScores() {
    scoresNotifier.value = {
      0: 0,
      1: 0,
      2: 0,
      3: 0,
    };
    scoresNotifier.notifyListeners();
  }

  void resetFrequencies() {
    frequenciesNotifier.value = {
      0: {5: 0, 10: 0, 15: 0, 25: 0, 50: 0, 100: 0, 150: 0, 200: 0, 250: 0},
      1: {5: 0, 10: 0, 15: 0, 25: 0, 50: 0, 100: 0, 150: 0, 200: 0, 250: 0},
      2: {5: 0, 10: 0, 15: 0, 25: 0, 50: 0, 100: 0, 150: 0, 200: 0, 250: 0},
      3: {5: 0, 10: 0, 15: 0, 25: 0, 50: 0, 100: 0, 150: 0, 200: 0, 250: 0},
    };
  }

  void setGameState(GameState state) {
    _gameState = state;
    notifyListeners();
  }

  void clearFinalScores() {
    lastFinalScores.value = null;
  }

  Stream<String> get messages => _messageController.stream;
  ConnectionStatus get status => _connectionStatus;
  String get serverIp => _serverIp;

  @override
  void dispose() {
    disconnect();
    _messageController.close();
    scoresNotifier.dispose();
    pseudonymsNotifier.dispose();
    frequenciesNotifier.dispose();
    lastFinalScores.dispose();
    showSaveButton.dispose();
    groupNotifier.dispose();
    feedbackNotifier.dispose(); // Ajouté
    super.dispose();
  }
}
