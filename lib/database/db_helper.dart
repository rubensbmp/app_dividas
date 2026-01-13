import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:intl/intl.dart';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  static Database? _database;

  factory DBHelper() => _instance;

  DBHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'faca_bainha_v3.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE pessoas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome TEXT NOT NULL,
        telefone TEXT,
        saldo REAL DEFAULT 0.0,
        ultima_data TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE transacoes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pessoa_id INTEGER NOT NULL,
        valor REAL NOT NULL,
        tipo TEXT NOT NULL,
        descricao TEXT,
        data_hora TEXT,
        data_vencimento TEXT, 
        juros REAL DEFAULT 0.0,
        iof REAL DEFAULT 0.0, 
        FOREIGN KEY (pessoa_id) REFERENCES pessoas (id) ON DELETE CASCADE
      )
    ''');
  }

  // --- PESSOAS ---
  Future<int> cadastrarPessoa(String nome, String telefone) async {
    final db = await database;
    String dataAtual = DateFormat('dd/MM/yyyy').format(DateTime.now());
    return await db.insert('pessoas', {
      'nome': nome,
      'telefone': telefone,
      'saldo': 0.0,
      'ultima_data': dataAtual
    });
  }

  Future<List<Map<String, dynamic>>> getPessoas() async {
    final db = await database;
    return await db.query('pessoas', orderBy: 'nome ASC');
  }

  Future<Map<String, dynamic>?> getPessoa(int id) async {
    final db = await database;
    final res = await db.query('pessoas', where: 'id = ?', whereArgs: [id]);
    if (res.isNotEmpty) return res.first;
    return null;
  }

  Future<int> atualizarPessoa(int id, String nome, String telefone) async {
    final db = await database;
    return await db.update('pessoas', {'nome': nome, 'telefone': telefone}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletarPessoa(int id) async {
    final db = await database;
    await db.delete('transacoes', where: 'pessoa_id = ?', whereArgs: [id]);
    await db.delete('pessoas', where: 'id = ?', whereArgs: [id]);
  }

  // --- TRANSAÇÕES ---

  Future<List<Map<String, dynamic>>> getTransacoes(int pessoaId) async {
    final db = await database;
    return await db.query('transacoes', where: 'pessoa_id = ?', whereArgs: [pessoaId], orderBy: 'id DESC');
  }

  Future<void> adicionarTransacao(int pessoaId, double valor, String tipo, String descricao, String? vencimento, double juros, double iof) async {
    final db = await database;
    String dataHora = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    await db.transaction((txn) async {
      await txn.insert('transacoes', {
        'pessoa_id': pessoaId,
        'valor': valor,
        'tipo': tipo,
        'descricao': descricao,
        'data_hora': dataHora,
        'data_vencimento': vencimento,
        'juros': juros,
        'iof': iof
      });
      await _atualizarSaldoPessoa(txn, pessoaId);
    });
  }

  // NOVA FUNÇÃO: EDITAR TRANSAÇÃO
  Future<void> editarTransacao(int transacaoId, int pessoaId, double novoValor, String novaDescricao, String? novoVencimento, double juros, double iof) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('transacoes', {
        'valor': novoValor,
        'descricao': novaDescricao,
        'data_vencimento': novoVencimento,
        'juros': juros,
        'iof': iof
      }, where: 'id = ?', whereArgs: [transacaoId]);

      await _atualizarSaldoPessoa(txn, pessoaId);
    });
  }

  Future<void> removerTransacao(int transacaoId, int pessoaId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('transacoes', where: 'id = ?', whereArgs: [transacaoId]);
      await _atualizarSaldoPessoa(txn, pessoaId);
    });
  }

  // Função auxiliar para recalcular saldo total (evita erros de conta)
  Future<void> _atualizarSaldoPessoa(Transaction txn, int pessoaId) async {
    final resultado = await txn.rawQuery("SELECT SUM(valor) as total FROM transacoes WHERE pessoa_id = ?", [pessoaId]);
    double novoSaldo = 0.0;
    if (resultado.first['total'] != null) {
      novoSaldo = resultado.first['total'] as double;
    }
    await txn.update(
      'pessoas',
      {'saldo': novoSaldo, 'ultima_data': DateFormat('dd/MM/yyyy').format(DateTime.now())},
      where: 'id = ?',
      whereArgs: [pessoaId],
    );
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}