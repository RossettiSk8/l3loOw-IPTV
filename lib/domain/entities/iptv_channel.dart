final class IptvChannel {
  const IptvChannel({
    required this.name,
    required this.url,
    this.group,
    this.isHls = false,
  });

  final String name;
  final Uri url;
  final String? group;
  final bool isHls;
}
