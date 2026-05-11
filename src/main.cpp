#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include <Stepper.h>

const char* ssid     = "Catapulta_IME";
const char* password = "senha_segura";

WebServer server(80);

const int LED_VERDE        = 21;
const int PASSOS_POR_VOLTA = 2048;

// --- Calibracao fisica (ajustar apos testes mecanicos) ---
// Mapa linear: DIST_MIN_M -> PASSOS_MIN, DIST_MAX_M -> PASSOS_MAX
const float DIST_MIN_M    = 0.5f;
const float DIST_MAX_M    = 4.0f;
const int   PASSOS_MIN    = 200;   // tensao minima: ~1/10 de volta
const int   PASSOS_MAX    = 4096;  // tensao maxima: 2 voltas completas
const int   PASSOS_GATILHO = PASSOS_POR_VOLTA / 4;  // 1/4 de volta = 512 passos
// ---------------------------------------------------------

// Ordem de pinos: IN1, IN3, IN2, IN4 (correcao de fase para ULN2003)
Stepper motorEsticador(PASSOS_POR_VOLTA, 19, 5, 18, 17);
Stepper motorGatilho  (PASSOS_POR_VOLTA, 16, 2,  4, 15);

bool sistemaArmado = false;
int  passosAtuais  = 0;

// Gira o motor em chunks para alimentar o Watchdog Timer do ESP32
void stepComYield(Stepper& motor, int passos) {
  const int CHUNK = 64;
  int sinal     = (passos >= 0) ? 1 : -1;
  int restantes = abs(passos);
  while (restantes > 0) {
    int agora = min(restantes, CHUNK);
    motor.step(sinal * agora);
    restantes -= agora;
    yield();
  }
}

int distanciaParaPassos(float metros) {
  metros = constrain(metros, DIST_MIN_M, DIST_MAX_M);
  float ratio = (metros - DIST_MIN_M) / (DIST_MAX_M - DIST_MIN_M);
  return (int)(PASSOS_MIN + ratio * (PASSOS_MAX - PASSOS_MIN));
}

void handleArmar() {
  if (!server.hasArg("distancia")) {
    server.send(400, "text/plain", "Erro: parametro 'distancia' ausente.");
    return;
  }
  float dist = server.arg("distancia").toFloat();
  if (dist < DIST_MIN_M || dist > DIST_MAX_M) {
    server.send(400, "text/plain",
      "Erro: distancia fora do intervalo [0.5, 4.0] m.");
    return;
  }
  int passos = distanciaParaPassos(dist);
  server.send(200, "text/plain",
    "Armando para " + String(dist, 1) + "m (" + String(passos) + " passos)");
  stepComYield(motorEsticador, passos);
  passosAtuais  = passos;
  sistemaArmado = true;
  digitalWrite(LED_VERDE, HIGH);
  Serial.printf("[ARMAR] %.1fm -> %d passos\n", dist, passos);
}

void handleFogo() {
  if (!sistemaArmado) {
    server.send(400, "text/plain", "Erro: sistema nao armado. Use /armar primeiro.");
    return;
  }
  server.send(200, "text/plain", "Fogo! Liberando trava.");
  stepComYield(motorGatilho,  PASSOS_GATILHO);
  delay(500);
  stepComYield(motorGatilho, -PASSOS_GATILHO);
  sistemaArmado = false;
  digitalWrite(LED_VERDE, LOW);
  Serial.println("[FOGO] Tiro realizado. Sistema pronto.");
}

void handleDesarmar() {
  if (!sistemaArmado) {
    server.send(200, "text/plain", "Ja estava desarmado.");
    return;
  }
  server.send(200, "text/plain", "Desarmando...");
  stepComYield(motorEsticador, -passosAtuais);
  passosAtuais  = 0;
  sistemaArmado = false;
  digitalWrite(LED_VERDE, LOW);
  Serial.println("[DESARMAR] Tensao liberada.");
}

void handleStatus() {
  server.send(200, "text/plain", sistemaArmado ? "armado" : "pronto");
}

void setup() {
  Serial.begin(115200);
  pinMode(LED_VERDE, OUTPUT);
  digitalWrite(LED_VERDE, LOW);

  WiFi.softAP(ssid, password);
  Serial.print("AP ativo. IP: ");
  Serial.println(WiFi.softAPIP());

  motorEsticador.setSpeed(12);
  motorGatilho.setSpeed(12);

  server.on("/armar",    handleArmar);
  server.on("/fogo",     handleFogo);
  server.on("/desarmar", handleDesarmar);
  server.on("/status",   handleStatus);
  server.begin();
  Serial.println("Servidor HTTP iniciado. Aguardando comandos...");
}

void loop() {
  server.handleClient();
}
