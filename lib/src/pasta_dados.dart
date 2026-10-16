import 'dart:io';

import 'package:path/path.dart' as p;

const _ambiente = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

String nomeDaPastaDeDados(String nomeApp, {String ambiente = _ambiente}) =>
    ambiente == 'prod' ? nomeApp : '$nomeApp Teste';

Future<Directory> pastaDeDadosDoApp(
  String nomeApp, {
  String ambiente = _ambiente,
  String? appData,
}) async {
  final raiz = appData ?? Platform.environment['APPDATA'];
  if (raiz == null || raiz.isEmpty) {
    throw StateError('APPDATA nao definido: pasta de dados so existe no Windows.');
  }
  final pasta = Directory(
    p.join(raiz, 'Agrosepac', nomeDaPastaDeDados(nomeApp, ambiente: ambiente)),
  );
  await pasta.create(recursive: true);
  return pasta;
}
