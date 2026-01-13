import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:brasil_fields/brasil_fields.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../database/db_helper.dart';

class PersonDetailsScreen extends StatefulWidget {
  final int pessoaId;
  final String nomeInicial;
  final String? telefoneInicial;

  const PersonDetailsScreen({
    Key? key,
    required this.pessoaId,
    required this.nomeInicial,
    this.telefoneInicial,
  }) : super(key: key);

  @override
  _PersonDetailsScreenState createState() => _PersonDetailsScreenState();
}

class _PersonDetailsScreenState extends State<PersonDetailsScreen> {
  List<Map<String, dynamic>> _transacoes = [];
  bool _isLoading = true;
  double _saldoAtual = 0;
  Set<int> _itensSelecionados = {};

  late TextEditingController _nomeController;
  late TextEditingController _telefoneController;

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController(text: widget.nomeInicial);
    _telefoneController = TextEditingController(text: widget.telefoneInicial ?? "");
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _isLoading = true);
    final transacoes = await DBHelper().getTransacoes(widget.pessoaId);
    final pessoaData = await DBHelper().getPessoa(widget.pessoaId);

    setState(() {
      _transacoes = transacoes;
      _itensSelecionados.clear();
      if (pessoaData != null) {
        _saldoAtual = pessoaData['saldo'] ?? 0.0;
        _nomeController.text = pessoaData['nome'];
        _telefoneController.text = pessoaData['telefone'] ?? "";
      }
      _isLoading = false;
    });
  }

  // ... (GERADOR DE PDF E WHATSAPP - MANTENHA A LÓGICA IGUAL, NÃO MUDA COM O TEMA) ...
  // Vou abreviar aqui para focar na interface visual, mas o código funcional é o mesmo do anterior.

  // --- LÓGICA DE DATAS ÚTEIS (Mantida) ---
  DateTime _calcularQuintoDiaUtil(int year, int month) {
    int diasUteisEncontrados = 0;
    int dia = 1;
    while (diasUteisEncontrados < 5) {
      DateTime dataTeste = DateTime(year, month, dia);
      if (dataTeste.weekday != DateTime.saturday && dataTeste.weekday != DateTime.sunday) {
        diasUteisEncontrados++;
      }
      if (diasUteisEncontrados < 5) dia++;
    }
    return DateTime(year, month, dia);
  }
  DateTime _sugerirQuintoDiaUtil() {
    DateTime hoje = DateTime.now();
    DateTime quinto = _calcularQuintoDiaUtil(hoje.year, hoje.month);
    return hoje.isAfter(quinto) ? _calcularQuintoDiaUtil(hoje.year, hoje.month + 1) : quinto;
  }
  DateTime _sugerirDia20() {
    DateTime hoje = DateTime.now();
    return hoje.day >= 20 ? DateTime(hoje.year, hoje.month + 1, 20) : DateTime(hoje.year, hoje.month, 20);
  }

  Future<void> _gerarPDF() async {
    final pdf = pw.Document();
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final dateFormat = DateFormat('dd/MM/yyyy');

    List<Map<String, dynamic>> itensParaImprimir = _itensSelecionados.isNotEmpty
        ? _transacoes.where((t) => _itensSelecionados.contains(t['id'])).toList()
        : _transacoes;

    if (itensParaImprimir.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Nenhum item para gerar documento.")));
      return;
    }

    double totalDocumento = itensParaImprimir.fold(0, (sum, item) => sum + (item['valor'] as double));
    String dataHoje = dateFormat.format(DateTime.now());

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(30),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(level: 0, child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text("EXTRATO DE CONTA", style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900)), pw.Text("Emissão: $dataHoje", style: pw.TextStyle(color: PdfColors.grey700))])),
              pw.SizedBox(height: 25),
              pw.Container(padding: pw.EdgeInsets.symmetric(vertical: 10), width: double.infinity, decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 1))), child: pw.Text(_nomeController.text.toUpperCase(), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
              if (_telefoneController.text.isNotEmpty) pw.Padding(padding: pw.EdgeInsets.only(top: 5, bottom: 20), child: pw.Text("Contato: ${_telefoneController.text}", style: pw.TextStyle(color: PdfColors.grey700))),
              pw.SizedBox(height: 20),
              pw.Table.fromTextArray(context: context, border: pw.TableBorder.all(color: PdfColors.grey200), headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white), headerDecoration: pw.BoxDecoration(color: PdfColors.blueGrey700), rowDecoration: pw.BoxDecoration(color: PdfColors.grey50), cellHeight: 32, cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.center, 2: pw.Alignment.centerRight}, headers: <String>['Descrição', 'Data/Venc.', 'Valor'], data: itensParaImprimir.map((item) => [item['descricao'], item['data_vencimento'] ?? item['data_hora'].toString().split(' ')[0], currencyFormat.format(item['valor'])]).toList()),
              pw.SizedBox(height: 15),
              pw.Container(alignment: pw.Alignment.centerRight, padding: pw.EdgeInsets.all(10), decoration: pw.BoxDecoration(color: totalDocumento > 0 ? PdfColors.red50 : PdfColors.green50, borderRadius: pw.BorderRadius.circular(5)), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [pw.Text("SALDO SELECIONADO: ", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text(currencyFormat.format(totalDocumento), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: totalDocumento > 0 ? PdfColors.red900 : PdfColors.green900))])),
            ],
          );
        },
      ),
    );
    String nomeCliente = _nomeController.text.trim();
    String valorTotal = currencyFormat.format(totalDocumento);
    String dataCurta = DateFormat('dd/MM').format(DateTime.now());
    String legendaZap = "--------------------\n*$nomeCliente*\nSaldo Ref: $valorTotal\nData: $dataCurta\n--------------------\nSegue extrato detalhado em PDF.";
    await Printing.sharePdf(bytes: await pdf.save(), filename: 'extrato_${nomeCliente.replaceAll(' ', '_').toLowerCase()}.pdf', body: legendaZap);
  }

  Future<void> _abrirWhatsAppTexto() async {
    String telefone = _telefoneController.text.replaceAll(RegExp(r'[^\d]'), '');
    if (telefone.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Cadastre um telefone!"))); return; }
    if (telefone.length <= 11) telefone = "55$telefone";
    List<Map<String, dynamic>> itens = _itensSelecionados.isNotEmpty ? _transacoes.where((t) => _itensSelecionados.contains(t['id'])).toList() : _transacoes;
    if (itens.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Nada selecionado."))); return; }
    double total = 0;
    String txt = "";
    for (var item in itens) { total += item['valor']; String valStr = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(item['valor']); String icon = (item['valor'] as double) < 0 ? "🟢" : "🔴"; txt += "$icon ${item['descricao']} ($valStr)\n"; }
    String msg = "Olá ${_nomeController.text}.\n\n$txt\n*Saldo Final: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(total)}*";
    final Uri url = Uri.parse("https://wa.me/$telefone?text=${Uri.encodeComponent(msg)}");
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) { await launchUrl(Uri.parse("sms:$telefone?body=${Uri.encodeComponent(msg)}")); }
  }

  // --- FORMULÁRIO (VISUAL ADAPTADO PARA DARK MODE VIA THEME) ---
  Future<void> _mostrarFormularioTransacao({Map<String, dynamic>? transacaoExistente, bool isDividaNova = true}) async {
    final isEdicao = transacaoExistente != null;
    final bool isDivida = isEdicao ? (transacaoExistente['valor'] as double) > 0 : isDividaNova;

    final descricaoController = TextEditingController(text: isEdicao ? transacaoExistente['descricao'] : "");
    double valorInicial = isEdicao ? (transacaoExistente['valor'] as double).abs() : 0.0;
    final valorController = TextEditingController(text: isEdicao ? UtilBrasilFields.obterReal(valorInicial) : "");
    final jurosController = TextEditingController(text: isEdicao ? transacaoExistente['juros']?.toString() : "");
    final iofController = TextEditingController(text: isEdicao ? transacaoExistente['iof']?.toString() : "");
    DateTime? dataVencimento;
    if (isEdicao && transacaoExistente['data_vencimento'] != null) { try { dataVencimento = DateFormat('dd/MM/yyyy').parse(transacaoExistente['data_vencimento']); } catch (e) {} }

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
            builder: (context, setStateDialog) {
              void atualizarData(DateTime novaData) => setStateDialog(() => dataVencimento = novaData);
              return AlertDialog(
                title: Text(isEdicao ? "Editar Item" : (isDivida ? "Nova Dívida" : "Novo Pagamento")),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(controller: descricaoController, decoration: InputDecoration(labelText: "Descrição", border: OutlineInputBorder()), textCapitalization: TextCapitalization.sentences),
                      SizedBox(height: 10),
                      TextField(controller: valorController, decoration: InputDecoration(labelText: "Valor", hintText: "R\$ 0,00", border: OutlineInputBorder()), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, CentavosInputFormatter(moeda: true)]),
                      if (isDivida) ...[
                        SizedBox(height: 10),
                        Row(children: [Expanded(child: TextField(controller: jurosController, decoration: InputDecoration(labelText: "Juros %"), keyboardType: TextInputType.numberWithOptions(decimal: true))), SizedBox(width: 10), Expanded(child: TextField(controller: iofController, decoration: InputDecoration(labelText: "IOF %"), keyboardType: TextInputType.numberWithOptions(decimal: true)))]),
                        SizedBox(height: 15),
                        Text("Definir Vencimento:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), // A COR AGORA É AUTOMÁTICA
                        SizedBox(height: 5),
                        Wrap(spacing: 8, children: [
                          ActionChip(label: Text("5º Dia Útil"), onPressed: () => atualizarData(_sugerirQuintoDiaUtil())),
                          ActionChip(label: Text("Dia 20"), onPressed: () => atualizarData(_sugerirDia20())),
                        ]),
                        SizedBox(height: 10),
                        OutlinedButton.icon(icon: Icon(Icons.edit_calendar, size: 18), label: Text(dataVencimento == null ? "Selecionar Outra Data" : "Vence: ${DateFormat('dd/MM/yyyy').format(dataVencimento!)}"), onPressed: () async { final picked = await showDatePicker(context: context, initialDate: dataVencimento ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030)); if (picked != null) atualizarData(picked); }),
                      ]
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancelar")),
                  ElevatedButton(onPressed: () async {
                    if (valorController.text.isNotEmpty) {
                      double valor = UtilBrasilFields.converterMoedaParaDouble(valorController.text);
                      double juros = double.tryParse(jurosController.text.replaceAll(',', '.')) ?? 0.0;
                      double iof = double.tryParse(iofController.text.replaceAll(',', '.')) ?? 0.0;
                      if (valor > 0) {
                        double valorFinal = isDivida ? valor : -valor;
                        String? dataVencStr = dataVencimento != null ? DateFormat('dd/MM/yyyy').format(dataVencimento!) : null;
                        if (isEdicao) { await DBHelper().editarTransacao(transacaoExistente['id'], widget.pessoaId, valorFinal, descricaoController.text, dataVencStr, juros, iof); } else { await DBHelper().adicionarTransacao(widget.pessoaId, valorFinal, isDivida ? 'DIVIDA' : 'PAGAMENTO', descricaoController.text.isEmpty ? (isDivida ? "Compra" : "Pagamento") : descricaoController.text, dataVencStr, juros, iof); }
                        Navigator.pop(context); _carregarDados();
                      }
                    }
                  }, child: Text("Salvar"))
                ],
              );
            }
        );
      },
    );
  }

  Future<void> _editarCliente() async { await DBHelper().atualizarPessoa(widget.pessoaId, _nomeController.text, _telefoneController.text); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Salvo!"))); }
  Future<void> _deletarCliente() async { await DBHelper().deletarPessoa(widget.pessoaId); Navigator.pop(context); }
  void _toggleSelecao(int id) { setState(() { if (_itensSelecionados.contains(id)) _itensSelecionados.remove(id); else _itensSelecionados.add(id); }); }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    // VERIFICA SE ESTÁ EM MODO ESCURO PARA AJUSTAR AS CORES DOS CONTAINERS
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final containerColor = isDark ? Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white70 : Colors.grey[700];

    // Calcula total selecionado
    double totalSelecionado = 0;
    if (_itensSelecionados.isNotEmpty) { for (var item in _transacoes) { if (_itensSelecionados.contains(item['id'])) totalSelecionado += (item['valor'] as double); } } else { totalSelecionado = _saldoAtual; }

    return Scaffold(
      // AQUI: Removemos a cor fixa. Agora ele pega do tema (Cinza claro ou Preto)
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      appBar: AppBar(
        title: Text(_nomeController.text),
        actions: [IconButton(icon: Icon(Icons.delete_forever), onPressed: _deletarCliente)],
      ),
      body: Column(
        children: [
          // CONTAINER DO CABEÇALHO (SALDO E BOTÕES)
          Container(
            padding: EdgeInsets.all(20),
            color: containerColor, // Cor dinâmica
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Saldo Total", style: TextStyle(fontSize: 16, color: textColor)), // Cor dinâmica
                    Text(
                      currencyFormat.format(_saldoAtual),
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: _saldoAtual > 0 ? Colors.red : Colors.green),
                    ),
                  ],
                ),
                SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(child: ElevatedButton.icon(icon: Icon(Icons.picture_as_pdf), label: Text(_itensSelecionados.isEmpty ? "PDF Completo" : "PDF Seleção"), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], foregroundColor: Colors.white, padding: EdgeInsets.symmetric(vertical: 12)), onPressed: _gerarPDF)),
                    SizedBox(width: 10),
                    Expanded(child: ElevatedButton.icon(icon: Icon(Icons.chat), label: Text("WhatsApp"), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: EdgeInsets.symmetric(vertical: 12)), onPressed: _abrirWhatsAppTexto)),
                  ],
                ),
                ExpansionTile(
                  title: Text("Editar Dados Cliente", style: TextStyle(fontSize: 14, color: textColor)),
                  iconColor: textColor,
                  collapsedIconColor: textColor,
                  children: [
                    TextField(controller: _nomeController, decoration: InputDecoration(labelText: "Nome"), onEditingComplete: _editarCliente),
                    TextField(controller: _telefoneController, decoration: InputDecoration(labelText: "Telefone"), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, TelefoneInputFormatter()], onEditingComplete: _editarCliente),
                  ],
                ),
              ],
            ),
          ),

          // LISTA DE TRANSAÇÕES
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.all(10),
              itemCount: _transacoes.length,
              separatorBuilder: (ctx, i) => Divider(height: 1, color: isDark ? Colors.grey[800] : Colors.grey[300]),
              itemBuilder: (context, index) {
                final item = _transacoes[index];
                final valor = item['valor'] ?? 0.0;
                final isDivida = valor > 0;
                final isSelected = _itensSelecionados.contains(item['id']);

                return ListTile(
                  // COR DE FUNDO DA LISTA (Dinâmica)
                  tileColor: isSelected
                      ? Colors.blue.withOpacity(0.1)
                      : containerColor,

                  leading: Checkbox(value: isSelected, activeColor: isDivida ? Colors.red : Colors.green, onChanged: (v) => _toggleSelecao(item['id'])),
                  title: Text(item['descricao'] ?? "Sem descrição", style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${item['data_hora']} ${item['data_vencimento'] != null ? '• Vence: ${item['data_vencimento']}' : ''}", style: TextStyle(color: textColor)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(currencyFormat.format(valor.abs()), style: TextStyle(fontWeight: FontWeight.bold, color: isDivida ? Colors.red : Colors.green)),
                      IconButton(icon: Icon(Icons.edit, color: Colors.blue, size: 20), onPressed: () => _mostrarFormularioTransacao(transacaoExistente: item)),
                      IconButton(icon: Icon(Icons.delete_outline, color: Colors.grey, size: 20), onPressed: () async { await DBHelper().removerTransacao(item['id'], widget.pessoaId); _carregarDados(); })
                    ],
                  ),
                  onTap: () => _toggleSelecao(item['id']),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.all(15),
        color: containerColor, // Cor dinâmica
        child: Row(
          children: [
            Expanded(child: ElevatedButton.icon(icon: Icon(Icons.attach_money), label: Text("PAGAR"), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: EdgeInsets.symmetric(vertical: 15)), onPressed: () => _mostrarFormularioTransacao(isDividaNova: false))),
            SizedBox(width: 15),
            Expanded(child: ElevatedButton.icon(icon: Icon(Icons.add_shopping_cart), label: Text("NOVA DÍVIDA"), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: EdgeInsets.symmetric(vertical: 15)), onPressed: () => _mostrarFormularioTransacao(isDividaNova: true))),
          ],
        ),
      ),
    );
  }
}