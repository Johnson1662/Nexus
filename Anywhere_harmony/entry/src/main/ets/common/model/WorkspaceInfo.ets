@ObservedV2
export class WorkspaceInfo {
  @Trace id: string = '';
  @Trace name: string = '';
  @Trace path: string = '';
  sessions: ServerSession[] = [];
}

export class ServerSession {
  sessionId: string = '';
  cwd: string = '';
  title: string = '';
  updatedAt: string = '';
}

@ObservedV2
export class WorkspaceStoreModel {
  @Trace workspaces: WorkspaceInfo[] = [];
  @Trace currentIndex: number = -1;
  @Trace showDrawer: boolean = false;
}

export const WorkspaceStore: WorkspaceStoreModel = new WorkspaceStoreModel();
