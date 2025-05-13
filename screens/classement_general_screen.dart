import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ClassementGeneralScreen extends StatefulWidget {
  final String winnerPseudo;
  final int winnerScore;

  const ClassementGeneralScreen({
    super.key,
    required this.winnerPseudo,
    required this.winnerScore,
  });

  @override
  State<ClassementGeneralScreen> createState() => _ClassementGeneralScreenState();
}

class _ClassementGeneralScreenState extends State<ClassementGeneralScreen> {
  Map<String, int> _bestScores = {};
  final storage = const FlutterSecureStorage();

  final List<List<Color>> fixedGradients = [
    [Color(0xFF4A148C), Color(0xFF6A1B9A)],
    [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
    [Color(0xFF8E24AA), Color(0xFFBA68C8)],
  ];
  final List<double> fixedFontSizes = [48, 40, 34];
  final List<Color> defaultGradient = [Color(0xFFBA68C8), Color(0xFFCE93D8)];
  final double defaultFontSize = 28;

  @override
  void initState() {
    super.initState();
    _saveWinnerToStorage().then((_) => _loadBestScores());
  }

  Future<void> _saveWinnerToStorage() async {
    final raw = await storage.read(key: 'score_history');
    Map<String, dynamic> history = {};

    if (raw != null) {
      history = jsonDecode(raw) as Map<String, dynamic>;
    }

    final now = DateTime.now();
    final entry = {
      'score': widget.winnerScore,
      'timestamp': now.toIso8601String(),
    };

    if (history[widget.winnerPseudo] == null) {
      history[widget.winnerPseudo] = [entry];
    } else if (history[widget.winnerPseudo] is List) {
      history[widget.winnerPseudo].add(entry);
    }

    await storage.write(key: 'score_history', value: jsonEncode(history));
  }

  Future<void> _loadBestScores() async {
    final raw = await storage.read(key: 'score_history');
    if (raw == null) return;

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    Map<String, int> scores = {};

    decoded.forEach((player, entries) {
      final list = (entries as List).map((e) => Map<String, dynamic>.from(e)).toList();

      final best = list.fold<int>(0, (max, e) {
        final score = e['score'];
        int parsedScore = 0;

        if (score is int) {
          parsedScore = score;
        } else if (score is double) {
          parsedScore = score.toInt();
        } else if (score is String) {
          parsedScore = int.tryParse(score) ?? 0;
        }

        return parsedScore > max ? parsedScore : max;
      });

      scores[player] = best;
    });

    setState(() {
      _bestScores = scores;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sortedEntries = _bestScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final totalPlayers = sortedEntries.length < 6 ? 6 : sortedEntries.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Classement général'),
      ),
      body: ListView.builder(
        itemCount: totalPlayers,
        itemBuilder: (context, index) {
          final rank = index + 1;

          final label = sortedEntries.length > index
              ? '$rank${_suffix(rank)} : ${sortedEntries[index].key} (${sortedEntries[index].value})'
              : '$rank${_suffix(rank)} :';

          final gradient = index < 3 ? fixedGradients[index] : defaultGradient;
          final fontSize = index < 3 ? fixedFontSizes[index] : defaultFontSize;

          return GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Vous avez cliqué sur le joueur $rank')),
              );
            },
            child: Container(
              height: 80,
              margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradient,
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (index < 3)
                      Icon(
                        index == 0 ? Icons.emoji_events : (index == 1 ? Icons.star : Icons.star_half),
                        color: Colors.amber,
                      ),
                    SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _suffix(int rank) => rank == 1 ? 'er' : 'e';
}
