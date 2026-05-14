@ObservedV2
export class AgentConfig {
  @Trace agentType: string = 'opencode';
  @Trace model: string = '';
  @Trace modelLabel: string = '';
  @Trace mode: string = '';
}

export class AgentModel {
  modelId: string = '';
  name: string = '';
}

export class AgentMode {
  value: string = '';
  name: string = '';
}
