#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include <Stepper.h>
#include <ArduinoOTA.h>

const char* ssid     = "Catapulta_IME";
const char* password = "senha_segura";

WebServer server(80);

const int LED_VERDE        = 21;
const int LED_POWER        = 13;  // aceso enquanto o sistema estiver ligado
const int PASSOS_POR_VOLTA = 2048;

// --- Calibracao fisica (ajustar via app ou apos testes mecanicos) ---
const float DIST_MIN_M = 0.5f;
const float DIST_MAX_M = 4.0f;
int passosMin     = 200;
int passosMax     = 4096;
int passosGatilho = PASSOS_POR_VOLTA / 4;
// ---------------------------------------------------------------------

// Pinos declarados explicitamente para permitir desligar coils por software
// Ordem: IN1, IN3, IN2, IN4 (correcao de fase para ULN2003/28BYJ-48)
const int PINOS_TRACAO1[4] = {19,  5, 18, 17};  // existente, mantido
const int PINOS_TRACAO2[4] = {22, 23, 25, 26};  // novo motor, pinos livres
const int PINOS_GATILHO[4] = {16,  2,  4, 15};  // existente, mantido

Stepper motorTracao1(PASSOS_POR_VOLTA,
  PINOS_TRACAO1[0], PINOS_TRACAO1[1], PINOS_TRACAO1[2], PINOS_TRACAO1[3]);
Stepper motorTracao2(PASSOS_POR_VOLTA,
  PINOS_TRACAO2[0], PINOS_TRACAO2[1], PINOS_TRACAO2[2], PINOS_TRACAO2[3]);
Stepper motorGatilho(PASSOS_POR_VOLTA,
  PINOS_GATILHO[0], PINOS_GATILHO[1], PINOS_GATILHO[2], PINOS_GATILHO[3]);

bool sistemaArmado = false;
int  passosAtuais  = 0;

// Corta corrente nas bobinas do motor — reducao 1:64 do 28BYJ-48 segura
// a posicao mecanicamente sem precisar de corrente continua.
void desligarCoils(const int* pinos) {
  for (int i = 0; i < 4; i++) digitalWrite(pinos[i], LOW);
}

// Alimenta o WDT a cada 64 passos para evitar reset em movimentos longos.
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

// M1 e M2 ficam de frente no mesmo cilindro: para somar forca sem torcer o
// eixo, um gira horario enquanto o outro gira anti-horario. Passa-se 1 passo
// por vez alternando os dois para sincronismo mecanico real.
void stepSincronizado(int passos) {
  int sinal     = (passos >= 0) ? 1 : -1;
  int restantes = abs(passos);
  while (restantes > 0) {
    motorTracao1.step( sinal);   // horario
    motorTracao2.step(-sinal);   // anti-horario (espelhado)
    restantes--;
    if (restantes % 64 == 0) yield();
  }
}

int distanciaParaPassos(float metros) {
  metros = constrain(metros, DIST_MIN_M, DIST_MAX_M);
  float ratio = (metros - DIST_MIN_M) / (DIST_MAX_M - DIST_MIN_M);
  return (int)(passosMin + ratio * (passosMax - passosMin));
}

// --- ESTADO DE TRACAO ---
// Gatilho desligado eletricamente; ambos motores de tracao giram sincronizados.
// Ao terminar, tracao tambem desliga (reducao seguura posicao sem corrente).
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

  desligarCoils(PINOS_GATILHO);       // interlock: gatilho off durante tracao
  stepSincronizado(passos);
  desligarCoils(PINOS_TRACAO1);       // estado armado: tracao off, poupa pilha
  desligarCoils(PINOS_TRACAO2);

  passosAtuais  = passos;
  sistemaArmado = true;
  digitalWrite(LED_VERDE, HIGH);
  Serial.printf("[ARMAR] %.1fm -> %d passos\n", dist, passos);
}

// --- ESTADO DE DISPARO ---
// Tracao garantidamente desligada; apenas gatilho se move.
void handleFogo() {
  if (!sistemaArmado) {
    server.send(400, "text/plain", "Erro: sistema nao armado. Use /armar primeiro.");
    return;
  }
  server.send(200, "text/plain", "Fogo! Liberando trava.");

  desligarCoils(PINOS_TRACAO1);       // interlock: garante tracao off
  desligarCoils(PINOS_TRACAO2);
  stepComYield(motorGatilho,  passosGatilho);
  delay(500);
  stepComYield(motorGatilho, -passosGatilho);
  desligarCoils(PINOS_GATILHO);

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

  desligarCoils(PINOS_GATILHO);       // interlock: gatilho off
  stepSincronizado(-passosAtuais);    // reverte exatamente os passos usados
  desligarCoils(PINOS_TRACAO1);
  desligarCoils(PINOS_TRACAO2);

  passosAtuais  = 0;
  sistemaArmado = false;
  digitalWrite(LED_VERDE, LOW);
  Serial.println("[DESARMAR] Tensao liberada.");
}

void handleConfigurar() {
  if (sistemaArmado) {
    server.send(400, "text/plain", "Erro: desarme o sistema antes de reconfigurar.");
    return;
  }
  bool atualizado = false;
  int novoMin = passosMin, novoMax = passosMax, novoGatilho = passosGatilho;

  if (server.hasArg("passos_min")) {
    int v = server.arg("passos_min").toInt();
    if (v > 0) { novoMin = v; atualizado = true; }
  }
  if (server.hasArg("passos_max")) {
    int v = server.arg("passos_max").toInt();
    if (v > 0) { novoMax = v; atualizado = true; }
  }
  if (server.hasArg("passos_gatilho")) {
    int v = server.arg("passos_gatilho").toInt();
    if (v > 0) { novoGatilho = v; atualizado = true; }
  }

  if (!atualizado) {
    server.send(400, "text/plain", "Erro: nenhum parametro valido recebido.");
    return;
  }
  if (novoMin >= novoMax) {
    server.send(400, "text/plain", "Erro: passos_min deve ser menor que passos_max.");
    return;
  }

  passosMin     = novoMin;
  passosMax     = novoMax;
  passosGatilho = novoGatilho;
  server.send(200, "text/plain",
    "Configurado: min=" + String(passosMin) +
    " max=" + String(passosMax) +
    " gatilho=" + String(passosGatilho));
  Serial.printf("[CONFIG] passos_min=%d passos_max=%d passos_gatilho=%d\n",
    passosMin, passosMax, passosGatilho);
}

void handleStatus() {
  server.send(200, "text/plain", sistemaArmado ? "armado" : "pronto");
}

void setup() {
  Serial.begin(115200);
  pinMode(LED_VERDE, OUTPUT);
  digitalWrite(LED_VERDE, LOW);
  pinMode(LED_POWER, OUTPUT);
  digitalWrite(LED_POWER, HIGH);

  // Configura todos os pinos como saida e garante coils desligados na inicializacao
  for (int i = 0; i < 4; i++) {
    pinMode(PINOS_TRACAO1[i], OUTPUT); digitalWrite(PINOS_TRACAO1[i], LOW);
    pinMode(PINOS_TRACAO2[i], OUTPUT); digitalWrite(PINOS_TRACAO2[i], LOW);
    pinMode(PINOS_GATILHO[i], OUTPUT); digitalWrite(PINOS_GATILHO[i], LOW);
  }

  WiFi.softAP(ssid, password);
  Serial.print("AP ativo. IP: ");
  Serial.println(WiFi.softAPIP());

  motorTracao1.setSpeed(12);
  motorTracao2.setSpeed(12);
  motorGatilho.setSpeed(12);

  server.on("/armar",      handleArmar);
  server.on("/fogo",       handleFogo);
  server.on("/desarmar",   handleDesarmar);
  server.on("/configurar", handleConfigurar);
  server.on("/status",     handleStatus);
  server.begin();
  Serial.println("Servidor HTTP iniciado. Aguardando comandos...");

  ArduinoOTA.setHostname("catapulta-ime");
  ArduinoOTA.setPassword("ota_catapulta");
  ArduinoOTA.onStart([]() { Serial.println("[OTA] Iniciando upload..."); });
  ArduinoOTA.onEnd([]()   { Serial.println("[OTA] Upload concluido!"); });
  ArduinoOTA.onError([](ota_error_t error) {
    Serial.printf("[OTA] Erro %u\n", error);
  });
  ArduinoOTA.begin();
  Serial.println("OTA pronto em 192.168.4.1");
}

void loop() {
  ArduinoOTA.handle();
  server.handleClient();
}
