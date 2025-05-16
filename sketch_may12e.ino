#include <Arduino.h>

// Groupes de scores
const char* groupes[] = {"F", "SP", "P", "C", "L", "LJ", "MS", "CPT"};
const int nombreGroupes = 8;
// F=0, SP=1, P=2, C=3, L=4, LJ=5, MS=6
int indexgroupe = 0; // Par défaut, groupe "F" = "Facile"

// Configuration des joueurs et scores
const int totalJoueurs = 4;             // Nombre de joueurs (J1 à J4)
const int totalScoresParJoueur = 12;    // Nombre de scores par joueur
const int intervalEnvoi = 1000;         // Intervalle entre chaque envoi (en ms)

// Valeurs possibles des points
const int valeursPoints[] = {5, 10, 15, 25, 50, 100, 150, 200, 250};
const int totalValeursPoints = sizeof(valeursPoints) / sizeof(valeursPoints[0]);

// Variables pour la gestion des scores
int scoresJoueurs[totalJoueurs][totalScoresParJoueur]; // Table des scores pour chaque joueur
int joueurActuel = 0;                                  // Joueur en cours
int scoreActuelIndex = 0;                              // Score actuel à envoyer pour le joueur courant
unsigned long dernierEnvoi = 0;                        // Temps du dernier envoi
int scoreCumule = 0;                                   // Score cumulé pour le joueur courant

// Nouveaux états pour la configuration
bool pseudosConfigures = false;
bool partieDemarree = false;
unsigned long attenteConfigStart = 0;
//const unsigned long timeoutConfig = 30000; // 30 secondes max d'attente

void setup() {
  // Initialisation des ports série
  Serial.begin(115200);    // Moniteur série pour le débogage
  Serial1.begin(9600);     // Communication avec l'ESP32 via Serial1

  // Générer le groupe aléatoire pour la partie
  randomSeed(analogRead(A15)); // Initialisation de la graine pour le générateur aléatoire
  indexgroupe = random(0, nombreGroupes); // Génération aléatoire d'un groupe

  // Génération des points aléatoires pour chaque joueur
  for (int joueur = 0; joueur < totalJoueurs; joueur++) {
    for (int score = 0; score < totalScoresParJoueur; score++) {
      randomSeed(analogRead(A5)); // Initialisation de la graine pour le générateur aléatoire
      scoresJoueurs[joueur][score] = valeursPoints[random(0, totalValeursPoints)];
    }
  }

  Serial.println("🎯 Scores générés pour chaque joueur :");
  for (int joueur = 0; joueur < totalJoueurs; joueur++) {
    Serial.print("J" + String(joueur + 1) + ": ");
    for (int score = 0; score < totalScoresParJoueur; score++) {
      Serial.print(scoresJoueurs[joueur][score]);
      if (score < totalScoresParJoueur - 1) Serial.print(", ");
    }
    Serial.println();
  }

  // Envoi de la demande de configuration des pseudos
  Serial1.println("CONFIG_PSEUDOS");
  Serial.println("📤 Envoi : CONFIG_PSEUDOS");
  attenteConfigStart = millis();
}

void loop() {
  if (!partieDemarree) {
    // Réception depuis ESP32
    if (Serial1.available()) {
      String message = Serial1.readStringUntil('\n');
      message.trim(); // Supprime les retours à la ligne et espaces
      Serial.println("📥 Reçu de ESP32 : " + message);

      if (message.equalsIgnoreCase("START_GAME")) {
        Serial.println("🎮 Commande START_GAME reçue !");
        partieDemarree = true;
        pseudosConfigures = true;
        Serial1.println("Groupe : " + String(groupes[indexgroupe]));
        Serial.println("📤 Envoi : Groupe : " + String(groupes[indexgroupe]));
        dernierEnvoi = millis(); // Démarre l’envoi des scores
      }
    }
    return; // Boucle sans fin jusqu'à réception de START_GAME
  }

  // Gestion des scores après démarrage
  if (millis() - dernierEnvoi >= intervalEnvoi) {
    dernierEnvoi = millis();

    scoreCumule += scoresJoueurs[joueurActuel][scoreActuelIndex];

    String message = "J" + String(joueurActuel + 1) + " : " + 
                     String(scoresJoueurs[joueurActuel][scoreActuelIndex]) + " : " + 
                     String(scoreCumule);
    Serial1.println(message);
    Serial.println("📤 Envoi : " + message);

    scoreActuelIndex++;
    if (scoreActuelIndex >= totalScoresParJoueur) {
      scoreActuelIndex = 0;
      scoreCumule = 0;
      joueurActuel++;

      if (joueurActuel >= totalJoueurs) {
        Serial1.println("FIN_GAME");
        Serial.println("📤 Envoi : FIN_GAME");

        // Redémarrer ? Attendre une nouvelle commande ?
        // ==> Option A: geler (comme tu faisais)
        // while (true);

        // ==> Option B: Réinitialiser pour une nouvelle partie
        joueurActuel = 0;
        partieDemarree = false;
        pseudosConfigures = false;
        setup(); // Regénère les scores, renvoie CONFIG_PSEUDOS
      }
    }
  }
}
