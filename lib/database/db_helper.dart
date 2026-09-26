import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:intl/intl.dart';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  static Database? _database;

  factory DBHelper() => _instance;

  DBHelper._internal();

  // Nome e versão do banco em uso (o BackupService exporta/importa este mesmo arquivo)
  static const String NOME_BANCO = 'faca_bainha_v4.db';
  static const int VERSAO_BANCO = 4;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), NOME_BANCO);
    return await openDatabase(
      path,
      version: VERSAO_BANCO,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // _criarTabelaAnotacoes já cria nivel_prioridade e ordem; os ALTER abaixo dariam "duplicate column"
          await _criarTabelaAnotacoes(db);
          return;
        }
        if (oldVersion < 3) await db.execute('ALTER TABLE anotacoes ADD COLUMN nivel_prioridade INTEGER DEFAULT 0');
        if (oldVersion < 4) await db.execute('ALTER TABLE anotacoes ADD COLUMN ordem INTEGER DEFAULT 0');
      },
      onCreate: (db, version) async {
        await _criarTabelaPessoas(db);
        await _criarTabelaTransacoes(db);
        await _criarTabelaAnotacoes(db);
      },
    );
  }

  // --- TABELAS ---
  Future _criarTabelaPessoas(Database db) async {
    await db.execute('CREATE TABLE pessoas (id INTEGER PRIMARY KEY AUTOINCREMENT, nome TEXT NOT NULL, telefone TEXT, saldo REAL DEFAULT 0.0, ultima_data TEXT)');
  }

  Future _criarTabelaTransacoes(Database db) async {
    await db.execute('CREATE TABLE transacoes (id INTEGER PRIMARY KEY AUTOINCREMENT, pessoa_id INTEGER NOT NULL, valor REAL NOT NULL, tipo TEXT NOT NULL, descricao TEXT, data_hora TEXT, data_vencimento TEXT, juros REAL DEFAULT 0.0, iof REAL DEFAULT 0.0, FOREIGN KEY (pessoa_id) REFERENCES pessoas (id) ON DELETE CASCADE)');
  }

  Future _criarTabelaAnotacoes(Database db) async {
    await db.execute('''
      CREATE TABLE anotacoes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pessoa_id INTEGER NOT NULL,
        texto TEXT NOT NULL,
        is_checklist INTEGER DEFAULT 0, 
        is_concluido INTEGER DEFAULT 0,
        valor_associado REAL DEFAULT 0.0,
        data_vencimento TEXT,
        nivel_prioridade INTEGER DEFAULT 0,
        ordem INTEGER DEFAULT 0,
        FOREIGN KEY (pessoa_id) REFERENCES pessoas (id) ON DELETE CASCADE
      )
    ''');
  }

  // --- PESSOAS ---
  Future<int> cadastrarPessoa(String nome, String telefone) async { final db = await database; return await db.insert('pessoas', {'nome': nome, 'telefone': telefone, 'saldo': 0.0, 'ultima_data': DateFormat('dd/MM/yyyy').format(DateTime.now())}); }
  Future<List<Map<String, dynamic>>> getPessoas() async { final db = await database; return await db.query('pessoas', orderBy: 'nome ASC'); }
  Future<Map<String, dynamic>?> getPessoa(int id) async { final db = await database; final res = await db.query('pessoas', where: 'id = ?', whereArgs: [id]); return res.isNotEmpty ? res.first : null; }
  Future<int> atualizarPessoa(int id, String nome, String telefone) async { final db = await database; return await db.update('pessoas', {'nome': nome, 'telefone': telefone}, where: 'id = ?', whereArgs: [id]); }
  Future<void> deletarPessoa(int id) async { final db = await database; await db.delete('transacoes', where: 'pessoa_id = ?', whereArgs: [id]); await db.delete('anotacoes', where: 'pessoa_id = ?', whereArgs: [id]); await db.delete('pessoas', where: 'id = ?', whereArgs: [id]); }

  // --- TRANSAÇÕES (ATUALIZADO PARA DATA RETROATIVA) ---
  Future<List<Map<String, dynamic>>> getTransacoes(int pessoaId) async { final db = await database; return await db.query('transacoes', where: 'pessoa_id = ?', whereArgs: [pessoaId], orderBy: 'id DESC'); }

  // MUDANÇA AQUI: Adicionado {String? dataPersonalizada}
  Future<void> adicionarTransacao(int pessoaId, double valor, String tipo, String descricao, String? vencimento, double juros, double iof, {String? dataPersonalizada}) async {
    final db = await database;

    // Se você mandou uma data antiga, usa ela. Se não, usa Agora.
    String dataHora = dataPersonalizada ?? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    await db.transaction((txn) async {
      await txn.insert('transacoes', {'pessoa_id': pessoaId, 'valor': valor, 'tipo': tipo, 'descricao': descricao, 'data_hora': dataHora, 'data_vencimento': vencimento, 'juros': juros, 'iof': iof});
      await _atualizarSaldoPessoa(txn, pessoaId);
    });
  }

  Future<void> editarTransacao(int transacaoId, int pessoaId, double novoValor, String novaDescricao, String? novoVencimento, double juros, double iof) async { final db = await database; await db.transaction((txn) async { await txn.update('transacoes', {'valor': novoValor, 'descricao': novaDescricao, 'data_vencimento': novoVencimento, 'juros': juros, 'iof': iof}, where: 'id = ?', whereArgs: [transacaoId]); await _atualizarSaldoPessoa(txn, pessoaId); }); }
  Future<void> removerTransacao(int transacaoId, int pessoaId) async { final db = await database; await db.transaction((txn) async { await txn.delete('transacoes', where: 'id = ?', whereArgs: [transacaoId]); await _atualizarSaldoPessoa(txn, pessoaId); }); }
  Future<void> _atualizarSaldoPessoa(Transaction txn, int pessoaId) async { final resultado = await txn.rawQuery("SELECT SUM(valor) as total FROM transacoes WHERE pessoa_id = ?", [pessoaId]); double novoSaldo = (resultado.first['total'] as double?) ?? 0.0; await txn.update('pessoas', {'saldo': novoSaldo, 'ultima_data': DateFormat('dd/MM/yyyy').format(DateTime.now())}, where: 'id = ?', whereArgs: [pessoaId]); }

  // --- ANOTAÇÕES ---
  Future<List<Map<String, dynamic>>> getAnotacoes(int pessoaId) async { final db = await database; return await db.query('anotacoes', where: 'pessoa_id = ?', whereArgs: [pessoaId], orderBy: 'ordem ASC'); }
  Future<void> adicionarAnotacao(int pessoaId, String texto, {bool isChecklist = false, double valor = 0.0, String? dataVenc, int prioridade = 0}) async { final db = await database; final res = await db.rawQuery("SELECT MIN(ordem) as minOrdem FROM anotacoes WHERE pessoa_id = ?", [pessoaId]); int topoOrdem = (res.first['minOrdem'] as int? ?? 0) - 1; await db.insert('anotacoes', {'pessoa_id': pessoaId, 'texto': texto, 'is_checklist': isChecklist ? 1 : 0, 'is_concluido': 0, 'valor_associado': valor, 'data_vencimento': dataVenc, 'nivel_prioridade': prioridade, 'ordem': topoOrdem}); }
  Future<void> atualizarOrdemAnotacoes(List<Map<String, dynamic>> listaReordenada) async { final db = await database; await db.transaction((txn) async { for (int i = 0; i < listaReordenada.length; i++) { await txn.update('anotacoes', {'ordem': i}, where: 'id = ?', whereArgs: [listaReordenada[i]['id']]); } }); }
  Future<void> atualizarPrioridadeAnotacao(int id, int novaPrioridade) async { final db = await database; await db.update('anotacoes', {'nivel_prioridade': novaPrioridade}, where: 'id = ?', whereArgs: [id]); }
  Future<void> alternarStatusAnotacao(int id, bool concluido) async { final db = await database; await db.update('anotacoes', {'is_concluido': concluido ? 1 : 0}, where: 'id = ?', whereArgs: [id]); }
  Future<void> deletarAnotacao(int id) async { final db = await database; await db.delete('anotacoes', where: 'id = ?', whereArgs: [id]); }
  Future<void> close() async { final db = await database; await db.close(); _database = null; }
}