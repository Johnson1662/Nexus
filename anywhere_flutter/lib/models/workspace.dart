/// Represents a workspace (project directory) managed on the host.
class WorkspaceInfo {
  final String id;
  String name;
  String path;
  int sortOrder;

  WorkspaceInfo({
    required this.id,
    required this.name,
    required this.path,
    this.sortOrder = 0,
  });
}
