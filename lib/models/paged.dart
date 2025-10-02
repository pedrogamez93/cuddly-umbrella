class Paged<T> {
  final int currentPage;
  final List<T> data;
  final int? total;
  final int? lastPage;
  final int? perPage;

  Paged({
    required this.currentPage,
    required this.data,
    this.total,
    this.lastPage,
    this.perPage,
  });
}
