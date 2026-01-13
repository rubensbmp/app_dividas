import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:brasil_fields/brasil_fields.dart';
import 'package:intl/intl.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../main.dart'; // Importante para acessar o themeModeNotifier
import '../database/db_helper.dart';
import '../services/backup_service.dart';
import 'person_details_screen.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _pessoas = [];
  List<Map<String, dynamic>> _pessoasFiltradas = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _atualizarLista();
    _searchController.addListener(_filtrarLista);
  }

  double _calcularTotalGeral() {
    double total = 0;
    for (var p in _pessoas) {
      total += (p['saldo'] ?? 0.0);
    }
    return total;
  }

  void _filtrarLista() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _pessoasFiltradas = _pessoas.where((p) {
        return p['nome'].toLowerCase().contains(query);
      }).toList();
    });
  }

  void _atualizarLista() async {
    final data = await DBHelper().getPessoas();
    setState(() {
      _pessoas = data;
      _pessoasFiltradas = data;
      _isLoading = false;
    });
    if (_searchController.text.isNotEmpty) _filtrarLista();
  }

  // --- MENU DE TEMAS E CORES ---
  void _mostrarConfiguracoesAparencia() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(children: [Icon(Icons.palette), SizedBox(width: 10), Text("Aparência")]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Modo Escuro", style: TextStyle(fontWeight: FontWeight.bold)),
              SwitchListTile(
                title: Text("Ativar Dark Mode"),
                secondary: Icon(Icons.dark_mode),
                value: themeModeNotifier.value == ThemeMode.dark,
                onChanged: (val) {
                  themeModeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
                  Navigator.pop(context); // Fecha para aplicar visualmente
                },
              ),
              Divider(),
              Text("Cor do Tema", style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _corBotao(Colors.blue, "Azul"),
                  _corBotao(Colors.green, "Verde"),
                  _corBotao(Colors.red, "Vermelho"),
                  _corBotao(Colors.orange, "Laranja"),
                  _corBotao(Colors.purple, "Roxo"),
                  _corBotao(Colors.blueGrey, "Cinza"),
                  _corBotao(Colors.black, "Preto"),
                ],
              )
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text("Fechar"))],
        );
      },
    );
  }

  Widget _corBotao(Color cor, String nome) {
    return GestureDetector(
      onTap: () {
        colorNotifier.value = cor;
        Navigator.pop(context);
      },
      child: Column(
        children: [
          CircleAvatar(
            backgroundColor: cor,
            radius: 20,
            child: colorNotifier.value == cor ? Icon(Icons.check, color: Colors.white) : null,
          ),
          SizedBox(height: 4),
          Text(nome, style: TextStyle(fontSize: 10))
        ],
      ),
    );
  }

  // --- FORMULÁRIO COM BUSCA DE CONTATO ---
  void _mostrarFormularioPessoa() {
    final nomeController = TextEditingController();
    final telefoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Novo Cliente"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: Icon(Icons.contacts, size: 18),
                label: Text("Importar da Agenda"),
                style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).primaryColor,
                    side: BorderSide(color: Theme.of(context).primaryColor),
                    padding: EdgeInsets.symmetric(vertical: 12)
                ),
                onPressed: () async {
                  try {
                    if (await FlutterContacts.requestPermission(readonly: true)) {
                      final contact = await FlutterContacts.openExternalPick();
                      if (contact != null) {
                        setState(() {
                          nomeController.text = contact.displayName;
                          if (contact.phones.isNotEmpty) {
                            String nums = contact.phones.first.number.replaceAll(RegExp(r'[^\d]'), '');
                            telefoneController.text = nums;
                          }
                        });
                      }
                    }
                  } catch (e) { print("Erro: $e"); }
                },
              ),
            ),
            SizedBox(height: 15),
            Divider(),
            SizedBox(height: 10),
            TextField(
              controller: nomeController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: "Nome", prefixIcon: Icon(Icons.person), border: OutlineInputBorder()),
            ),
            SizedBox(height: 10),
            TextField(
              controller: telefoneController,
              decoration: InputDecoration(labelText: "Telefone", prefixIcon: Icon(Icons.phone), border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, TelefoneInputFormatter()],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancelar")),
          ElevatedButton(
            onPressed: () async {
              if (nomeController.text.isNotEmpty) {
                await DBHelper().cadastrarPessoa(nomeController.text, telefoneController.text);
                Navigator.pop(context);
                _atualizarLista();
              }
            },
            child: Text("Salvar"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    double totalGeral = _calcularTotalGeral();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // Se for dark, usa a cor do tema, se não, usa o cinza claro
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text("Controle de Dívidas"),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'exportar') {
                BackupService().exportarBanco(context);
              } else if (value == 'importar') {
                BackupService().importarBanco(context, () { _atualizarLista(); });
              } else if (value == 'tema') {
                _mostrarConfiguracoesAparencia();
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                PopupMenuItem(value: 'tema', child: Row(children: [Icon(Icons.palette, color: Colors.orange), SizedBox(width: 10), Text("Aparência")])),
                PopupMenuItem(value: 'exportar', child: Row(children: [Icon(Icons.upload, color: Colors.green), SizedBox(width: 10), Text("Backup")])),
                PopupMenuItem(value: 'importar', child: Row(children: [Icon(Icons.download, color: Colors.blue), SizedBox(width: 10), Text("Restaurar")])),
              ];
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              // No modo escuro, o cabeçalho fica cinza escuro. No claro, fica da cor principal.
                color: isDark ? Color(0xFF1E1E1E) : Theme.of(context).primaryColor,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))]
            ),
            child: Column(
              children: [
                Text("Total a Receber", style: TextStyle(color: Colors.white70, fontSize: 16)),
                SizedBox(height: 5),
                Text(
                  currencyFormat.format(totalGeral),
                  style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 15),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: "Buscar cliente...",
                    fillColor: isDark ? Colors.grey[800] : Colors.white,
                    filled: true,
                    prefixIcon: Icon(Icons.search, color: isDark ? Colors.white : Theme.of(context).primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                    contentPadding: EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _pessoasFiltradas.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.person_off, size: 60, color: Colors.grey), Text("Nenhum cliente encontrado", style: TextStyle(color: Colors.grey))]))
                : GridView.builder(
              padding: EdgeInsets.all(15),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 15,
                mainAxisSpacing: 15,
                childAspectRatio: 0.90,
              ),
              itemCount: _pessoasFiltradas.length,
              itemBuilder: (context, index) {
                final pessoa = _pessoasFiltradas[index];
                final saldo = pessoa['saldo'] ?? 0.0;
                final ultimaData = pessoa['ultima_data'];

                return GestureDetector(
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PersonDetailsScreen(
                          pessoaId: pessoa['id'],
                          nomeInicial: pessoa['nome'],
                          telefoneInicial: pessoa['telefone'],
                        ),
                      ),
                    );
                    _atualizarLista();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                      border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey.shade200),
                    ),
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              width: 45,
                              height: 45,
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                    pessoa['nome'][0].toUpperCase(),
                                    style: TextStyle(
                                        color: Theme.of(context).primaryColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20
                                    )
                                ),
                              ),
                            ),
                            if (saldo > 0) Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24)
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pessoa['nome'],
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Color(0xFF2D3436)
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (ultimaData != null)
                              Text("Últ.: $ultimaData", style: TextStyle(fontSize: 10, color: Colors.grey)),
                          ],
                        ),
                        Text(
                          currencyFormat.format(saldo),
                          style: TextStyle(
                            color: saldo > 0 ? Colors.red : (saldo < 0 ? Colors.green : Colors.grey),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _mostrarFormularioPessoa,
        child: Icon(Icons.person_add),
      ),
    );
  }
}