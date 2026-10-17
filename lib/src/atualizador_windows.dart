import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'configuracao_atualizacao.dart';
import 'manifesto.dart';

class FalhaAoAtualizar implements Exception {
  final String mensagem;

  const FalhaAoAtualizar(this.mensagem);

  @override
  String toString() => mensagem;
}

typedef AoReiniciar = void Function();

class AtualizadorWindows {
  final ConfiguracaoAtualizacao configuracao;
  final Duration tempoLimiteDaRede;
  final AoReiniciar aoReiniciar;

  AtualizadorWindows({
    required this.configuracao,
    this.tempoLimiteDaRede = const Duration(seconds: 10),
    AoReiniciar? aoReiniciar,
  }) : aoReiniciar = aoReiniciar ?? (() => exit(0));

  factory AtualizadorWindows.doBuild() =>
      AtualizadorWindows(configuracao: ConfiguracaoAtualizacao.doBuild());

  bool get ativo => configuracao.ativa;

  Future<Manifesto?> versaoNova() async {
    if (!ativo) return null;
    try {
      final arquivo = File(
        p.join(configuracao.pastaPublicacao, 'versao.json'),
      );
      final texto = await arquivo.readAsString().timeout(tempoLimiteDaRede);
      final manifesto = Manifesto.fromJson(
        jsonDecode(texto) as Map<String, dynamic>,
      );
      return manifesto.build > configuracao.buildAtual ? manifesto : null;
    } catch (e) {
      debugPrint('Consulta de versao do Windows falhou: $e');
      return null;
    }
  }

  bool jaFalhouCom(Manifesto manifesto) {
    final registro = configuracao.instalacao!.registroDeFalha;
    if (!registro.existsSync()) return false;
    try {
      final json = jsonDecode(registro.readAsStringSync()) as Map;
      return json['build'] == manifesto.build;
    } catch (_) {
      return false;
    }
  }

  String? ultimaFalha() {
    final registro = configuracao.instalacao!.registroDeFalha;
    if (!registro.existsSync()) return null;
    try {
      final json = jsonDecode(registro.readAsStringSync()) as Map;
      return json['erro'] as String?;
    } catch (_) {
      return null;
    }
  }

  bool scriptNaoRodouPara(Manifesto manifesto) {
    final instalacao = configuracao.instalacao!;
    if (!instalacao.registroPendente.existsSync()) return false;
    if (instalacao.registroDeFalha.existsSync()) return false;
    try {
      final json =
          jsonDecode(instalacao.registroPendente.readAsStringSync()) as Map;
      return json['build'] == manifesto.build;
    } catch (_) {
      return false;
    }
  }

  void esquecerFalha() {
    final instalacao = configuracao.instalacao!;
    for (final registro in [
      instalacao.registroDeFalha,
      instalacao.registroPendente,
    ]) {
      if (registro.existsSync()) registro.deleteSync();
    }
  }

  void registrar(String mensagem) {
    try {
      configuracao.instalacao!.log.writeAsStringSync(
        '${DateTime.now().toIso8601String()} app: $mensagem\r\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  Future<File> baixar(
    Manifesto manifesto, {
    void Function(double fracao)? progresso,
  }) async {
    final instalacao = configuracao.instalacao!;
    final origem = File(p.join(configuracao.pastaPublicacao, manifesto.zip));
    final destino = File(p.join(instalacao.download.path, manifesto.zip));
    try {
      await instalacao.download.create(recursive: true);
      final total = await origem.length();
      var copiado = 0;
      final saida = destino.openWrite();
      await for (final pedaco in origem.openRead()) {
        saida.add(pedaco);
        copiado += pedaco.length;
        progresso?.call(total == 0 ? 1 : copiado / total);
      }
      await saida.close();
    } on FileSystemException catch (e) {
      throw FalhaAoAtualizar(
          'Não foi possível copiar a versão nova: ${e.message}');
    }
    final hash = (await sha256.bind(destino.openRead()).first).toString();
    if (hash != manifesto.sha256) {
      await destino.delete();
      throw const FalhaAoAtualizar(
        'O arquivo da versão nova chegou corrompido (hash diferente do publicado).',
      );
    }
    return destino;
  }

  Future<void> trocarEReiniciar(Manifesto manifesto, File zip) async {
    final instalacao = configuracao.instalacao!;
    final embutido = instalacao.scriptEmbutido();
    if (!embutido.existsSync()) {
      throw const FalhaAoAtualizar('O script de atualização não veio no app.');
    }
    await embutido.copy(instalacao.script.path);
    instalacao.registroPendente.writeAsStringSync(
      jsonEncode({
        'build': manifesto.build,
        'em': DateTime.now().toIso8601String(),
      }),
    );
    registrar('disparando o atualizador para o build ${manifesto.build}');
    try {
      await Process.start(
        'cmd.exe',
        [
          '/c',
          'start',
          '',
          '/min',
          'powershell.exe',
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-WindowStyle',
          'Hidden',
          '-File',
          instalacao.script.path,
          '-ProcessoId',
          '$pid',
          '-Build',
          '${manifesto.build}',
          '-Zip',
          zip.path,
          '-Instalacao',
          instalacao.raiz.path,
          '-Exe',
          instalacao.exe,
        ],
        workingDirectory: instalacao.raiz.path,
        mode: ProcessStartMode.detached,
      );
    } on ProcessException catch (e) {
      instalacao.registroPendente.deleteSync();
      registrar('o Windows recusou iniciar o atualizador: ${e.message}');
      throw FalhaAoAtualizar(
        'O Windows não deixou iniciar o atualizador: ${e.message}',
      );
    }
    aoReiniciar();
  }
}
