import 'dart:io';

import 'package:atualizador_windows/atualizador_windows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _AtualizadorFalso extends AtualizadorWindows {
  Manifesto? publicado;
  bool falhouAntes = false;
  bool scriptNaoRodou = false;
  int falhasAoBaixar = 0;
  int downloads = 0;
  Manifesto? reiniciouCom;

  _AtualizadorFalso()
      : super(
          configuracao: const ConfiguracaoAtualizacao(
            buildAtual: 4,
            pastaPublicacao: 'rede',
            instalacao: null,
          ),
        );

  @override
  bool get ativo => true;

  @override
  Future<Manifesto?> versaoNova() async => publicado;

  @override
  bool jaFalhouCom(Manifesto manifesto) => falhouAntes;

  @override
  bool scriptNaoRodouPara(Manifesto manifesto) => scriptNaoRodou;

  @override
  String? ultimaFalha() => 'o app nao fechou em 60 segundos';

  @override
  void esquecerFalha() => falhouAntes = false;

  @override
  Future<File> baixar(
    Manifesto manifesto, {
    void Function(double fracao)? progresso,
  }) async {
    downloads++;
    if (falhasAoBaixar > 0) {
      falhasAoBaixar--;
      throw const FalhaAoAtualizar('Não foi possível copiar a versão nova.');
    }
    progresso?.call(1);
    return File('zip');
  }

  @override
  Future<void> trocarEReiniciar(Manifesto manifesto, File zip) async {
    reiniciouCom = manifesto;
  }
}

Manifesto _manifesto({required bool obrigatoria}) => Manifesto(
      nome: 'Timber Pine Teste',
      versao: '1.0.0',
      build: 5,
      exe: 'agro_pine_cliente.exe',
      zip: 'timber_pine-1.0.0+5.zip',
      sha256: 'abc',
      obrigatoria: obrigatoria,
    );

void main() {
  late _AtualizadorFalso atualizador;

  setUp(() => atualizador = _AtualizadorFalso());

  Future<void> montar(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AtualizacaoWindowsHost(
          atualizador: atualizador,
          child: const Text('conteudo'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> desmontar(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  testWidgets('sem versao nova, o app aparece normalmente', (tester) async {
    await montar(tester);

    expect(find.text('conteudo'), findsOneWidget);
    expect(find.text('Atualização obrigatória'), findsNothing);
    await desmontar(tester);
  });

  Future<void> tocar(WidgetTester tester, String texto) async {
    await tester.tap(find.text(texto));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('versao obrigatoria esconde o app e espera o clique em Atualizar',
      (
    tester,
  ) async {
    atualizador.publicado = _manifesto(obrigatoria: true);

    await montar(tester);

    expect(find.text('conteudo'), findsNothing);
    expect(find.text('Atualização obrigatória'), findsOneWidget);
    expect(find.text('Depois'), findsNothing);
    expect(atualizador.downloads, 0);
    await desmontar(tester);
  });

  testWidgets(
      'Atualizar baixa e so reinicia depois do clique em Reiniciar agora', (
    tester,
  ) async {
    atualizador.publicado = _manifesto(obrigatoria: true);
    await montar(tester);

    await tocar(tester, 'Atualizar');

    expect(atualizador.downloads, 1);
    expect(find.text('Atualização pronta'), findsOneWidget);
    expect(atualizador.reiniciouCom, isNull);

    await tocar(tester, 'Reiniciar agora');

    expect(atualizador.reiniciouCom?.build, 5);
    await desmontar(tester);
  });

  testWidgets('falha ao baixar mantem o bloqueio e permite tentar de novo', (
    tester,
  ) async {
    atualizador
      ..publicado = _manifesto(obrigatoria: true)
      ..falhasAoBaixar = 1;
    await montar(tester);

    await tocar(tester, 'Atualizar');

    expect(find.text('conteudo'), findsNothing);
    expect(find.text('Não foi possível atualizar'), findsOneWidget);

    await tocar(tester, 'Tentar de novo');

    expect(atualizador.downloads, 2);
    expect(find.text('Atualização pronta'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('build que ja falhou no script mostra o erro do script', (
    tester,
  ) async {
    atualizador
      ..publicado = _manifesto(obrigatoria: true)
      ..falhouAntes = true;

    await montar(tester);

    expect(find.text('Não foi possível atualizar'), findsOneWidget);
    expect(find.text('o app nao fechou em 60 segundos'), findsOneWidget);
    expect(atualizador.downloads, 0);
    await desmontar(tester);
  });

  testWidgets(
      'app que fechou para atualizar e voltou antigo avisa que o script nao rodou',
      (
    tester,
  ) async {
    atualizador
      ..publicado = _manifesto(obrigatoria: true)
      ..scriptNaoRodou = true;

    await montar(tester);

    expect(find.text(kMensagemScriptNaoRodou), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
    expect(atualizador.downloads, 0);
    await desmontar(tester);
  });

  testWidgets('versao opcional oferece atualizar e pode ser adiada', (
    tester,
  ) async {
    atualizador.publicado = _manifesto(obrigatoria: false);

    await montar(tester);

    expect(find.text('conteudo'), findsOneWidget);
    expect(find.text('Versão 1.0.0+5 disponível.'), findsOneWidget);
    expect(atualizador.downloads, 0);

    await tocar(tester, 'Depois');

    expect(find.text('Versão 1.0.0+5 disponível.'), findsNothing);
    expect(find.text('conteudo'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('versao opcional atualiza e reinicia quando a pessoa pede', (
    tester,
  ) async {
    atualizador.publicado = _manifesto(obrigatoria: false);
    await montar(tester);

    await tocar(tester, 'Atualizar agora');
    expect(find.text('Atualização pronta'), findsOneWidget);

    await tocar(tester, 'Reiniciar agora');

    expect(atualizador.reiniciouCom?.build, 5);
    await desmontar(tester);
  });
}
