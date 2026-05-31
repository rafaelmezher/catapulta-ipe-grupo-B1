import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const CatapultaApp());

class CatapultaApp extends StatelessWidget {
  const CatapultaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Catapulta IME',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ControlePage(),
    );
  }
}

class ControlePage extends StatefulWidget {
  const ControlePage({super.key});

  @override
  State<ControlePage> createState() => _ControlePageState();
}

class _ControlePageState extends State<ControlePage> {
  static const String _baseUrl = 'http://192.168.4.1';

  // Controle
  double _distancia = 2.0;
  bool _armado = false;
  bool _carregando = false;
  String _mensagem = 'Pronto para armar.';

  // Navegação
  int _selectedIndex = 0;

  // Configurações avançadas
  int _passosGatilho = 512;
  int _anguloMin     = 45;
  int _anguloMax     = 180;
  bool _carregandoConfig = false;
  String _mensagemConfig = '';
  bool _configSucesso = false;

  late final TextEditingController _ctrlGatilho;
  late final TextEditingController _ctrlAnguloMin;
  late final TextEditingController _ctrlAnguloMax;

  @override
  void initState() {
    super.initState();
    _ctrlGatilho   = TextEditingController(text: '$_passosGatilho');
    _ctrlAnguloMin = TextEditingController(text: '$_anguloMin');
    _ctrlAnguloMax = TextEditingController(text: '$_anguloMax');
  }

  @override
  void dispose() {
    _ctrlGatilho.dispose();
    _ctrlAnguloMin.dispose();
    _ctrlAnguloMax.dispose();
    super.dispose();
  }

  Future<void> _armar() async {
    setState(() {
      _carregando = true;
      _mensagem = 'Armando para ${_distancia.toStringAsFixed(1)} m...';
    });
    try {
      final uri = Uri.parse(
          '$_baseUrl/armar?distancia=${_distancia.toStringAsFixed(1)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      setState(() {
        if (resp.statusCode == 200) {
          _armado = true;
          _mensagem = resp.body;
        } else {
          _mensagem = 'Erro: ${resp.body}';
        }
      });
    } catch (_) {
      setState(() => _mensagem = 'Sem conexão. Conecte ao WiFi "Catapulta_IME".');
    } finally {
      setState(() => _carregando = false);
    }
  }

  Future<void> _lancar() async {
    setState(() {
      _carregando = true;
      _mensagem = 'Lançando...';
    });
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/fogo'))
          .timeout(const Duration(seconds: 15));
      setState(() {
        _armado = false;
        _mensagem = resp.statusCode == 200
            ? 'Lançado! Recarregue e pressione ARMAR.'
            : 'Erro: ${resp.body}';
      });
    } catch (_) {
      setState(() => _mensagem = 'Sem conexão. Conecte ao WiFi "Catapulta_IME".');
    } finally {
      setState(() => _carregando = false);
    }
  }

  Future<void> _desarmar() async {
    setState(() {
      _carregando = true;
      _mensagem = 'Desarmando...';
    });
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/desarmar'))
          .timeout(const Duration(seconds: 15));
      setState(() {
        _armado = false;
        _mensagem = resp.statusCode == 200 ? 'Desarmado.' : resp.body;
      });
    } catch (_) {
      setState(() => _mensagem = 'Sem conexão. Conecte ao WiFi "Catapulta_IME".');
    } finally {
      setState(() => _carregando = false);
    }
  }

  Future<void> _configurar() async {
    final gatilho = int.tryParse(_ctrlGatilho.text.trim());
    final angMin  = int.tryParse(_ctrlAnguloMin.text.trim());
    final angMax  = int.tryParse(_ctrlAnguloMax.text.trim());

    if (gatilho == null || gatilho <= 0 ||
        angMin == null || angMin < 0 || angMin > 180 ||
        angMax == null || angMax < 0 || angMax > 180) {
      setState(() {
        _mensagemConfig = 'Valores inválidos. Ângulos: 0–180. Gatilho: positivo.';
        _configSucesso = false;
      });
      return;
    }
    if (angMin >= angMax) {
      setState(() {
        _mensagemConfig = 'Ângulo mín deve ser menor que ângulo máx.';
        _configSucesso = false;
      });
      return;
    }

    setState(() {
      _carregandoConfig = true;
      _mensagemConfig = 'Enviando configuração...';
      _configSucesso = false;
    });
    try {
      final uri = Uri.parse(
        '$_baseUrl/configurar'
        '?angulo_min=$angMin&angulo_max=$angMax&passos_gatilho=$gatilho',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      setState(() {
        if (resp.statusCode == 200) {
          _passosGatilho = gatilho;
          _anguloMin     = angMin;
          _anguloMax     = angMax;
          _mensagemConfig = 'Configuração aplicada com sucesso.';
          _configSucesso = true;
        } else {
          _mensagemConfig = 'Erro: ${resp.body}';
          _configSucesso = false;
        }
      });
    } catch (_) {
      setState(() {
        _mensagemConfig = 'Sem conexão. Conecte ao WiFi "Catapulta_IME".';
        _configSucesso = false;
      });
    } finally {
      setState(() => _carregandoConfig = false);
    }
  }

  Widget _buildControle(ColorScheme cs) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),

            // Título
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.sports_baseball, color: cs.primary, size: 32),
                const SizedBox(width: 12),
                Text(
                  'Catapulta IME',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _armado
                    ? Colors.green.withAlpha(50)
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _armado ? Colors.green : cs.outline,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _armado ? Icons.lock : Icons.lock_open,
                    color: _armado ? Colors.green : cs.onSurface,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _mensagem,
                      style: TextStyle(
                        color: _armado ? Colors.green : cs.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (_carregando)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 36),

            // Label distância
            Text(
              'Distância do alvo',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: cs.onSurface),
            ),
            const SizedBox(height: 4),

            // Slider — 0,5 m a 4,0 m, 35 divisões de 0,1 m
            Row(
              children: [
                Text('0,5 m',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: _distancia,
                    min: 0.5,
                    max: 4.0,
                    divisions: 35,
                    label: '${_distancia.toStringAsFixed(1)} m',
                    onChanged: _armado || _carregando
                        ? null
                        : (v) => setState(() => _distancia = v),
                  ),
                ),
                Text('4,0 m',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ],
            ),

            // Valor central
            Center(
              child: Text(
                '${_distancia.toStringAsFixed(1)} m',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
              ),
            ),
            const SizedBox(height: 36),

            // Botão ARMAR
            FilledButton.icon(
              onPressed: _armado || _carregando ? null : _armar,
              icon: const Icon(Icons.compress),
              label: const Text('ARMAR',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                backgroundColor: Colors.orange,
                foregroundColor: Colors.black,
                disabledBackgroundColor: Colors.orange.withAlpha(80),
              ),
            ),
            const SizedBox(height: 14),

            // Botão LANÇAR
            FilledButton.icon(
              onPressed: !_armado || _carregando ? null : _lancar,
              icon: const Icon(Icons.rocket_launch),
              label: const Text('LANÇAR',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.red.withAlpha(80),
              ),
            ),
            const SizedBox(height: 10),

            // Botão Desarmar
            OutlinedButton.icon(
              onPressed: _carregando ? null : _desarmar,
              icon: const Icon(Icons.lock_open, size: 18),
              label: const Text('Desarmar (soltar tensão)'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 24),

            Center(
              child: Text(
                'Conecte ao WiFi "Catapulta_IME" antes de usar',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildConfiguracoes(ColorScheme cs) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),

            // Título
            Row(
              children: [
                Icon(Icons.tune, color: cs.primary, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Configurações Avançadas',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Ajuste os passos do gatilho conforme os testes mecânicos. '
              'A calibração balística (ângulos mín/máx do servo) é feita '
              'diretamente no firmware. Configurações valem até o ESP32 ser reiniciado.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 28),

            // Card — Servo Tração
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.rotate_right, color: cs.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Servo Tração (MG996R)',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Mapeamento linear: distância → ângulo do servo.',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _ctrlAnguloMin,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Ângulo mínimo  (distância 0,5 m)',
                        helperText: 'Padrão: 45°',
                        border: OutlineInputBorder(),
                        suffixText: '°',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _ctrlAnguloMax,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Ângulo máximo  (distância 4,0 m)',
                        helperText: 'Padrão: 180°',
                        border: OutlineInputBorder(),
                        suffixText: '°',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Card — Motor Gatilho
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.rocket_launch, color: cs.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Motor Gatilho',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Passos para abrir e fechar o mecanismo de disparo.',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _ctrlGatilho,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Passos do gatilho',
                        helperText: 'Padrão: 512  (1/4 de volta)',
                        border: OutlineInputBorder(),
                        suffixText: 'passos',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Botão Aplicar
            FilledButton.icon(
              onPressed: _carregandoConfig ? null : _configurar,
              icon: _carregandoConfig
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              label: const Text('Aplicar Configurações',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),

            if (_mensagemConfig.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _configSucesso
                      ? Colors.green.withAlpha(40)
                      : cs.errorContainer.withAlpha(80),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _configSucesso ? Colors.green : cs.error,
                  ),
                ),
                child: Text(
                  _mensagemConfig,
                  style: TextStyle(
                    color: _configSucesso ? Colors.green : cs.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Valores ativos
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Valores enviados ao ESP32 nesta sessão:',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                  const SizedBox(height: 6),
                  Text(
                    'Servo: $_anguloMin° – $_anguloMax°  |  Gatilho: $_passosGatilho passos',
                    style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w500,
                        fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            _buildControle(cs),
            _buildConfiguracoes(cs),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.sports_baseball_outlined),
            selectedIcon: Icon(Icons.sports_baseball),
            label: 'Controle',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Configurações',
          ),
        ],
      ),
    );
  }
}
