# Catapulta IME — Grupo B1

Projeto de competição do IME. Uma catapulta controlada por celular via WiFi, com firmware para ESP32 e app Android em Flutter.

## Como funciona

O ESP32 cria uma rede WiFi própria (`Catapulta_IME`). O celular se conecta a essa rede e envia comandos HTTP para armar e disparar. Dois motores de passo controlam o mecanismo:

- **Motor esticador** — tensiona o elástico de acordo com a distância alvo
- **Motor gatilho** — libera a trava para disparar

A distância configurada (0,5 m a 4,0 m) é convertida linearmente em número de passos do motor esticador.

## Estrutura do repositório

```
├── src/main.cpp          # Firmware ESP32 (Arduino/PlatformIO)
├── platformio.ini        # Configuração do PlatformIO
├── catapulta_app/        # App Flutter de controle
│   ├── lib/main.dart     # Código principal do app
│   └── pubspec.yaml
├── include/
└── lib/
```

## Hardware

| Componente | Detalhe |
|---|---|
| Microcontrolador | ESP32 DOIT DevKit v1 |
| Motor esticador | 28BYJ-48 + ULN2003 (pinos 19, 5, 18, 17) |
| Motor gatilho | 28BYJ-48 + ULN2003 (pinos 16, 2, 4, 15) |
| LED de status | Verde — pino 21 (aceso = armado) |

## API HTTP (ESP32)

O ESP32 expõe um servidor HTTP em `192.168.4.1:80`.

| Endpoint | Descrição |
|---|---|
| `GET /armar?distancia=X.X` | Tensiona o elástico para a distância em metros (0,5–4,0) |
| `GET /fogo` | Dispara (só funciona se armado) |
| `GET /desarmar` | Libera a tensão sem disparar |
| `GET /status` | Retorna `armado` ou `pronto` |

## Calibração

Edite as constantes no topo de `src/main.cpp` após testes mecânicos:

```cpp
const float DIST_MIN_M  = 0.5f;   // distância mínima (m)
const float DIST_MAX_M  = 4.0f;   // distância máxima (m)
const int   PASSOS_MIN  = 200;    // passos para distância mínima
const int   PASSOS_MAX  = 4096;   // passos para distância máxima
```

## Como usar

### 1. Gravar o firmware

```bash
# Com PlatformIO instalado (VS Code + extensão PlatformIO)
pio run --target upload
```

### 2. Rodar o app

```bash
cd catapulta_app
flutter pub get
flutter run
```

### 3. Operar

1. Ligue a catapulta (ESP32 inicializa e cria o WiFi `Catapulta_IME`)
2. No celular, conecte ao WiFi **Catapulta_IME** (senha: `senha_segura`)
3. Abra o app, ajuste a distância no slider e toque em **ARMAR**
4. Aguarde o LED verde acender, depois toque em **LANÇAR**

## Dependências

**Firmware**
- [PlatformIO](https://platformio.org/) com plataforma `espressif32`
- Biblioteca `Stepper` (Arduino built-in)

**App**
- Flutter ≥ 3.x / Dart SDK ^3.11.5
- [`http`](https://pub.dev/packages/http) ^1.2.0
