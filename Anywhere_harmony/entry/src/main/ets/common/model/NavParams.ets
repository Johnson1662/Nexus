import { ServerSession } from './WorkspaceInfo';

/** navStack.pushPath 的参数类型 */
export class AgentDetailParam {
  index: number = 0;
}

export class SessionDetailParam {
  session: ServerSession = new ServerSession();
}

export class ChatParam {
  // 预留扩展
}

export class OnboardingParam {
  // 预留扩展
}

export class AgentManageParam {
  deviceIndex: number = 0;
}
