import 'package:flutter/material.dart';
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

  double _distancia = 2.0;
  bool _armado = false;
  bool _carregando = false;
  String _mensagem = 'Pronto para armar.';

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
        _mensagem = resp.statusCode == 200 ? 'Lançado com sucesso!' : 'Erro: ${resp.body}';
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
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

              // Slider
              Row(
                children: [
                  Text('0,5 m', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
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
                  Text('4,0 m', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
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
                label: const Text('ARMAR', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                label: const Text('LANÇAR', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                onPressed: !_armado || _carregando ? null : _desarmar,
                icon: const Icon(Icons.lock_open, size: 18),
                label: const Text('Desarmar (soltar tensão)'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),

              const Spacer(),

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
      ),
    );
  }
}
