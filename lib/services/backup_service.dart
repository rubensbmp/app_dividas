import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../database/db_helper.dart';
import '../utils/share_origin.dart';

class BackupService {

  static const String KEY_ULTIMO_BACKUP = 'data_ultimo_backup';
  // IMPORTANTE: precisa ser o mesmo arquivo que o DBHelper abre
  static const String NOME_INTERNO = DBHelper.NOME_BANCO;

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
        // Fecha a conexão para gravar tudo no arquivo antes de copiar
        await DBHelper().close();

        // Faz uma cópia temporária com o nome bonito
        await dbFile.copy(pathExportacao);

        // Abre o compartilhamento nativo
        await Share.shareXFiles(
            [XFile(pathExportacao)],
            text: 'Backup Controle de Dívidas ($dataHoje)',
            sharePositionOrigin: origemCompartilhamento(),
        );

        await _atualizarDataBackup(); // Reseta o contador de 7 dias

      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Nenhum banco de dados encontrado.")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao criar backup: $e")));
    }
  }

  // Confere se o arquivo é um banco deste app numa versão que o DBHelper sabe migrar.
  // Retorna a mensagem de erro, ou null se estiver tudo certo.
  Future<String?> _validarBackup(String path) async {
    Database? db;
    try {
      db = await openDatabase(path, readOnly: true, singleInstance: false);
      final versao = await db.getVersion();
      final tabelas = (await db.query('sqlite_master', columns: ['name'], where: "type = 'table'"))
          .map((t) => t['name'])
          .toSet();
      if (!tabelas.contains('pessoas') || !tabelas.contains('transacoes')) {
        return "Este arquivo não é um backup do Controle de Dívidas.";
      }
      if (versao < 2) {
        return "Este backup é de uma versão antiga do app e não pode ser restaurado. Gere um backup novo.";
      }
      if (versao > DBHelper.VERSAO_BANCO) {
        return "Este backup é de uma versão mais nova do app. Atualize o app antes de restaurar.";
      }
      return null;
    } catch (e) {
      return "Arquivo de backup inválido.";
    } finally {
      await db?.close();
    }
  }

  // --- IMPORTAR (Restaura o arquivo) ---
  Future<void> importarBanco(BuildContext context, VoidCallback onSuccess) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();

      if (result != null) {
        File file = File(result.files.single.path!);

        final erro = await _validarBackup(file.path);
        if (erro != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro)));
          return;
        }

        var databasesPath = await getDatabasesPath();
        String dbPath = join(databasesPath, NOME_INTERNO);

        // Fecha conexão antes de substituir o arquivo (evita corrupção)
        await DBHelper().close();

        // Remove journal/WAL do banco antigo para não serem aplicados sobre o backup
        for (final sufixo in ['-journal', '-wal', '-shm']) {
          final extra = File('$dbPath$sufixo');
          if (await extra.exists()) await extra.delete();
        }

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