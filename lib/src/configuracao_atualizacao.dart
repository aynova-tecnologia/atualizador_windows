import 'dart:io';

import 'package:flutter/foundation.dart';

import 'instalacao.dart';

class ConfiguracaoAtualizacao {
  final int buildAtual;
  final String pastaPublicacao;
  final Instalacao? instalacao;

  const ConfiguracaoAtualizacao({
    required this.buildAtual,
    required this.pastaPublicacao,
    required this.instalacao,
  });

  factory ConfiguracaoAtualizacao.doBuild() => ConfiguracaoAtualizacao(
        buildAtual: const int.fromEnvironment('APP_BUILD'),
        pastaPublicacao: const String.fromEnvironment('PASTA_ATUALIZACAO'),
        instalacao: !kIsWeb && Platform.isWindows
            ? Instalacao.doExecutavel(Platform.resolvedExecutable)
            : null,
      );

  bool get ativa =>
      buildAtual > 0 && pastaPublicacao.isNotEmpty && instalacao != null;
}
