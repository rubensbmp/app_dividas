import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:brasil_fields/brasil_fields.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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

class _PersonDetailsScreenState extends State<PersonDetailsScreen> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _transacoes = [];
  List<Map<String, dynamic>> _anotacoes = [];

  bool _isLoading = true;
  double _saldoAtual = 0;
  Set<int> _itensSelecionados = {};

  // Variável para checkbox do PDF no WhatsApp
  bool _anexarPdfAoZap = false;

  late TextEditingController _nomeController;
  late TextEditingController _telefoneController;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController(text: widget.nomeInicial);
    _telefoneController = TextEditingController(text: widget.telefoneInicial ?? "");
    _tabController = TabController(length: 2, vsync: this);
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _isLoading = true);
    final transacoes = await DBHelper().getTransacoes(widget.pessoaId);
    final anotacoes = await DBHelper().getAnotacoes(widget.pessoaId);
    final pessoaData = await DBHelper().getPessoa(widget.pessoaId);

    setState(() {
      _transacoes = transacoes;
      _anotacoes = List.from(anotacoes);
      if (pessoaData != null) {
        _saldoAtual = pessoaData['saldo'] ?? 0.0;
        _nomeController.text = pessoaData['nome'];
        _telefoneController.text = pessoaData['telefone'] ?? "";
      }
      _isLoading = false;
    });
  }

  // --- GERAÇÃO DO PDF ---
  Future<Uint8List> _gerarBytesDoPDF(List<Map<String, dynamic>> itens, double total) async {
    final pdf = pw.Document();
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(30),
        build: (context) => [
          pw.Header(
              level: 0,
              child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("EXTRATO / RECIBO", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
                    pw.Text("Emissão: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}"),
                  ]
              )
          ),
          pw.SizedBox(height: 10),
          pw.Text("Cliente: ${_nomeController.text.toUpperCase()}", style: pw.TextStyle(fontSize: 14)),
          if (_telefoneController.text.isNotEmpty) pw.Text("Telefone: ${_telefoneController.text}"),
          pw.Divider(),
          pw.SizedBox(height: 15),

          pw.Table.fromTextArray(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            headerDecoration: pw.BoxDecoration(color: PdfColors.grey200),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellHeight: 30,
            columnWidths: {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(1.5),
              2: pw.FlexColumnWidth(1.5),
            },
            headers: ['Descrição', 'Data', 'Valor'],
            data: itens.map((i) {
              return [
                i['descricao'] ?? "",
                i['data_vencimento'] ?? i['data_hora'].split(' ')[0],
                currencyFormat.format(i['valor']),
              ];
            }).toList(),
          ),

          pw.SizedBox(height: 10),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              "TOTAL DESTE EXTRATO: ${currencyFormat.format(total)}",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
            ),
          ),

          pw.SizedBox(height: 50),

          pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                    children: [
                      pw.Container(width: 100, decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide()))),
                      pw.SizedBox(height: 5),
                      pw.Text("Data"),
                    ]
                ),
                pw.Column(
                    children: [
                      pw.Container(width: 180, decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide()))),
                      pw.SizedBox(height: 5),
                      pw.Text("Assinatura / Visto"),
                    ]
                ),
              ]
          ),
        ],
      ),
    );
    return await pdf.save();
  }

  Future<void> _visualizarPDF() async {
    List<Map<String, dynamic>> itensParaPDF = _itensSelecionados.isNotEmpty
        ? _transacoes.where((t) => _itensSelecionados.contains(t['id'])).toList()
        : _transacoes;

    if (itensParaPDF.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Nenhum item para gerar PDF.")));
      return;
    }

    double total = itensParaPDF.fold(0, (sum, item) => sum + (item['valor'] as double));
    final bytes = await _gerarBytesDoPDF(itensParaPDF, total);

    await Printing.layoutPdf(onLayout: (format) async => bytes);
  }

  // --- LÓGICA DO WHATSAPP (LINK DIRETO OU SHARE SHEET) ---
  Future<void> _compartilharWhatsApp() async {
    List<Map<String, dynamic>> itensParaEnviar = _itensSelecionados.isNotEmpty
        ? _transacoes.where((t) => _itensSelecionados.contains(t['id'])).toList()
        : _transacoes;

    if (itensParaEnviar.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Selecione algo para enviar.")));
      return;
    }

    double total = 0.0;
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    String legenda = "Olá ${_nomeController.text}!\n\n";

    for (var item in itensParaEnviar) {
      double val = item['valor'] as double;
      total += val;
      String data = item['data_vencimento'] ?? item['data_hora'].split(' ')[0];
      String desc = item['descricao'] ?? "Sem descrição";
      String icone = val > 0 ? "🔴" : "🟢";

      legenda += "$icone $data - $desc\n*${currency.format(val)}*\n";
    }

    legenda += "---------------------------\n";
    legenda += "*TOTAL: ${currency.format(total)}*";

    try {
      if (_anexarPdfAoZap) {
        // MODO PDF + TEXTO (Usa Share Sheet pois WhatsApp não aceita anexo via link)
        final pdfBytes = await _gerarBytesDoPDF(itensParaEnviar, total);
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/extrato_${_nomeController.text.replaceAll(' ', '_')}.pdf');
        await file.writeAsBytes(pdfBytes);

        await Share.shareXFiles(
          [XFile(file.path)],
          text: legenda,
        );
      } else {
        // MODO SÓ TEXTO (Abre direto o contato do WhatsApp)
        String telefone = _telefoneController.text.replaceAll(RegExp(r'[^\d]'), '');

        if (telefone.isEmpty) {
          await Share.share(legenda);
        } else {
          if (telefone.length <= 11) telefone = "55$telefone";

          final whatsappUrl = Uri.parse("https://wa.me/$telefone?text=${Uri.encodeComponent(legenda)}");

          if (await canLaunchUrl(whatsappUrl)) {
            await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
          } else {
            await Share.share(legenda);
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao enviar: $e")));
    }
  }

  // --- LÓGICA DO FORMULÁRIO (COM DATA RETROATIVA) ---
  Future<void> _mostrarFormularioTransacao({Map<String, dynamic>? transacaoExistente, bool isDividaNova = true}) async {
    final isEdicao = transacaoExistente != null;
    final bool isDivida = isEdicao ? (transacaoExistente['valor'] as double) > 0 : isDividaNova;
    final descricaoController = TextEditingController(text: isEdicao ? transacaoExistente['descricao'] : "");
    double valorInicial = isEdicao ? (transacaoExistente['valor'] as double).abs() : 0.0;
    final valorController = TextEditingController(text: isEdicao ? UtilBrasilFields.obterReal(valorInicial) : "");

    DateTime? dataVencimento;
    DateTime dataLancamento = DateTime.now(); // Padrão: Hoje

    if (isEdicao) {
      if (transacaoExistente['data_vencimento'] != null) {
        try { dataVencimento = DateFormat('dd/MM/yyyy').parse(transacaoExistente['data_vencimento']); } catch (e) {}
      }
      if (transacaoExistente['data_hora'] != null) {
        try {
          dataLancamento = DateFormat('dd/MM/yyyy HH:mm').parse(transacaoExistente['data_hora']);
        } catch (e) {}
      }
    }

    await showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(builder: (context, setStateDialog) {
            void atualizarDataVenc(DateTime d) => setStateDialog(() => dataVencimento = d);

            return AlertDialog(
                title: Text(isDivida ? "Nova Dívida" : "Novo Pagamento"),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [

                      // SELETOR DE DATA DO LANÇAMENTO
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 18, color: Colors.grey[700]),
                          SizedBox(width: 8),
                          Text("Data do Lançamento: ", style: TextStyle(fontWeight: FontWeight.bold)),
                          TextButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: dataLancamento,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2050),
                              );
                              if (picked != null) {
                                setStateDialog(() {
                                  final agora = DateTime.now();
                                  dataLancamento = DateTime(picked.year, picked.month, picked.day, agora.hour, agora.minute);
                                });
                              }
                            },
                            child: Text(DateFormat('dd/MM/yyyy').format(dataLancamento)),
                          )
                        ],
                      ),
                      Divider(),

                      TextField(controller: descricaoController, decoration: InputDecoration(labelText: "Descrição"), textCapitalization: TextCapitalization.sentences),
                      SizedBox(height: 10),
                      TextField(controller: valorController, decoration: InputDecoration(labelText: "Valor"), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, CentavosInputFormatter(moeda: true)]),

                      if (isDivida) ...[
                        SizedBox(height: 10),
                        Align(alignment: Alignment.centerLeft, child: Text("Data de Vencimento (Opcional):", style: TextStyle(fontSize: 12, color: Colors.grey))),
                        Wrap(spacing: 5, children: [
                          ActionChip(label: Text("5º Útil"), onPressed: () => atualizarDataVenc(DateTime.now().day > 5 ? _calcularQuintoDiaUtil(DateTime.now().year, DateTime.now().month + 1) : _calcularQuintoDiaUtil(DateTime.now().year, DateTime.now().month))),
                          ActionChip(label: Text("Dia 20"), onPressed: () => atualizarDataVenc(DateTime.now().day > 20 ? DateTime(DateTime.now().year, DateTime.now().month + 1, 20) : DateTime(DateTime.now().year, DateTime.now().month, 20)))
                        ]),
                        OutlinedButton(
                            onPressed: () async { final p = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030)); if (p!=null) atualizarDataVenc(p); },
                            child: Text(dataVencimento == null ? "Escolher Vencimento" : DateFormat('dd/MM/yyyy').format(dataVencimento!))
                        )
                      ]
                    ])
                ),
                actions: [
                  TextButton(onPressed: ()=>Navigator.pop(context), child: Text("Cancelar")),
                  ElevatedButton(onPressed: () async {
                    if (valorController.text.isNotEmpty) {
                      double val = UtilBrasilFields.converterMoedaParaDouble(valorController.text);
                      if (val > 0) {
                        double finalVal = isDivida ? val : -val;
                        String? dtVenc = dataVencimento != null ? DateFormat('dd/MM/yyyy').format(dataVencimento!) : null;
                        String dataLancamentoFormatada = DateFormat('dd/MM/yyyy HH:mm').format(dataLancamento);

                        if (isEdicao) {
                          await DBHelper().editarTransacao(transacaoExistente['id'], widget.pessoaId, finalVal, descricaoController.text, dtVenc, 0, 0);
                        } else {
                          await DBHelper().adicionarTransacao(
                              widget.pessoaId,
                              finalVal,
                              isDivida?'DIVIDA':'PAGAMENTO',
                              descricaoController.text,
                              dtVenc, 0, 0,
                              dataPersonalizada: dataLancamentoFormatada
                          );
                        }
                        Navigator.pop(context);
                        _carregarDados();
                      }
                    }
                  }, child: Text("Salvar"))
                ]
            );
          });
        }
    );
  }

  // --- OUTRAS FUNÇÕES ---
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

  Future<void> _gerarParcelasAutomaticas() async {
    final valorParcelarController = TextEditingController(text: UtilBrasilFields.obterReal(_saldoAtual > 0 ? _saldoAtual : 0.0));
    final qtdController = TextEditingController(text: "2");
    String tipoData = "quinto_dia";
    DateTime? dataCustomizada;

    await showDialog(
        context: context,
        builder: (ctx) {
          String previewTexto = "";
          return StatefulBuilder(
              builder: (context, setDialogState) {
                void atualizarPreview() {
                  double val = UtilBrasilFields.converterMoedaParaDouble(valorParcelarController.text);
                  int qtd = int.tryParse(qtdController.text) ?? 1;
                  if (qtd < 1) qtd = 1;
                  if (val > 0) {
                    double valParcela = val / qtd;
                    setDialogState(() {
                      previewTexto = "${qtd}x de ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(valParcela)}";
                    });
                  } else {
                    setDialogState(() => previewTexto = "");
                  }
                }
                if (previewTexto.isEmpty) atualizarPreview();

                return AlertDialog(
                  title: Text("Gerar Parcelamento"),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(controller: valorParcelarController, decoration: InputDecoration(labelText: "Valor a Parcelar", border: OutlineInputBorder()), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, CentavosInputFormatter(moeda: true)], onChanged: (_) => atualizarPreview()),
                        SizedBox(height: 10),
                        TextField(controller: qtdController, decoration: InputDecoration(labelText: "Nº de Parcelas", border: OutlineInputBorder()), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], onChanged: (_) => atualizarPreview()),
                        SizedBox(height: 10),
                        Container(width: double.infinity, padding: EdgeInsets.all(10), color: Colors.blue[50], child: Text(previewTexto, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800], fontSize: 16), textAlign: TextAlign.center)),
                        SizedBox(height: 15),
                        Text("Dia do Vencimento:", style: TextStyle(fontWeight: FontWeight.bold)),
                        RadioListTile(title: Text("5º Dia Útil"), value: "quinto_dia", groupValue: tipoData, onChanged: (v) => setDialogState(() => tipoData = v.toString())),
                        RadioListTile(title: Text("Dia 20"), value: "dia_20", groupValue: tipoData, onChanged: (v) => setDialogState(() => tipoData = v.toString())),
                        RadioListTile(title: Row(children: [Text("Outra Data: "), if (dataCustomizada != null) Text(DateFormat('dd/MM').format(dataCustomizada!), style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))]), value: "custom", groupValue: tipoData, onChanged: (v) async { final picked = await showDatePicker(context: context, initialDate: DateTime.now().add(Duration(days: 30)), firstDate: DateTime.now(), lastDate: DateTime(2030)); if (picked != null) { setDialogState(() { dataCustomizada = picked; tipoData = "custom"; }); } }),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancelar")),
                    ElevatedButton(
                      onPressed: () async {
                        int qtd = int.tryParse(qtdController.text) ?? 1;
                        if (qtd < 1) qtd = 1;
                        double valorTotal = UtilBrasilFields.converterMoedaParaDouble(valorParcelarController.text);
                        if (valorTotal <= 0) return;
                        double valorParcela = valorTotal / qtd;

                        for (int i = 1; i <= qtd; i++) {
                          DateTime dataVenc;
                          if (tipoData == 'custom' && dataCustomizada != null) {
                            if (i == 1) { dataVenc = dataCustomizada!; } else {
                              int targetMonth = dataCustomizada!.month + (i - 1);
                              int targetYear = dataCustomizada!.year;
                              if (targetMonth > 12) { targetYear += (targetMonth - 1) ~/ 12; targetMonth = (targetMonth - 1) % 12 + 1; }
                              int dia = dataCustomizada!.day;
                              int maxDia = DateTime(targetYear, targetMonth + 1, 0).day;
                              if (dia > maxDia) dia = maxDia;
                              dataVenc = DateTime(targetYear, targetMonth, dia);
                            }
                          } else {
                            DateTime dataBase = DateTime.now();
                            int mesCalculo = dataBase.month + i;
                            int anoCalculo = dataBase.year;
                            if (mesCalculo > 12) { anoCalculo += (mesCalculo - 1) ~/ 12; mesCalculo = (mesCalculo - 1) % 12 + 1; }
                            if (tipoData == 'quinto_dia') { dataVenc = _calcularQuintoDiaUtil(anoCalculo, mesCalculo); } else if (tipoData == 'dia_20') { dataVenc = DateTime(anoCalculo, mesCalculo, 20); } else { dataVenc = DateTime.now().add(Duration(days: 30 * i)); }
                          }
                          String dataFormatada = DateFormat('yyyy-MM-dd').format(dataVenc);
                          String texto = "Parcela $i/$qtd";
                          await DBHelper().adicionarAnotacao(widget.pessoaId, texto, isChecklist: true, valor: valorParcela, dataVenc: dataFormatada);
                        }
                        Navigator.pop(ctx); _carregarDados(); _tabController.animateTo(1); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Parcelas geradas!")));
                      },
                      child: Text("Gerar"),
                    )
                  ],
                );
              }
          );
        }
    );
  }

  Future<void> _adicionarNotaAvancada() async {
    final notaController = TextEditingController();
    bool isCheck = false;
    double nivelPrioridade = 0;

    await showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  title: Text("Nova Anotação"),
                  content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TextField(controller: notaController, decoration: InputDecoration(hintText: "Escreva aqui...", border: OutlineInputBorder()), minLines: 3, maxLines: 6, textCapitalization: TextCapitalization.sentences),
                    SizedBox(height: 15),
                    Row(children: [Text("Com Checkbox?"), Spacer(), Switch(value: isCheck, onChanged: (v) => setDialogState(() => isCheck = v))]),
                    SizedBox(height: 10),
                    Text("Indentação Inicial:"),
                    Slider(value: nivelPrioridade, min: 0, max: 2, divisions: 2, label: nivelPrioridade.toInt().toString(), onChanged: (v) => setDialogState(() => nivelPrioridade = v)),
                  ]),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancelar")),
                    ElevatedButton(onPressed: () async { if (notaController.text.isNotEmpty) { await DBHelper().adicionarAnotacao(widget.pessoaId, notaController.text, isChecklist: isCheck, prioridade: nivelPrioridade.toInt()); Navigator.pop(ctx); _carregarDados(); } }, child: Text("Adicionar"))
                  ],
                );
              }
          );
        }
    );
  }

  Future<void> _toggleCheckboxNota(Map<String, dynamic> nota) async {
    bool novoStatus = !(nota['is_concluido'] == 1);
    if (novoStatus == true && (nota['valor_associado'] as double) > 0) {
      bool lancarPagamento = await showDialog(context: context, builder: (ctx) => AlertDialog(title: Text("Receber Parcela?"), content: Text("Lançar pagamento no financeiro?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("Não")), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Sim"), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white))])) ?? false;
      if (lancarPagamento) { await DBHelper().adicionarTransacao(widget.pessoaId, -(nota['valor_associado']), 'PAGAMENTO', "Pgto: ${nota['texto']}", DateFormat('dd/MM/yyyy').format(DateTime.now()), 0, 0); }
    }
    await DBHelper().alternarStatusAnotacao(nota['id'], novoStatus); _carregarDados();
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _anotacoes.removeAt(oldIndex);
      _anotacoes.insert(newIndex, item);
    });
    DBHelper().atualizarOrdemAnotacoes(_anotacoes);
  }

  Future<void> _alterarPrioridade(Map<String, dynamic> nota, bool aumentar) async {
    int atual = nota['nivel_prioridade'] ?? 0;
    int novo = aumentar ? atual + 1 : atual - 1;
    if (novo < 0) novo = 0; if (novo > 2) novo = 2;
    if (novo != atual) { await DBHelper().atualizarPrioridadeAnotacao(nota['id'], novo); _carregarDados(); }
  }

  String _formatarDataExibicao(String? dataStr) {
    if (dataStr == null) return "";
    try { return DateFormat('dd/MM/yyyy').format(DateTime.parse(dataStr)); } catch (e) { return dataStr; }
  }

  Future<void> _gerarPDFParcelas() async {
    List<Map<String, dynamic>> parcelas = _anotacoes.where((n) => (n['valor_associado'] as double) > 0).toList();
    if (parcelas.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sem parcelas."))); return; }

    List<Map<String, dynamic>> itensConvertidos = parcelas.map((p) => {
      'descricao': p['texto'],
      'valor': p['valor_associado'],
      'data_vencimento': p['data_vencimento']
    }).toList();

    double total = itensConvertidos.fold(0, (sum, item) => sum + (item['valor'] as double));
    final bytes = await _gerarBytesDoPDF(itensConvertidos, total);
    await Printing.layoutPdf(onLayout: (format) async => bytes);
  }

  void _toggleSelecao(int id) { setState(() { if (_itensSelecionados.contains(id)) _itensSelecionados.remove(id); else _itensSelecionados.add(id); }); }
  Future<void> _editarCliente() async { await DBHelper().atualizarPessoa(widget.pessoaId, _nomeController.text, _telefoneController.text); }

  Future<void> _deletarCliente() async {
    bool confirmar = await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text("Tem certeza?"),
          content: Text("Isso apagará todas as dívidas, pagamentos e anotações deste cliente. Não é possível desfazer."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("Cancelar")),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text("Sim, Apagar"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            )
          ],
        )
    ) ?? false;

    if (confirmar) {
      await DBHelper().deletarPessoa(widget.pessoaId);
      Navigator.pop(context);
    }
  }

  // --- BUILD ---
  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final containerColor = isDark ? Color(0xFF1E1E1E) : Colors.white;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_nomeController.text),
        actions: [IconButton(icon: Icon(Icons.delete_forever), onPressed: _deletarCliente)],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white, labelColor: Colors.white, unselectedLabelColor: Colors.white70,
          tabs: [Tab(text: "FINANCEIRO", icon: Icon(Icons.attach_money)), Tab(text: "NOTAS & PARCELAS", icon: Icon(Icons.checklist))],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ABA 1 - Financeiro
          Column(children: [
            Container(
                padding: EdgeInsets.all(20),
                color: containerColor,
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Saldo Total", style: TextStyle(fontSize: 16)), Text(currencyFormat.format(_saldoAtual), style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: _saldoAtual > 0 ? Colors.red : Colors.green))]),
                  SizedBox(height: 10),

                  // --- BARRA DE AÇÕES ---
                  Row(children: [
                    Expanded(flex: 2, child: ElevatedButton.icon(icon: Icon(Icons.picture_as_pdf), label: Text("Ver PDF"), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], foregroundColor: Colors.white), onPressed: _visualizarPDF)),
                    SizedBox(width: 8),
                    Column(
                      children: [
                        Transform.scale(
                          scale: 0.8,
                          child: Switch(
                            value: _anexarPdfAoZap,
                            onChanged: (val) => setState(() => _anexarPdfAoZap = val),
                            activeColor: Colors.green,
                          ),
                        ),
                        Text("Anexar PDF", style: TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                    SizedBox(width: 8),
                    Expanded(flex: 3, child: ElevatedButton.icon(icon: Icon(Icons.share), label: Text("WhatsApp"), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), onPressed: _compartilharWhatsApp)),
                  ]),

                  ExpansionTile(title: Text("Editar Dados"), children: [TextField(controller: _nomeController, decoration: InputDecoration(labelText: "Nome"), onEditingComplete: _editarCliente), TextField(controller: _telefoneController, decoration: InputDecoration(labelText: "Telefone"), keyboardType: TextInputType.number, onEditingComplete: _editarCliente)])
                ])
            ),
            Expanded(child: ListView.separated(padding: EdgeInsets.all(10), itemCount: _transacoes.length, separatorBuilder: (ctx,i)=>Divider(height:1), itemBuilder: (context, index) {
              final item = _transacoes[index];
              final isDivida = (item['valor'] as double) > 0;
              final isSelected = _itensSelecionados.contains(item['id']);

              return ListTile(
                  tileColor: isSelected ? Colors.blue.withOpacity(0.1) : containerColor,
                  leading: Checkbox(value: isSelected, activeColor: isDivida?Colors.red:Colors.green, onChanged: (v)=>_toggleSelecao(item['id'])),
                  title: Text(item['descricao']??"", style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${item['data_hora']} ${item['data_vencimento']!=null?'• '+item['data_vencimento']:''}"),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(currencyFormat.format((item['valor'] as double).abs()), style: TextStyle(color: isDivida?Colors.red:Colors.green, fontWeight: FontWeight.bold)), IconButton(icon: Icon(Icons.edit, color: Colors.blue, size: 20), onPressed: () => _mostrarFormularioTransacao(transacaoExistente: item)), IconButton(icon: Icon(Icons.delete, color: Colors.grey, size: 20), onPressed: () async { await DBHelper().removerTransacao(item['id'], widget.pessoaId); _carregarDados(); })]),
                  onTap: ()=>_toggleSelecao(item['id']));
            }))
          ]),

          // ABA 2 - Notas & Parcelas
          Column(children: [
            Container(padding: EdgeInsets.all(15), color: containerColor, child: Row(children: [Expanded(child: ElevatedButton.icon(icon: Icon(Icons.splitscreen), label: Text("Parcelar"), style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white), onPressed: _gerarParcelasAutomaticas)), SizedBox(width: 10), Expanded(child: ElevatedButton.icon(icon: Icon(Icons.note_add), label: Text("Anotar"), style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white), onPressed: _adicionarNotaAvancada))])),
            if (_anotacoes.any((n) => (n['valor_associado'] as double) > 0)) Container(width: double.infinity, padding: EdgeInsets.symmetric(horizontal: 15, vertical: 5), color: Colors.yellow[100], child: TextButton.icon(icon: Icon(Icons.print, color: Colors.black), label: Text("Imprimir Carnê (Assinar)", style: TextStyle(color: Colors.black)), onPressed: _gerarPDFParcelas)),
            Expanded(
                child: ReorderableListView.builder(
                  padding: EdgeInsets.all(10),
                  itemCount: _anotacoes.length,
                  onReorder: _onReorder,
                  itemBuilder: (context, index) {
                    final nota = _anotacoes[index];
                    final isCheck = nota['is_checklist'] == 1;
                    final isDone = nota['is_concluido'] == 1;
                    final nivel = nota['nivel_prioridade'] ?? 0;
                    final valor = nota['valor_associado'] as double;

                    return Dismissible(
                      key: ValueKey(nota['id']),
                      direction: DismissDirection.horizontal,
                      confirmDismiss: (direction) async {
                        if (direction == DismissDirection.startToEnd) { await _alterarPrioridade(nota, true); } else { await _alterarPrioridade(nota, false); }
                        return false;
                      },
                      background: Container(color: Colors.blue[100], alignment: Alignment.centerLeft, padding: EdgeInsets.only(left: 20), child: Icon(Icons.format_indent_increase, color: Colors.blue)),
                      secondaryBackground: Container(color: Colors.orange[100], alignment: Alignment.centerRight, padding: EdgeInsets.only(right: 20), child: Icon(Icons.format_indent_decrease, color: Colors.orange)),

                      child: Container(
                        margin: EdgeInsets.only(bottom: 2),
                        color: containerColor,
                        child: Padding(
                          padding: EdgeInsets.only(left: (nivel * 25.0)),
                          child: ListTile(
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                            visualDensity: VisualDensity.compact,
                            leading: isCheck ? Checkbox(value: isDone, onChanged: (v) => _toggleCheckboxNota(nota)) : Icon(Icons.circle, size: 8, color: Colors.grey),
                            title: Text(nota['texto'], style: TextStyle(decoration: isDone ? TextDecoration.lineThrough : null, color: isDone ? Colors.grey : null)),
                            subtitle: valor > 0 ? Text("${_formatarDataExibicao(nota['data_vencimento'])} • ${currencyFormat.format(valor)}", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)) : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                    icon: Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                                    onPressed: () async { await DBHelper().deletarAnotacao(nota['id']); _carregarDados(); }
                                ),
                                ReorderableDragStartListener(index: index, child: Icon(Icons.drag_handle, color: Colors.grey[400])),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                )
            )
          ])
        ],
      ),
      floatingActionButton: _tabController.index == 0 ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 30), FloatingActionButton.extended(heroTag: "pg", icon: Icon(Icons.attach_money), label: Text("PAGAR"), backgroundColor: Colors.green, onPressed: () => _mostrarFormularioTransacao(isDividaNova: false)), SizedBox(width: 20), FloatingActionButton.extended(heroTag: "dv", icon: Icon(Icons.add_shopping_cart), label: Text("DÍVIDA"), backgroundColor: Colors.red, onPressed: () => _mostrarFormularioTransacao(isDividaNova: true))]) : null,
    );
  }
}