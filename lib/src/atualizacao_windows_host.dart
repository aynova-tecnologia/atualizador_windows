import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'atualizador_windows.dart';
import 'manifesto.dart';

enum _Fase { liberado, oferecendo, baixando, pronto, reiniciando, falhou }

const kMensagemScriptNaoRodou =
    'O app fechou para atualizar, mas o atualizador não chegou a rodar. '
    'Ele pode ter sido bloqueado pelo antivírus ou por uma política do Windows. '
    'Avise a TI.';

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
  File? _zipBaixado;
  int? _adiadaAteBuild;
  double _progresso = 0;
  String? _erro;

  bool get _obrigatoria => _versaoNova?.obrigatoria ?? true;

  bool get _ocupado =>
      _fase == _Fase.baixando ||
      _fase == _Fase.pronto ||
      _fase == _Fase.reiniciando;

  bool get _bloqueia => _ocupado || (_obrigatoria && _fase != _Fase.liberado);

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
    if (_consultando || _ocupado) return;
    _consultando = true;
    final manifesto = await _atualizador.versaoNova();
    _consultando = false;
    if (!mounted || manifesto == null) return;
    _versaoNova = manifesto;
    if (_atualizador.jaFalhouCom(manifesto)) {
      _falhar(
        _atualizador.ultimaFalha() ??
            'A última tentativa de instalar esta versão falhou.',
      );
      return;
    }
    if (_atualizador.scriptNaoRodouPara(manifesto)) {
      _falhar(kMensagemScriptNaoRodou);
      return;
    }
    final adiada = _adiadaAteBuild;
    if (!manifesto.obrigatoria && adiada != null && manifesto.build <= adiada) {
      return;
    }
    setState(() => _fase = _Fase.oferecendo);
  }

  void _falhar(String erro) => setState(() {
        _fase = _Fase.falhou;
        _erro = erro;
      });

  Future<void> _baixar() async {
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
      setState(() {
        _zipBaixado = zip;
        _fase = _Fase.pronto;
      });
    } catch (e) {
      if (mounted) _falhar('$e');
    }
  }

  Future<void> _reiniciar() async {
    setState(() => _fase = _Fase.reiniciando);
    try {
      await _atualizador.trocarEReiniciar(_versaoNova!, _zipBaixado!);
    } catch (e) {
      if (mounted) _falhar('$e');
    }
  }

  void _adiar() => setState(() {
        _adiadaAteBuild = _versaoNova?.build;
        _fase = _Fase.liberado;
      });

  @override
  Widget build(BuildContext context) {
    final mostraAviso =
        !_bloqueia && (_fase == _Fase.oferecendo || _fase == _Fase.falhou);
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
              obrigatoria: _obrigatoria,
              fase: _fase,
              progresso: _progresso,
              erro: _erro,
              aoAtualizar: _baixar,
              aoReiniciar: _reiniciar,
              aoAdiar: _obrigatoria ? null : _adiar,
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
              aoAtualizar: _baixar,
              aoAdiar: _adiar,
            ),
          ),
      ],
    );
  }
}

class _TelaDeAtualizacao extends StatelessWidget {
  final String versao;
  final bool obrigatoria;
  final _Fase fase;
  final double progresso;
  final String? erro;
  final VoidCallback aoAtualizar;
  final VoidCallback aoReiniciar;
  final VoidCallback? aoAdiar;

  const _TelaDeAtualizacao({
    required this.versao,
    required this.obrigatoria,
    required this.fase,
    required this.progresso,
    required this.erro,
    required this.aoAtualizar,
    required this.aoReiniciar,
    required this.aoAdiar,
  });

  String get _titulo => switch (fase) {
        _Fase.falhou => 'Não foi possível atualizar',
        _Fase.pronto => 'Atualização pronta',
        _ => obrigatoria ? 'Atualização obrigatória' : 'Nova versão disponível',
      };

  String get _texto => switch (fase) {
        _Fase.falhou => erro ?? 'Erro desconhecido.',
        _Fase.pronto =>
          'Clique em Reiniciar agora. O app vai fechar e abrir de novo já na versão $versao.',
        _Fase.reiniciando => 'Fechando o app para instalar a versão $versao…',
        _ => obrigatoria
            ? 'A versão $versao está disponível. Atualize para continuar usando o app.'
            : 'A versão $versao está disponível.',
      };

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final falhou = fase == _Fase.falhou;
    return Material(
      color: tema.colorScheme.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
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
                  _titulo,
                  style: tema.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _texto,
                  style: tema.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ..._acoes(tema),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _acoes(ThemeData tema) => switch (fase) {
        _Fase.baixando => [
            LinearProgressIndicator(value: progresso),
            const SizedBox(height: 8),
            Text(
              'Baixando… ${(progresso * 100).round()}%',
              style: tema.textTheme.bodySmall,
            ),
          ],
        _Fase.reiniciando => [const LinearProgressIndicator()],
        _Fase.pronto => [
            _Botoes(
              principal: FilledButton.icon(
                onPressed: aoReiniciar,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reiniciar agora'),
              ),
              aoAdiar: aoAdiar,
            ),
          ],
        _Fase.falhou => [
            _Botoes(
              principal: FilledButton.icon(
                onPressed: aoAtualizar,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar de novo'),
              ),
              aoAdiar: aoAdiar,
            ),
          ],
        _ => [
            _Botoes(
              principal: FilledButton.icon(
                onPressed: aoAtualizar,
                icon: const Icon(Icons.download),
                label: const Text('Atualizar'),
              ),
              aoAdiar: aoAdiar,
            ),
          ],
      };
}

class _Botoes extends StatelessWidget {
  final Widget principal;
  final VoidCallback? aoAdiar;

  const _Botoes({required this.principal, required this.aoAdiar});

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          if (aoAdiar != null)
            TextButton(onPressed: aoAdiar, child: const Text('Depois')),
          principal,
        ],
      );
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
