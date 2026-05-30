class LegalTermsSection {
  final String title;
  final String body;

  const LegalTermsSection({required this.title, required this.body});
}

class LegalTerms {
  final String version;
  final String title;
  final List<String> bullets;
  final List<LegalTermsSection> sections;

  const LegalTerms({
    required this.version,
    required this.title,
    this.bullets = const [],
    this.sections = const [],
  });
}
