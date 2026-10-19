class ApiRecord {
  const ApiRecord(this.json);

  final Map<String, dynamic> json;

  String get id => json['id']?.toString() ?? '';
  String get name => json['name']?.toString() ?? '';
  String get login => json['login']?.toString() ?? '';
  String get status => json['status']?.toString() ?? 'IDLE';
  String get repository => json['repository']?.toString() ?? '';
  String get title => json['title']?.toString() ?? '';
  String get body => json['body']?.toString() ?? '';
  List<Map<String, dynamic>> get stages => _records(json['stages']);
  List<Map<String, dynamic>> get accounts => _records(json['githubAccounts']);

  static List<Map<String, dynamic>> _records(Object? value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }
}