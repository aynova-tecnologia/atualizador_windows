import 'dart:async';

import 'package:flutter/material.dart';

import 'atualizador_windows.dart';
import 'manifesto.dart';

enum _Fase { liberado, oferecendo, baixando, reiniciando, falhou }

class AtualizacaoWindowsHost extends StatefulWidget {
  final Widget? child;
  final AtualizadorWindows? atualizador;
  final Duration intervaloDeConsulta;

  const AtualizacaoWindowsHost({
    required this.child,
    this.atualizador,
    this.intervaloDeConsulta = const Duration(minutes: 30),
    super.key,
  });

  @override
  State<AtualizacaoWindowsHost> createState() => _AtualizacaoWindowsHostState();
}

class _AtualizacaoWindowsHostState extends State<AtualizacaoWindowsHost> {
  late final AtualizadorWindows _atualizador =
      widget.atualizador ?? AtualizadorWindows.doBuild();
  AppLifecycleListener? _ciclo;
  Timer? _relogio;
  bool _consultando = false;
  _Fase _fase = _Fase.liberado;
  Manifesto? _versaoNova;
  int? _adiadaAteBuild;
  double _progresso = 0;
  String? _erro;

  bool get _obrigatoria => _versaoNova?.obrigatoria ?? true;

  bool get _bloqueia =>
      _fase == _Fase.baixando ||
      _fase == _Fase.reiniciando ||
      (_fase == _Fase.falhou && _obrigatoria);

  @override
  void initState() {
    super.initState();
    if (!_atualizador.ativo) return;
    _ciclo = AppLifecycleListener(onResume: _consultar);
    _relogio = Timer.periodic(widget.intervaloDeConsulta, (_) => _consultar());
    WidgetsBinding.instance.addPostFrameCallback((_) => _consultar());
  }

  @override
  void dispose() {
    _ciclo?.dispose();
    _relogio?.cancel();
    super.dispose();
  }

  Future<void> _consultar() async {
    if (_consultando || _fase == _Fase.baixando || _fase == _Fase.reiniciando) {
      return;
    }
    _consultando = true;
    final manifesto = await _atualizador.versaoNova();
    _consultando = false;
    if (!mounted || manifesto == null) return;
    _versaoNova = manifesto;
    if (_atualizador.jaFalhouCom(manifesto)) {
      setState(() {
        _fase = _Fase.falhou;
        _erro =
            _atualizador.ultimaFalha() ??
            'A última tentativa de instalar esta versão falhou.';
      });
      return;
    }
    if (manifesto.obrigatoria) {
      unawaited(_instalar());
      return;
    }
    final adiada = _adiadaAteBuild;
    if (adiada != null && manifesto.build <= adiada) return;
    setState(() => _fase = _Fase.oferecendo);
  }

  Future<void> _instalar() async {
    final manifesto = _versaoNova!;
    setState(() {
      _fase = _Fase.baixando;
      _progresso = 0;
      _erro = null;
    });
    try {
      _atualizador.esquecerFalha();
      final zip = await _atualizador.baixar(
        manifesto,
        progresso: (fracao) {
          if (mounted) setState(() => _progresso = fracao);
        },
      );
      if (!mounted) return;
      setState(() => _fase = _Fase.reiniciando);
      await _atualizador.trocarEReiniciar(manifesto, zip);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fase = _Fase.falhou;
        _erro = '$e';
      });
    }
  }

  void _adiar() => setState(() {
    _adiadaAteBuild = _versaoNova?.build;
    _fase = _Fase.liberado;
  });

  @override
  Widget build(BuildContext context) {
    final mostraAviso =
        !_obrigatoria &&
        (_fase == _Fase.oferecendo || _fase == _Fase.falhou);
    return Stack(
      children: [
        Positioned.fill(
          child: Offstage(
            offstage: _bloqueia,
            child: widget.child ?? const SizedBox.shrink(),
          ),
        ),
        if (_bloqueia)
          Positioned.fill(
            child: _TelaDeAtualizacao(
              versao: _versaoNova!.rotulo,
              fase: _fase,
              progresso: _progresso,
              erro: _erro,
              aoTentarDeNovo: _instalar,
            ),
          ),
        if (mostraAviso)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _AvisoDeVersaoNova(
              versao: _versaoNova!.rotulo,
              erro: _fase == _Fase.falhou ? _erro : null,
              aoAtualizar: _instalar,
              aoAdiar: _adiar,
            ),
          ),
      ],
    );
  }
}

class _TelaDeAtualizacao extends StatelessWidget {
  final String versao;
  final _Fase fase;
  final double progresso;
  final String? erro;
  final VoidCallback aoTentarDeNovo;

  const _TelaDeAtualizacao({
    required this.versao,
    required this.fase,
    required this.progresso,
    required this.erro,
    required this.aoTentarDeNovo,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final falhou = fase == _Fase.falhou;
    return Material(
      color: tema.colorScheme.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  falhou ? Icons.error_outline : Icons.system_update_alt,
                  size: 48,
                  color: falhou
                      ? tema.colorScheme.error
                      : tema.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  falhou
                      ? 'Não foi possível atualizar'
                      : 'Atualização obrigatória',
                  style: tema.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  falhou
                      ? erro ?? 'Erro desconhecido.'
                      : 'A versão $versao está disponível. O app vai reiniciar sozinho.',
                  style: tema.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (falhou)
                  FilledButton.icon(
                    onPressed: aoTentarDeNovo,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar de novo'),
                  )
                else ...[
                  LinearProgressIndicator(
                    value: fase == _Fase.baixando ? progresso : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    fase == _Fase.baixando
                        ? 'Baixando… ${(progresso * 100).round()}%'
                        : 'Reiniciando…',
                    style: tema.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvisoDeVersaoNova extends StatelessWidget {
  final String versao;
  final String? erro;
  final VoidCallback aoAtualizar;
  final VoidCallback aoAdiar;

  const _AvisoDeVersaoNova({
    required this.versao,
    required this.erro,
    required this.aoAtualizar,
    required this.aoAdiar,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: tema.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(
              erro == null ? Icons.system_update_alt : Icons.error_outline,
              color: erro == null
                  ? tema.colorScheme.primary
                  : tema.colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                erro == null
                    ? 'Versão $versao disponível.'
                    : 'Não foi possível atualizar: $erro',
                style: tema.textTheme.bodyMedium,
              ),
            ),
            TextButton(onPressed: aoAdiar, child: const Text('Depois')),
            FilledButton(
              onPressed: aoAtualizar,
              child: Text(erro == null ? 'Atualizar agora' : 'Tentar de novo'),
            ),
          ],
        ),
      ),
    );
  }
}
