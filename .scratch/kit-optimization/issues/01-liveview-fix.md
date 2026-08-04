# 01 — LiveViewKit 修复：补全 nodeIcons + sequence 递增 + start/update 分离

**What to build:** 修复 ArkTS 侧 `LiveViewHelper.ets`，使实况窗能在锁屏/状态栏正确显示进度胶囊。用户点击 KitTestPage 的"测试 LiveView"按钮后，状态栏应出现带进度条的实况窗胶囊，显示百分比和状态文字。

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `layoutData` 包含 `nodeIcons: [$r('app.media.app_icon')]`
- [ ] 维护 `sequenceCounter`，每次调用递增
- [ ] 首次调用使用 `startLiveView()`，后续使用 `updateLiveView()`，通过 `isLiveViewActive` 标志区分
- [ ] `stopLiveView()` 重置 `isLiveViewActive = false` 和 `sequenceCounter = 0`
- [ ] hilog 中不再出现 error 401 或 `nodeIcons` 相关错误
