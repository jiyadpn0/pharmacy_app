class EmailItem {
  final String id;
  final String threadId;
  final String snippet;
  final String subject;
  final String from;
  final String date;

  EmailItem({
    required this.id,
    required this.threadId,
    required this.snippet,
    required this.subject,
    required this.from,
    required this.date,
  });
}
