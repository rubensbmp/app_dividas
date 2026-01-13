import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../database/db_helper.dart';

class BackupService {

  // Função para EXPORTAR (Salvar)
  Future<void> exportarBanco(BuildContext context) async {
    try {
      // 1. Acha onde o banco de dados está escondido
      String dbPath = join(await getDatabasesPath(), 'app_dividas_v3.db');
      File dbFile = File(dbPath);

      if (!await dbFile.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Nenhum dado para salvar ainda.")));
        return;
      }

      // 2. Cria uma cópia temporária com nome bonito (ex: backup_dividas_data.db)
      final directory = await getTemporaryDirectory();
      final date = DateTime.now().toString().split(' ')[0]; // Pega só a data (2023-10-25)
      String newPath = '${directory.path}/backup_dividas_$date.db';

      await dbFile.copy(newPath);

      // 3. Abre a janelinha de compartilhar (WhatsApp, Drive, Email...)
      await Share.shareXFiles([XFile(newPath)], text: 'Backup App Dívidas ($date)');

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao criar backup: $e")));
    }
  }

  // Função para IMPORTAR (Restaurar)
  Future<void> importarBanco(BuildContext context, Function onSucesso) async {
    try {
      // 1. Abre a janela para você escolher o arquivo
      FilePickerResult? result = await FilePicker.platform.pickFiles();

      if (result != null) {
        File file = File(result.files.single.path!);

        // Confirmação de Segurança
        bool confirmar = await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text("Cuidado!"),
            content: Text("Isso vai APAGAR todos os dados atuais e substituir pelo backup. Tem certeza?"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("Cancelar")),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("SIM, Restaurar", style: TextStyle(color: Colors.red))),
            ],
          ),
        ) ?? false;

        if (confirmar) {
          // 2. Fecha o banco atual para não dar erro
          await DBHelper().close();

          // 3. Substitui o arquivo velho pelo novo
          String dbPath = join(await getDatabasesPath(), 'app_dividas_v3.db');
          await file.copy(dbPath);

          // 4. Avisa que deu certo
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Dados restaurados com sucesso!")));

          // Chama a função para recarregar a tela
          onSucesso();
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao restaurar: $e")));
    }
  }
}