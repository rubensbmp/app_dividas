import 'package:flutter/widgets.dart';

// O iOS exige sharePositionOrigin não-zero e dentro da tela para abrir a folha de
// compartilhamento. Usa o tamanho da tela (e não um BuildContext) porque algumas
// chamadas acontecem logo após fechar um diálogo. No Android o valor é ignorado.
Rect origemCompartilhamento() {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final tamanho = view.physicalSize / view.devicePixelRatio;
  return Rect.fromLTWH(0, 0, tamanho.width, tamanho.height / 2);
}
