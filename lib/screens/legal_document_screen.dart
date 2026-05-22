import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum LegalDocumentType { terms, privacy }

extension LegalDocumentTypeLabel on LegalDocumentType {
  String get title {
    switch (this) {
      case LegalDocumentType.terms:
        return '이용약관';
      case LegalDocumentType.privacy:
        return '개인정보 처리방침';
    }
  }

  String get assetPath {
    switch (this) {
      case LegalDocumentType.terms:
        return 'assets/legal/terms.md';
      case LegalDocumentType.privacy:
        return 'assets/legal/privacy.md';
    }
  }
}

Future<void> openLegalDocument(BuildContext context, LegalDocumentType type) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => LegalDocumentScreen(type: type)),
  );
}

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.type});

  final LegalDocumentType type;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(type.title)),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(type.assetPath),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '${type.title}을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, height: 1.5),
                ),
              ),
            );
          }

          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              children: [
                SelectableText(
                  snapshot.data!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.55, fontSize: 14),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
