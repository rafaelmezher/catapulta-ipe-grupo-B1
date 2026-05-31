#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include <Stepper.h>
#include <ESP32Servo.h>
#include <ArduinoOTA.h>

const char* ssid     = "Catapulta_IME";
const char* password = "senha_segura";

WebServer server(80);

const int LED_POWER        = 5;
const int PASSOS_POR_VOLTA = 2048;

// Pino PWM do Servo MG996R
const int PINO_SERVO     = 19;
const int SERVO_REPOUSO  = 0;     // graus na posicao desarmada

const float DIST_MIN_M = 0.5f;
const float DIST_MAX_M = 4.0f;

// Calibracao balistica — ajustaveis em tempo real via /configurar
int anguloMin = 45;   // graus para DIST_MIN_M (0,5 m)
int anguloMax = 180;  // graus para DIST_MAX_M (4,0 m)

// 15 ms por grau = ~2.7 s no sweep maximo; limita pico de corrente do MG996R
const int SWEEP_DELAY_MS = 15;

// Gaps de segurança no ciclo de disparo (ajustar conforme testes)
const int DELAY_APICE_MS   = 2000;  // apos cancela soltar: aguarda braco atingir apice
const int DELAY_RETORNO_MS = 2000;  // apos servo voltar a 0: aguarda braco descer totalmente

// Passos do 28BYJ-48 para acionar/recuar o pino da trava
int passosGatilho = PASSOS_POR_VOLTA / 4;

// IN1, IN3, IN2, IN4 — correto para ULN2003/28BYJ-48
const int PINOS_GATILHO[4] = {16, 2, 4, 15};

Servo   servoTracao;
Stepper motorGatilho(PASSOS_POR_VOLTA,
           PINOS_GATILHO[0], PINOS_GATILHO[1],
           PINOS_GATILHO[2], PINOS_GATILHO[3]);

bool sistemaArmado = false;
int  anguloAtual   = 0;   // angulo em que o servo esta segurando (0 = repouso)

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

// Sweep suave de 'de' ate 'ate' graus.
// Nao chama detach ao final — o servo deve manter o sinal PWM para segurar
// a posicao contra a carga do elastico.
void servoSweep(int de, int ate) {
  int passo = (ate >= de) ? 1 : -1;
  for (int pos = de; pos != ate + passo; pos += passo) {
    servoTracao.write(pos);
    delay(SWEEP_DELAY_MS);
    if (abs(pos - de) % 16 == 0) yield();
  }
}

// Converte distancia (m) para angulo (graus) por interpolacao linear.
int distanciaParaAngulo(float metros) {
  metros = constrain(metros, DIST_MIN_M, DIST_MAX_M);
  float ratio  = (metros - DIST_MIN_M) / (DIST_MAX_M - DIST_MIN_M);
  float angulo = anguloMin + ratio * (float)(anguloMax - anguloMin);
  return (int)roundf(angulo);
}

// --- /armar ---
// Gatilho desligado (interlock). Servo sobe suavemente de 0 ate o angulo
// correspondente a distancia solicitada e permanece energizado nessa posicao.
void handleArmar() {
  if (sistemaArmado) {
    server.send(400, "text/plain", "Erro: sistema ja esta armado.");
    return;
  }
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

  int angulo = distanciaParaAngulo(dist);
  server.send(200, "text/plain",
    "Armando para " + String(dist, 1) + "m -> " + String(angulo) + " graus.");

  desligarCoils(PINOS_GATILHO);
  servoSweep(SERVO_REPOUSO, angulo);
  // Servo permanece attached — nao chamar detach enquanto elastico estiver tenso

  anguloAtual   = angulo;
  sistemaArmado = true;
  Serial.printf("[ARMAR] %.1fm -> %d graus. Sistema armado.\n", dist, angulo);
}

// --- /fogo ---
// Servo segura no angulo atual durante a liberacao da trava. Apos o tiro,
// o elastico foi liberado e o PWM pode ser descartado.
void handleFogo() {
  if (!sistemaArmado) {
    server.send(400, "text/plain", "Erro: sistema nao armado. Use /armar primeiro.");
    return;
  }
  server.send(200, "text/plain", "Fogo! Liberando trava.");

  stepComYield(motorGatilho, passosGatilho);   // 1. solta a cancela
  delay(DELAY_APICE_MS);                       // 2. aguarda braco atingir apice do lancamento
  servoSweep(anguloAtual, SERVO_REPOUSO);      // 3. servo volta a 0° liberando o elastico
  delay(DELAY_RETORNO_MS);                     // 4. aguarda braco descer totalmente por gravidade
  stepComYield(motorGatilho, -passosGatilho);  // 5. trava a cancela (braco em repouso)
  desligarCoils(PINOS_GATILHO);

  anguloAtual   = 0;
  sistemaArmado = false;
  Serial.println("[FOGO] Tiro realizado. Servo em 0. Pronto para recarga.");
}

// --- /desarmar ---
// Recolhe o servo do angulo atual de volta a 0 sem solavanco, entao libera PWM.
void handleDesarmar() {
  if (!sistemaArmado) {
    server.send(200, "text/plain", "Ja estava desarmado. Servo em repouso.");
    return;
  }
  server.send(200, "text/plain",
    "Desarmando: servo " + String(anguloAtual) + "->0 graus.");

  desligarCoils(PINOS_GATILHO);
  servoSweep(anguloAtual, SERVO_REPOUSO);
  // Servo permanece attached em 0° — pronto para o proximo arme sem salto

  anguloAtual   = 0;
  sistemaArmado = false;
  Serial.println("[DESARMAR] Tensao liberada. Pronto para recarga manual.");
}

void handleConfigurar() {
  if (sistemaArmado) {
    server.send(400, "text/plain", "Erro: desarme o sistema antes de reconfigurar.");
    return;
  }

  bool atualizado = false;
  int novoGatilho  = passosGatilho;
  int novoAngMin   = anguloMin;
  int novoAngMax   = anguloMax;

  if (server.hasArg("passos_gatilho")) {
    int v = server.arg("passos_gatilho").toInt();
    if (v > 0) { novoGatilho = v; atualizado = true; }
  }
  if (server.hasArg("angulo_min")) {
    int v = server.arg("angulo_min").toInt();
    if (v >= 0 && v <= 180) { novoAngMin = v; atualizado = true; }
  }
  if (server.hasArg("angulo_max")) {
    int v = server.arg("angulo_max").toInt();
    if (v >= 0 && v <= 180) { novoAngMax = v; atualizado = true; }
  }

  if (!atualizado) {
    server.send(400, "text/plain", "Erro: nenhum parametro valido recebido.");
    return;
  }
  if (novoAngMin >= novoAngMax) {
    server.send(400, "text/plain", "Erro: angulo_min deve ser menor que angulo_max.");
    return;
  }

  passosGatilho = novoGatilho;
  anguloMin     = novoAngMin;
  anguloMax     = novoAngMax;

  server.send(200, "text/plain",
    "Configurado: angulo_min=" + String(anguloMin) +
    " angulo_max=" + String(anguloMax) +
    " passos_gatilho=" + String(passosGatilho));
  Serial.printf("[CONFIG] angulo_min=%d angulo_max=%d passos_gatilho=%d\n",
    anguloMin, anguloMax, passosGatilho);
}

void handleStatus() {
  String resposta = sistemaArmado
    ? "armado (" + String(anguloAtual) + " graus)"
    : "pronto";
  server.send(200, "text/plain", resposta);
}

void setup() {
  Serial.begin(115200);
  pinMode(LED_POWER, OUTPUT);
  digitalWrite(LED_POWER, HIGH);

  for (int i = 0; i < 4; i++) {
    pinMode(PINOS_GATILHO[i], OUTPUT);
    digitalWrite(PINOS_GATILHO[i], LOW);
  }

  // Servo attached desde o boot em 0° — elimina salto no primeiro arme
  servoTracao.attach(PINO_SERVO, 500, 2500);
  servoTracao.write(SERVO_REPOUSO);
  delay(500);

  WiFi.softAP(ssid, password);
  Serial.print("AP ativo. IP: ");
  Serial.println(WiFi.softAPIP());

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
