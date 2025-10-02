class Session {
  final String accessToken;
  final String userId;
  final String? email;
  Session({required this.accessToken, required this.userId, this.email});
}
