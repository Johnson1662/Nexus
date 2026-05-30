import { MessageData } from './MessageData';
import { ChatStore, trimMessages } from './ChatState';
import { AcpUpdate, AcpToolCallContent, AcpContent } from '../websocket/WSProtocol';
import { StorageService, PrefsKeys } from '../../services/StorageService';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'MsgHandler';

export function handleAcpUpdate(u: AcpUpdate): void {
  let t: string = u.sessionUpdate;

  if (ChatStore.loadingSession &&
    (t === 'agent_message_chunk' || t === 'user_message_chunk' || t === 'tool_call')) {
    ChatStore.messages = [];
    ChatStore.planEntries = [];
    ChatStore.streamingThinking = '';
    ChatStore.turnActive = false;
  }

  if (t === 'agent_message_chunk' && u.content?.text) {
    if (ChatStore.loadingSession) {
      ChatStore.loadingSession = false;
    }
    if (ChatStore.streamingThinking.length > 0) {
      ChatStore.messages = [...ChatStore.messages, new MessageData('assistant', ChatStore.streamingThinking, 'thinking')];
      ChatStore.streamingThinking = '';
    }
    ChatStore.messages = appendText(ChatStore.messages, u.content.text);
  } else if (t === 'agent_thought_chunk' && u.content?.text) {
    ChatStore.streamingThinking += u.content.text;
  } else if (t === 'tool_call' && u.toolCallId) {
    if (ChatStore.loadingSession) {
      ChatStore.loadingSession = false;
    }
    hilog.info(DOMAIN, TAG, 'tool_call: id=' + u.toolCallId + ' title=' + (u.title || '') + ' kind=' + (u.kind || ''));
    if (ChatStore.streamingThinking.length > 0) {
      ChatStore.messages = [...ChatStore.messages, new MessageData('assistant', ChatStore.streamingThinking, 'thinking')];
      ChatStore.streamingThinking = '';
    }
    let m = new MessageData('assistant', u.title || '', 'tool_call');
    m.toolCallId = u.toolCallId;
    m.toolName = u.title || '';
    m.toolStatus = 'pending';
    m.toolKind = u.kind || '';
    ChatStore.messages = [...ChatStore.messages, m];
    hilog.info(DOMAIN, TAG, 'tool_call: card created, total msgs=' + String(ChatStore.messages.length));
  } else if (t === 'tool_call_update') {
    hilog.info(DOMAIN, TAG, 'handleAcpUpdate: tool_call_update received');
    // tool_call_update may lack toolCallId — find the most recent pending card as fallback
    let id: string = u.toolCallId || '';
    if (id.length === 0) {
      let msgs = ChatStore.messages;
      for (let i = msgs.length - 1; i >= 0; i--) {
        if (msgs[i].type === 'tool_call' && (msgs[i].toolStatus === 'pending' || msgs[i].toolStatus === 'in_progress')) {
          id = msgs[i].toolCallId;
          break;
        }
      }
      hilog.info(DOMAIN, TAG, 'tool_call_update: fallback id=' + id);
    }
    if (id.length === 0) {
      hilog.info(DOMAIN, TAG, 'tool_call_update: no id found, skipping');
      return;
    }
    // Parse content from either bridge format (toolCallContent) or agent format (content as array)
    let items: AcpToolCallContent[] | undefined = u.toolCallContent;
    if (!items) {
      hilog.info(DOMAIN, TAG, 'tool_call_update: no toolCallContent, trying agent format');
      items = getContentFromAgentFormat(u);
      hilog.info(DOMAIN, TAG, 'tool_call_update: got items=' + (items ? String(items.length) : 'undefined'));
    }
    if (!items) {
      hilog.info(DOMAIN, TAG, 'tool_call_update: items is undefined, skipping');
    }
    let contentText = '';
    let contentType = '';
    let toolPath = '';
    let oldText = '';
    let newText = '';
    let terminalId = '';
    if (items) {
      for (let i = 0; i < items.length; i++) {
        let item = items[i];
        hilog.info(DOMAIN, TAG, 'tool_call_update: item[' + i + '] type=' + String(item.type) + ' hasContent=' + String(!!item.content));
        if (item.type === 'terminal') {
          contentType = 'terminal';
          terminalId = item.terminalId || '';
        } else if (item.type === 'diff') {
          contentType = 'diff';
          toolPath = item.path || '';
          oldText = item.oldText || '';
          newText = item.newText || '';
        } else if (item.type === 'content' && contentType.length === 0) {
          contentType = 'content';
        }
        if (item.content?.text) {
          let txt = item.content.text;
          contentText += txt;
          hilog.info(DOMAIN, TAG, 'tool_call_update: got text len=' + String(txt.length) + ' total=' + String(contentText.length));
        }
      }
    }
    let status = u.status || (contentText.length > 0 ? 'completed' : 'in_progress');
    hilog.info(DOMAIN, TAG, 'tool_call_update: final contentText len=' + String(contentText.length) + ' contentType=' + contentType + ' status=' + status + ' id=' + id);
    ChatStore.messages = updateToolStatus(ChatStore.messages, id, status, contentText,
      contentType, toolPath, oldText, newText, terminalId);
    hilog.info(DOMAIN, TAG, 'tool_call_update: done');
  } else if (t === 'plan' && u.entries) {
    if (ChatStore.streamingThinking.length > 0) {
      ChatStore.messages = [...ChatStore.messages, new MessageData('assistant', ChatStore.streamingThinking, 'thinking')];
      ChatStore.streamingThinking = '';
    }
    ChatStore.planEntries = u.entries;
  } else if (t === 'user_message_chunk' && u.content?.text) {
    if (ChatStore.loadingSession) {
      ChatStore.loadingSession = false;
    }
    let prev = ChatStore.messages.length > 0 ? ChatStore.messages[ChatStore.messages.length - 1] : undefined;
    if (prev && prev.role === 'user') {
      return;
    }
    ChatStore.messages = [...ChatStore.messages, new MessageData('user', u.content.text, 'text')];
  } else if (t === 'session_info_update' && u.title) {
    ChatStore.sessionTitle = u.title;
    let targetSessionId = ChatStore.acpSessionId || ChatStore.bridgeSessionId;
    for (let i = 0; i < ChatStore.sessions.length; i++) {
      if (ChatStore.sessions[i].sessionId === targetSessionId) {
        ChatStore.sessions[i].title = u.title;
        break;
      }
    }
  } else if (t === 'config_option_update' && u.configOptions) {
    ChatStore.configOptions = u.configOptions;
  } else if (t === 'available_commands_update' && u.availableCommands) {
    ChatStore.availableCommands = u.availableCommands;
  } else if (t === 'usage_update' && u.usage) {
    ChatStore.lastUsage = u.usage;
  } else if (t === 'turn_ended') {
    if (ChatStore.streamingThinking.length > 0) {
      ChatStore.messages = [...ChatStore.messages, new MessageData('assistant', ChatStore.streamingThinking, 'thinking')];
      ChatStore.streamingThinking = '';
    }
    ChatStore.turnActive = false;
  }
  trimMessages();
}

// Agent sends tool_call_update content in the standard ACP format:
//   content: [{type: "content", content: {type: "text", text: "..."}}, {type: "diff", path: "...", oldText: "...", newText: "..."}]
// Access it through Object cast since the type doesn't include array content
function getContentFromAgentFormat(u: AcpUpdate): AcpToolCallContent[] | undefined {
  let raw = (u as Object) as Record<string, Object>;
  let content = raw['content'];
  hilog.info(DOMAIN, TAG, 'getContentFromAgentFormat: typeof content=' + typeof content + ' isArray=' + String(Array.isArray(content)));
  if (Array.isArray(content) && content.length > 0) {
    let items: AcpToolCallContent[] = [];
    for (let i = 0; i < content.length; i++) {
      let c = content[i] as Record<string, Object>;
      let type = String(c['type'] || '');
      hilog.info(DOMAIN, TAG, 'getContentFromAgentFormat: item[' + i + '] type=' + type);
      if (type === 'content' && c['content']) {
        let nested = c['content'] as Record<string, Object>;
        items.push({
          type: 'content',
          content: { type: 'text', text: String(nested['text'] || '') },
        } as AcpToolCallContent);
      } else if (type === 'diff') {
        items.push({
          type: 'diff',
          path: String(c['path'] || ''),
          oldText: String(c['oldText'] || ''),
          newText: String(c['newText'] || ''),
        } as AcpToolCallContent);
      } else if (type === 'text' && c['text']) {
        items.push({
          type: 'content',
          content: { type: 'text', text: String(c['text'] || '') },
        } as AcpToolCallContent);
      } else if (type === 'resolved' && c['content']) {
        let nested = c['content'] as Record<string, Object>;
        items.push({
          type: 'content',
          content: { type: 'text', text: String(nested['text'] || '') },
        } as AcpToolCallContent);
      } else {
        let nestedContent = c['content'] as Record<string, Object> | undefined;
        let textValue = '';
        if (nestedContent && nestedContent['text']) {
          textValue = String(nestedContent['text']);
        } else if (c['text']) {
          textValue = String(c['text']);
        }
        items.push({
          type: type,
          content: { type: 'text', text: textValue },
          path: String(c['path'] || ''),
        } as AcpToolCallContent);
      }
    }
    hilog.info(DOMAIN, TAG, 'getContentFromAgentFormat: returning ' + String(items.length) + ' items');
    return items;
  }
  hilog.info(DOMAIN, TAG, 'getContentFromAgentFormat: no array content found, keys=' + String(Object.keys(raw).join(',')));
  return undefined;
}

function appendText(msgs: MessageData[], t: string): MessageData[] {
  if (msgs.length > 0) {
    let last = msgs[msgs.length - 1];
    if (last.role === 'assistant' && last.type === 'text') {
      let u = new MessageData('assistant', last.content + t, 'text');
      u.id = last.id; u.timestamp = last.timestamp;
      let r = [...msgs]; r[r.length - 1] = u; return r;
    }
  }
  let cleaned = t.replace(/^\n+/, '');
  return [...msgs, new MessageData('assistant', cleaned, 'text')];
}

function updateToolStatus(msgs: MessageData[], id: string, s: string, c: string, contentType: string, toolPath: string,
  oldText: string, newText: string, terminalId: string): MessageData[] {
  let r = [...msgs];
  let found = false;
  for (let i = 0; i < r.length; i++) {
    if (r[i].toolCallId === id || (terminalId.length > 0 && r[i].toolCallId === terminalId)) {
      hilog.info(DOMAIN, TAG, 'updateToolStatus: found card at idx=' + String(i) + ' oldContent=' + r[i].toolContent);
      let u = new MessageData(r[i].role, r[i].content, r[i].type);
      u.id = r[i].id; u.timestamp = r[i].timestamp;
      u.toolName = r[i].toolName; u.toolStatus = s; u.toolCallId = r[i].toolCallId;
      u.toolKind = r[i].toolKind;
      u.toolContent = c.length > 0 ? c : r[i].toolContent;
      u.toolContentType = contentType.length > 0 ? contentType : r[i].toolContentType;
      u.toolPath = toolPath.length > 0 ? toolPath : r[i].toolPath;
      u.toolOldText = oldText.length > 0 ? oldText : r[i].toolOldText;
      u.toolNewText = newText.length > 0 ? newText : r[i].toolNewText;
      u.toolTerminalId = terminalId.length > 0 ? terminalId : r[i].toolTerminalId;
      r[i] = u; found = true; break;
    }
  }
  if (!found) {
    hilog.info(DOMAIN, TAG, 'updateToolStatus: card NOT FOUND for id=' + id);
  }
  if (!found && contentType.length > 0) {
    let m = new MessageData('assistant', toolPath.length > 0 ? toolPath : id, 'tool_call');
    m.toolCallId = terminalId.length > 0 ? terminalId : id;
    m.toolName = contentType === 'terminal' ? 'Terminal' : (contentType === 'diff' ? 'File change' : (id.startsWith('read:') ? 'File read' : 'Tool call'));
    m.toolStatus = s;
    m.toolKind = contentType === 'terminal' ? 'execute' : 'edit';
    m.toolContent = c;
    m.toolContentType = contentType;
    m.toolPath = toolPath;
    m.toolOldText = oldText;
    m.toolNewText = newText;
    m.toolTerminalId = terminalId;
    r = [...r, m];
    hilog.info(DOMAIN, TAG, 'updateToolStatus: created synthetic card');
  }
  return r;
}