import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../database/db_helper.dart';

class BackupService {

  static const String KEY_ULTIMO_BACKUP = 'data_ultimo_backup';
  // IMPORTANTE: Nome interno do arquivo no celular (não muda para não perder dados)
  static const String NOME_INTERNO = 'faca_bainha_v3.db';

  // Verifica se já passaram 7 dias desde o último backup
  Future<bool> precisaFazerBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final String? dataStr = prefs.getString(KEY_ULTIMO_BACKUP);

    if (dataStr == null) return true; // Nunca fez

    DateTime ultimoBackup = DateTime.parse(dataStr);
    DateTime agora = DateTime.now();
    int diasPassados = agora.difference(ultimoBackup).inDays;

    return diasPassados >= 7;
  }

  // Marca que o backup foi feito agora
  Future<void> _atualizarDataBackup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(KEY_ULTIMO_BACKUP, DateTime.now().toIso8601String());
  }

  // --- EXPORTAR (Envia para WhatsApp/Drive) ---
  Future<void> exportarBanco(BuildContext context) async {
    try {
      var databasesPath = await getDatabasesPath();

      // Cria o nome amigável com a data de hoje: ex: controle_de_dividas_14-01-2026.db
      String dataHoje = DateFormat('dd-MM-yyyy').format(DateTime.now());
      String nomeExterno = 'controle_de_dividas_$dataHoje.db';

      String pathOriginal = join(databasesPath, NOME_INTERNO);
      String pathExportacao = join(databasesPath, nomeExterno);

      File dbFile = File(pathOriginal);

      if (await dbFile.exists()) {
        // Faz uma cópia temporária com o nome bonito
        await dbFile.copy(pathExportacao);

        // Abre o compartilhamento nativo
        await Share.shareXFiles(
            [XFile(pathExportacao)],
            text: 'Backup Controle de Dívidas ($dataHoje)'
        );

        await _atualizarDataBackup(); // Reseta o contador de 7 dias

      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Nenhum banco de dados encontrado.")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao criar backup: $e")));
    }
  }

  // --- IMPORTAR (Restaura o arquivo) ---
  Future<void> importarBanco(BuildContext context, VoidCallback onSuccess) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();

      if (result != null) {
        File file = File(result.files.single.path!);

        var databasesPath = await getDatabasesPath();
        String dbPath = join(databasesPath, NOME_INTERNO);

        // Fecha conexão antes de substituir o arquivo (evita corrupção)
        await DBHelper().close();

        await file.copy(dbPath);

        await _atualizarDataBackup();

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Backup restaurado com sucesso!")));
        onSuccess(); // Atualiza a tela
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao restaurar backup: $e")));
    }
  }
}