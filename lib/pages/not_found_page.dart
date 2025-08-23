import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.pagina_nao_encontrada),
        backgroundColor:
            Colors.red, // Red color for the AppBar to indicate an error
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(
              Icons.error_outline,
              size: 80,
              color: Colors.red, // Red color for the icon
            ),
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context)!.pagina_nao_encontrada_404,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.red, // Text color
              ),
            ),
            const SizedBox(height: 10),
            Text(
              AppLocalizations.of(context)!
                  .pagina_voce_esta_procurando_nao_existe,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(), // Go back to the previous page
              child: Text(AppLocalizations.of(context)!.voltar),
            ),
          ],
        ),
      ),
    );
  }
}
