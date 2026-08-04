import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/theme.dart';
import '../providers/chat_provider.dart';
import '../utils/agent_utils.dart';
import '../widgets/agent_logo.dart';

class NewSessionWizard extends StatefulWidget {
  const NewSessionWizard({super.key});

  @override
  State<NewSessionWizard> createState() => _NewSessionWizardState();
}

class _NewSessionWizardState extends State<NewSessionWizard>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // Selections
  int _selectedWorkspaceIndex = -1;
  int _selectedAgentIndex = -1;
  final TextEditingController _taskController = TextEditingController();

  @override
  void dispose() {
    _pageController.dispose();
    _taskController.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    if (step < 0 || step > 2) return;
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _onStart() {
    final chatProvider = context.read<ChatProvider>();
    final workspaceProvider = context.read<WorkspaceProvider>();

    // Set workspace and agent selections
    if (_selectedWorkspaceIndex >= 0 &&
        _selectedWorkspaceIndex < workspaceProvider.workspaces.length) {
      workspaceProvider.selectWorkspace(_selectedWorkspaceIndex);
      chatProvider.setCurrentWorkspace(
        workspaceProvider.workspaces[_selectedWorkspaceIndex]['path'] ?? '',
      );
    }

    if (_selectedAgentIndex >= 0 &&
        _selectedAgentIndex < chatProvider.state.agentNames.length) {
      chatProvider.selectAgent(
        chatProvider.state.agentNames[_selectedAgentIndex],
      );
    }

    // Send the task as a start message
    final task = _taskController.text.trim();
    if (task.isNotEmpty) {
      chatProvider.sendMessage(task);
    }

    Navigator.pushReplacementNamed(context, '/chat');
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final workspaceProvider = context.watch<WorkspaceProvider>();

    final workspaces = workspaceProvider.workspaces;
    final agents = chatProvider.state.agentNames;
    final isConnected = chatProvider.state.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('新建会话'),
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => _goToStep(_currentStep - 1),
              )
            : null,
      ),
      body: Column(
        children: [
          // Step indicator
          _buildStepIndicator(),
          const SizedBox(height: AppSpacing.sm),

          // Page content
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildStepWorkspace(context, workspaces),
                _buildStepAgent(context, agents),
                _buildStepTask(context, chatProvider, workspaces, agents),
              ],
            ),
          ),

          // Bottom navigation
          _buildBottomNav(
            context,
            isConnected,
            workspaces.isNotEmpty || !isConnected,
          ),
        ],
      ),
    );
  }

  // ── Step Indicator ──

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          _stepDot(0, '工作区'),
          Expanded(child: _stepLine(0)),
          _stepDot(1, 'Agent'),
          Expanded(child: _stepLine(1)),
          _stepDot(2, '任务'),
        ],
      ),
    );
  }

  Widget _stepDot(int step, String label) {
    final isActive = _currentStep == step;
    final isCompleted = _currentStep > step;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isCompleted
                  ? AppColors.success
                  : isActive
                      ? AppColors.accent
                      : AppColors.foregroundM(context).withAlpha(50),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: isCompleted
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : Text(
                    '${step + 1}',
                    style: TextStyle(
                      fontSize: AppFontSize.sm,
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? Colors.white
                          : AppColors.foregroundM(context),
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: TextStyle(
              fontSize: AppFontSize.xxs,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              color: isActive
                  ? AppColors.foregroundC(context)
                  : AppColors.foregroundM(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepLine(int fromStep) {
    final isCompleted = _currentStep > fromStep;
    return Container(
      height: 2,
      margin: const EdgeInsets.only(bottom: 18),
      color: isCompleted ? AppColors.success : AppColors.border,
    );
  }

  // ── Step 1: Workspace ──

  Widget _buildStepWorkspace(
    BuildContext context,
    List<Map<String, String>> workspaces,
  ) {
    if (workspaces.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open,
              size: 48,
              color: AppColors.foregroundM(context).withAlpha(80),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '暂无可用工作区',
              style: TextStyle(
                color: AppColors.foregroundM(context),
                fontSize: AppFontSize.md,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '请先连接主机并创建工作区',
              style: TextStyle(
                color: AppColors.foregroundM(context),
                fontSize: AppFontSize.sm,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '选择工作区',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '选择要使用的项目工作区',
            style: TextStyle(
              color: AppColors.foregroundM(context),
              fontSize: AppFontSize.sm,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: ListView.builder(
              itemCount: workspaces.length,
              itemBuilder: (context, index) {
                final w = workspaces[index];
                final name = w['name'] ??
                    (w['path']?.split(RegExp(r'[/\\]')).lastOrNull ?? '未命名');
                final path = w['path'] ?? '';
                final isSelected = _selectedWorkspaceIndex == index;

                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Material(
                    color: isSelected
                        ? AppColors.accentLight
                        : AppColors.surface1(context),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: () =>
                          setState(() => _selectedWorkspaceIndex = index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.lg,
                        ),
                        child: Row(
                          children: [
                            Radio<int>(
                              value: index,
                              groupValue: _selectedWorkspaceIndex,
                              onChanged: (v) =>
                                  setState(() => _selectedWorkspaceIndex = v!),
                              activeColor: AppColors.accent,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name.isNotEmpty ? name : '未命名',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: AppSpacing.xxs),
                                  Text(
                                    path,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.folder,
                              size: 20,
                              color: isSelected
                                  ? AppColors.accent
                                  : AppColors.foregroundM(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 2: Agent ──

  Widget _buildStepAgent(
    BuildContext context,
    List<String> agents,
  ) {
    if (agents.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 48,
              color: AppColors.foregroundM(context).withAlpha(80),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '暂无可用 Agent',
              style: TextStyle(
                color: AppColors.foregroundM(context),
                fontSize: AppFontSize.md,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '请先在 Agent 管理中安装 Agent',
              style: TextStyle(
                color: AppColors.foregroundM(context),
                fontSize: AppFontSize.sm,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '选择 Agent',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '选择要使用的 AI Agent',
            style: TextStyle(
              color: AppColors.foregroundM(context),
              fontSize: AppFontSize.sm,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: ListView.builder(
              itemCount: agents.length,
              itemBuilder: (context, index) {
                final agent = agents[index];
                final isSelected = _selectedAgentIndex == index;

                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Material(
                    color: isSelected
                        ? AppColors.accentLight
                        : AppColors.surface1(context),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: () => setState(() => _selectedAgentIndex = index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.lg,
                        ),
                        child: Row(
                          children: [
                            Radio<int>(
                              value: index,
                              groupValue: _selectedAgentIndex,
                              onChanged: (v) =>
                                  setState(() => _selectedAgentIndex = v!),
                              activeColor: AppColors.accent,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AgentUtils.getDisplayName(agent),
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            AgentLogo(
                              agentName: agent,
                              size: 20,
                              color: isSelected
                                  ? AppColors.accent
                                  : AppColors.foregroundM(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 3: Task + Summary ──

  Widget _buildStepTask(
    BuildContext context,
    ChatProvider chatProvider,
    List<Map<String, String>> workspaces,
    List<String> agents,
  ) {
    final workspaceName = _selectedWorkspaceIndex >= 0 &&
            _selectedWorkspaceIndex < workspaces.length
        ? (workspaces[_selectedWorkspaceIndex]['name'] ??
            workspaces[_selectedWorkspaceIndex]['path']
                ?.split(RegExp(r'[/\\]'))
                .lastOrNull ??
            '未选择')
        : '未选择';

    final agentName =
        _selectedAgentIndex >= 0 && _selectedAgentIndex < agents.length
            ? agents[_selectedAgentIndex]
            : '未选择';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '任务描述',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '描述你想让 AI 完成的任务',
            style: TextStyle(
              color: AppColors.foregroundM(context),
              fontSize: AppFontSize.sm,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Task text area
          SizedBox(
            height: 120,
            child: TextField(
              controller: _taskController,
              maxLines: 5,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: '例如: 帮我创建一个 Flutter 登录页面...',
                alignLabelWithHint: true,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Summary card
          _buildSummaryCard(
            context,
            chatProvider,
            workspaceName,
            agentName,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    ChatProvider chatProvider,
    String workspaceName,
    String agentName,
  ) {
    final isConnected = chatProvider.state.connected;

    return Material(
      color: AppColors.surface1(context),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '会话摘要',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isConnected ? AppColors.success : AppColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  isConnected ? '已连接' : '未连接',
                  style: TextStyle(
                    fontSize: AppFontSize.xxs,
                    color: isConnected ? AppColors.success : AppColors.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const Divider(height: AppSpacing.xl),
            _summaryRow('工作区', workspaceName, Icons.folder_outlined),
            const SizedBox(height: AppSpacing.sm),
            _summaryRow('Agent', agentName, Icons.smart_toy_outlined),
            if (chatProvider.lastModelId.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _summaryRow('Model', chatProvider.lastModelId, Icons.memory),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.foregroundM(context)),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: TextStyle(
            fontSize: AppFontSize.sm,
            color: AppColors.foregroundM(context),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: AppFontSize.sm,
              color: AppColors.foregroundC(context),
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ── Bottom Navigation ──

  Widget _buildBottomNav(
    BuildContext context,
    bool isConnected,
    bool hasWorkspaces,
  ) {
    final isWorkspaceStep = _currentStep == 0;
    final isAgentStep = _currentStep == 1;
    final isTaskStep = _currentStep == 2;
    final isFirstStep = isWorkspaceStep;
    final isLastStep = isTaskStep;

    final canProceed = isWorkspaceStep
        ? _selectedWorkspaceIndex >= 0
        : isAgentStep
            ? _selectedAgentIndex >= 0
            : _taskController.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: AppColors.backgroundCtx(context),
        border: Border(
          top: BorderSide(
            color: AppColors.border.withAlpha(80),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (!isFirstStep)
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _goToStep(_currentStep - 1),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.foregroundC(context),
                    side: BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  ),
                  child: const Text('上一步'),
                ),
              ),
            if (!isFirstStep) const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 2,
              child: isLastStep
                  ? ElevatedButton(
                      onPressed: (canProceed && isConnected) ? _onStart : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppColors.foregroundM(context).withAlpha(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                      ),
                      child: const Text(
                        '开始',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: AppFontSize.md,
                        ),
                      ),
                    )
                  : ElevatedButton(
                      onPressed:
                          canProceed ? () => _goToStep(_currentStep + 1) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppColors.foregroundM(context).withAlpha(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                      ),
                      child: const Text(
                        '下一步',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: AppFontSize.md,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
