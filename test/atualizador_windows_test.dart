import 'dart:convert';
import 'dart:io';

import 'package:atualizador_windows/atualizador_windows.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late Directory publicacao;
  late Instalacao instalacao;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('atualizador_');
    publicacao = Directory(p.join(temp.path, 'rede'))..createSync();
    final raiz = Directory(p.join(temp.path, 'Timber Pine Teste'))
      ..createSync();
    Directory(p.join(raiz.path, 'app')).createSync();
    File(p.join(raiz.path, Instalacao.marcador)).createSync();
    instalacao = Instalacao(raiz: raiz, exe: 'agro_pine_cliente.exe');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Map<String, dynamic> manifestoJson({int build = 5, String? sha}) => {
        'nome': 'Timber Pine Teste',
        'versao': '1.0.0',
        'build': build,
        'exe': 'agro_pine_cliente.exe',
        'zip': 'timber_pine-1.0.0+$build.zip',
        'sha256': sha ?? 'ABC',
        'obrigatoria': true,
      };

  void publicar(Map<String, dynamic> json) => File(
        p.join(publicacao.path, 'versao.json'),
      ).writeAsStringSync(jsonEncode(json));

  AtualizadorWindows atualizador({int buildAtual = 4}) => AtualizadorWindows(
        configuracao: ConfiguracaoAtualizacao(
          buildAtual: buildAtual,
          pastaPublicacao: publicacao.path,
          instalacao: instalacao,
        ),
      );

  group('Manifesto', () {
    test('le o versao.json e normaliza o hash para minusculas', () {
      final manifesto = Manifesto.fromJson(manifestoJson());
      expect(manifesto.build, 5);
      expect(manifesto.sha256, 'abc');
      expect(manifesto.rotulo, '1.0.0+5');
    });

    test('sem o campo obrigatoria, a atualizacao e obrigatoria', () {
      final json = manifestoJson()..remove('obrigatoria');
      expect(Manifesto.fromJson(json).obrigatoria, isTrue);
    });
  });

  group('Instalacao.doExecutavel', () {
    test('reconhece o exe dentro de app\\ com o marcador na raiz', () {
      final exe = p.join(instalacao.app.path, 'agro_pine_cliente.exe');
      final achada = Instalacao.doExecutavel(exe);
      expect(achada?.raiz.path, instalacao.raiz.path);
      expect(achada?.exe, 'agro_pine_cliente.exe');
    });

    test('sem o marcador nao e uma instalacao gerenciada', () {
      File(p.join(instalacao.raiz.path, Instalacao.marcador)).deleteSync();
      final exe = p.join(instalacao.app.path, 'agro_pine_cliente.exe');
      expect(Instalacao.doExecutavel(exe), isNull);
    });

    test('exe fora de uma pasta app nao e uma instalacao gerenciada', () {
      expect(Instalacao.doExecutavel(p.join(temp.path, 'x.exe')), isNull);
    });
  });

  group('versaoNova', () {
    test('devolve o manifesto quando o build publicado e maior', () async {
      publicar(manifestoJson(build: 5));
      expect((await atualizador(buildAtual: 4).versaoNova())?.build, 5);
    });

    test('nada quando o build publicado e igual ou menor', () async {
      publicar(manifestoJson(build: 4));
      expect(await atualizador(buildAtual: 4).versaoNova(), isNull);
    });

    test('pasta sem versao.json libera o app', () async {
      expect(await atualizador().versaoNova(), isNull);
    });

    test('versao.json ilegivel libera o app', () async {
      File(p.join(publicacao.path, 'versao.json')).writeAsStringSync('{');
      expect(await atualizador().versaoNova(), isNull);
    });

    test('build sem APP_BUILD nunca consulta', () async {
      publicar(manifestoJson(build: 5));
      expect(await atualizador(buildAtual: 0).versaoNova(), isNull);
    });
  });

  group('baixar', () {
    test('copia o zip, informa o progresso e confere o hash', () async {
      final bytes = List<int>.generate(200000, (i) => i % 251);
      File(p.join(publicacao.path, 'timber_pine-1.0.0+5.zip'))
          .writeAsBytesSync(bytes);
      final manifesto = Manifesto.fromJson(
        manifestoJson(sha: sha256.convert(bytes).toString()),
      );
      final fracoes = <double>[];

      final zip = await atualizador().baixar(manifesto, progresso: fracoes.add);

      expect(zip.readAsBytesSync(), bytes);
      expect(p.isWithin(instalacao.download.path, zip.path), isTrue);
      expect(fracoes.last, 1);
    });

    test('hash diferente falha e apaga o arquivo baixado', () async {
      File(p.join(publicacao.path, 'timber_pine-1.0.0+5.zip'))
          .writeAsBytesSync([1, 2, 3]);
      final manifesto = Manifesto.fromJson(manifestoJson(sha: 'errado'));

      await expectLater(
        atualizador().baixar(manifesto),
        throwsA(isA<FalhaAoAtualizar>()),
      );
      expect(
        File(p.join(instalacao.download.path, manifesto.zip)).existsSync(),
        isFalse,
      );
    });

    test('zip ausente na rede vira FalhaAoAtualizar', () async {
      final manifesto = Manifesto.fromJson(manifestoJson());
      await expectLater(
        atualizador().baixar(manifesto),
        throwsA(isA<FalhaAoAtualizar>()),
      );
    });
  });

  group('registro de falha do script', () {
    test('vale so para o build que falhou e pode ser esquecido', () {
      instalacao.registroDeFalha.writeAsStringSync(
        jsonEncode({'build': 5, 'erro': 'o app nao fechou'}),
      );
      final alvo = atualizador();

      expect(alvo.jaFalhouCom(Manifesto.fromJson(manifestoJson(build: 5))),
          isTrue);
      expect(alvo.jaFalhouCom(Manifesto.fromJson(manifestoJson(build: 6))),
          isFalse);
      expect(alvo.ultimaFalha(), 'o app nao fechou');

      alvo.esquecerFalha();
      expect(instalacao.registroDeFalha.existsSync(), isFalse);
    });
  });

  group('pendente.json', () {
    test('marca o script que nao rodou so para o mesmo build e sem falha.json',
        () {
      instalacao.registroPendente.writeAsStringSync(jsonEncode({'build': 5}));
      final alvo = atualizador();
      final build5 = Manifesto.fromJson(manifestoJson(build: 5));

      expect(alvo.scriptNaoRodouPara(build5), isTrue);
      expect(
          alvo.scriptNaoRodouPara(Manifesto.fromJson(manifestoJson(build: 6))),
          isFalse);

      instalacao.registroDeFalha
          .writeAsStringSync(jsonEncode({'build': 5, 'erro': 'x'}));
      expect(alvo.scriptNaoRodouPara(build5), isFalse);

      alvo.esquecerFalha();
      expect(instalacao.registroPendente.existsSync(), isFalse);
      expect(instalacao.registroDeFalha.existsSync(), isFalse);
    });

    test('sem o script dentro do app, nao marca pendente nem fecha', () async {
      var fechou = false;
      final alvo = AtualizadorWindows(
        configuracao: ConfiguracaoAtualizacao(
          buildAtual: 4,
          pastaPublicacao: publicacao.path,
          instalacao: instalacao,
        ),
        aoReiniciar: () => fechou = true,
      );

      await expectLater(
        alvo.trocarEReiniciar(
          Manifesto.fromJson(manifestoJson()),
          File(p.join(temp.path, 'x.zip')),
        ),
        throwsA(isA<FalhaAoAtualizar>()),
      );
      expect(instalacao.registroPendente.existsSync(), isFalse);
      expect(fechou, isFalse);
    });
  });

  group('pasta de dados', () {
    test('producao usa o nome do app; o resto ganha o sufixo Teste', () {
      expect(
          nomeDaPastaDeDados('Timber Pine', ambiente: 'prod'), 'Timber Pine');
      expect(nomeDaPastaDeDados('Timber Pine', ambiente: 'dev'),
          'Timber Pine Teste');
    });

    test('fica em APPDATA\\Agrosepac e e criada se nao existir', () async {
      final pasta = await pastaDeDadosDoApp(
        'Timber Pine',
        ambiente: 'prod',
        appData: temp.path,
      );
      expect(pasta.path, p.join(temp.path, 'Agrosepac', 'Timber Pine'));
      expect(pasta.existsSync(), isTrue);
    });
  });
}
