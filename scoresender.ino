#include <Arduino.h>

// Groupes de scores
const char* groupes[] = {"F", "SP", "P", "C", "L", "LJ", "MS", "CPT"};
const int nombreGroupes = 8;
int indexgroupe = 0; // Par défaut, groupe "F" = "Facile"

// Configuration des joueurs et scores
const int totalJoueurs = 4;             // Nombre de joueurs (J1 à J4)
const int totalScoresParJoueur = 12;    // Nombre de scores tirés par joueur
const int totalTours = 3;               // Nombre total de tours
const int intervalEnvoi = 1000;         // Intervalle entre chaque envoi (en ms)

// Valeurs possibles des points
const int valeursPoints[] = {5, 10, 15, 25, 50, 100, 150, 200, 250};
const int totalValeursPoints = sizeof(valeursPoints) / sizeof(valeursPoints[0]);

// Variables pour la gestion des scores
int scoresJoueurs[totalJoueurs];                      // Score cumulé pour chaque joueur
int pointsTires[totalScoresParJoueur];                // Points tirés pour le joueur en cours
int joueurActuel = 0;                                 // Joueur en cours
int tourActuel = 1;                                   // Tour actuel
int scoreActuelIndex = 0;                             // Index du score actuel
unsigned long dernierEnvoi = 0;                       // Temps du dernier envoi
bool partieDemarree = false;                          // État de la partie
bool finPartie = false;                               // Indicateur de fin de partie
bool attenteSignal = false;                           // Indicateur d'attente pour message WebSocket

void tirageAleatoirePoints() {
  Serial.println("🎲 Tirage des points pour Joueur " + String(joueurActuel + 1) + " :");
  for (int i = 0; i < totalScoresParJoueur; i++) {
    pointsTires[i] = valeursPoints[random(0, totalValeursPoints)];
    Serial.print(pointsTires[i]);
    if (i < totalScoresParJoueur - 1) Serial.print(", ");
  }
  Serial.println();
}

void setup() {
  Serial.begin(115200);    // Moniteur série pour le débogage
  Serial1.begin(9600);     // Communication avec l'ESP32 via Serial1

  randomSeed(analogRead(A15)); // Initialisation de la graine pour le générateur aléatoire
  indexgroupe = random(0, nombreGroupes); // Génération aléatoire d'un groupe

  for (int i = 0; i < totalJoueurs; i++) {
    scoresJoueurs[i] = 0;
  }

  Serial.println("🎯 Jeu initialisé avec les paramètres suivants :");
  Serial.println("🔢 Groupe de difficulté : " + String(groupes[indexgroupe]));
  Serial.println("🟢 Prêt pour démarrer la partie !");
  Serial1.println("CONFIG_PSEUDOS"); // Demande de configuration des pseudos
}

void gestionPointsEtTransmission() {
  int points = pointsTires[scoreActuelIndex];
  scoresJoueurs[joueurActuel] += points;

  String message = "{\"player\": " + String(joueurActuel + 1) +
                   ", \"points\": " + String(points) +
                   ", \"totalScore\": " + String(scoresJoueurs[joueurActuel]) + "}";
  Serial1.println(message);
  Serial.println("📤 Envoi : " + message);
}

void gestionTransitions() {
  scoreActuelIndex++;

  if (scoreActuelIndex >= totalScoresParJoueur) {
    scoreActuelIndex = 0; 
    joueurActuel++;       

    if (joueurActuel >= totalJoueurs) {
      joueurActuel = 0; 
      tourActuel++;     

      if (tourActuel > totalTours) { 
        finPartie = true;
        Serial1.println("{\"event\": \"FIN_GAME\"}");
        Serial.println("🏁 La partie est terminée !");
        return;
      }

      Serial.println("🔄 Passage au tour suivant : Tour " + String(tourActuel));
      Serial1.println("{\"event\": \"TOUR_SUIVANT\", \"tour\": " + String(tourActuel) + "}");
    }

    tirageAleatoirePoints();
    Serial.println("🔄 Passage au joueur suivant : Joueur " + String(joueurActuel + 1));
    Serial1.println("{\"event\": \"JOUEUR_SUIVANT\", \"player\": " + String(joueurActuel + 1) + "}");
  }
}

void attendreSignalWebSocket() {
  if (Serial1.available()) {
    String message = Serial1.readStringUntil('\n');
    message.trim();

    if (message == "CONTINUER_JOUEUR") {
      Serial.println("📥 Signal reçu : CONTINUER_JOUEUR");
      attenteSignal = false; 
    } else if (message == "CONTINUER_TOUR") {
      Serial.println("📥 Signal reçu : CONTINUER_TOUR");
      attenteSignal = false; 
    }
  }
}

void loop() {
  if (!partieDemarree) {
    if (Serial1.available()) {
      String message = Serial1.readStringUntil('\n');
      message.trim();
      Serial.println("📥 Reçu de ESP32 : " + message);

      if (message.equalsIgnoreCase("START_GAME")) {
        Serial.println("🎮 Commande START_GAME reçue !");
        partieDemarree = true;
        Serial1.println("{\"group\": \"" + String(groupes[indexgroupe]) + "\"}");
        Serial.println("📤 Envoi : Groupe : " + String(groupes[indexgroupe]));
        dernierEnvoi = millis();

        tirageAleatoirePoints();
      }
    }
    return;
  }

  if (attenteSignal) {
    attendreSignalWebSocket();
    return;
  }

  if (millis() - dernierEnvoi >= intervalEnvoi && !finPartie) {
    dernierEnvoi = millis();

    gestionPointsEtTransmission();
    gestionTransitions();

    if (finPartie) {
      Serial.println("🏁 Réinitialisation du jeu pour une nouvelle partie.");
      joueurActuel = 0;
      tourActuel = 1;
      partieDemarree = false;
      setup();
    }
  }
}