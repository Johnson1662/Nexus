import React from "react";
import {
  AbsoluteFill,
  Easing,
  Img,
  interpolate,
  Sequence,
  staticFile,
  useCurrentFrame,
  Video,
} from "remotion";

// ── Scene 1: Title & Icon Reveal (0 - 2.5s / 0-75f) ──
const SceneTitle: React.FC = () => {
  const frame = useCurrentFrame();

  const iconScale = interpolate(frame, [0, 35], [0.4, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.16, 1, 0.3, 1),
  });

  const titleOpacity = interpolate(frame, [10, 40], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill
      style={{
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <div
        style={{
          scale: `${iconScale}`,
          width: 130,
          height: 130,
          borderRadius: 30,
          background: "#FFFFFF",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          boxShadow: "0 20px 50px rgba(0, 125, 255, 0.35)",
          marginBottom: 28,
        }}
      >
        <svg width="90" height="90" viewBox="0 0 128 128" fill="none">
          <line x1="64" y1="64" x2="34" y2="38" stroke="#E5E7EB" strokeWidth="6" strokeLinecap="round" />
          <line x1="64" y1="64" x2="94" y2="38" stroke="#E5E7EB" strokeWidth="6" strokeLinecap="round" />
          <line x1="64" y1="64" x2="34" y2="90" stroke="#007DFF" strokeWidth="7" strokeLinecap="round" />
          <line x1="64" y1="64" x2="94" y2="90" stroke="#007DFF" strokeWidth="7" strokeLinecap="round" />
          <circle cx="34" cy="38" r="7" fill="#9CA3AF" />
          <circle cx="94" cy="38" r="7" fill="#9CA3AF" />
          <circle cx="34" cy="90" r="9" fill="#007DFF" />
          <circle cx="94" cy="90" r="9" fill="#007DFF" />
          <circle cx="64" cy="64" r="18" fill="#111827" />
          <circle cx="64" cy="64" r="7" fill="#36B37E" />
        </svg>
      </div>

      <h1
        style={{
          opacity: titleOpacity,
          fontSize: 68,
          fontWeight: 900,
          letterSpacing: -1,
          margin: 0,
          background: "linear-gradient(135deg, #FFFFFF 0%, #9CA3AF 100%)",
          WebkitBackgroundClip: "text",
          WebkitTextFillColor: "transparent",
        }}
      >
        Nexus
      </h1>

      <p
        style={{
          opacity: titleOpacity,
          fontSize: 26,
          color: "#60A5FA",
          marginTop: 14,
          fontWeight: 600,
          letterSpacing: 1,
        }}
      >
        2026 鸿蒙高校创新赛 · 全场景远程 AI 编程助手
      </p>
    </AbsoluteFill>
  );
};

// ── Scene 2: Terminal & ACP Protocol Streaming (2.5s - 6s / 75-180f) ──
const SceneTerminal: React.FC = () => {
  const frame = useCurrentFrame();

  const windowY = interpolate(frame, [0, 30], [40, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.16, 1, 0.3, 1),
  });

  const typingChars = Math.floor(
    interpolate(frame, [10, 80], [0, 140], { extrapolateRight: "clamp" })
  );

  const fullCode =
    'nexus connect --target "192.168.3.143:12138" --agent omp\n[ACP] WebSocket connected to Bridge Server\n[ACP] Session initialized: oh-my-pi v17.1.1\n[Stream] Refactoring SessionManager.mts (101 tests passed)...';

  return (
    <AbsoluteFill
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <div
        style={{
          translate: `0px ${windowY}px`,
          width: 920,
          height: 480,
          borderRadius: 20,
          background: "#18181B",
          border: "1px solid #27272A",
          boxShadow: "0 30px 60px rgba(0,0,0,0.6)",
          overflow: "hidden",
        }}
      >
        <div
          style={{
            height: 44,
            background: "#09090B",
            display: "flex",
            alignItems: "center",
            paddingLeft: 20,
            gap: 10,
            borderBottom: "1px solid #27272A",
          }}
        >
          <div style={{ width: 12, height: 12, borderRadius: "50%", background: "#EF4444" }} />
          <div style={{ width: 12, height: 12, borderRadius: "50%", background: "#F59E0B" }} />
          <div style={{ width: 12, height: 12, borderRadius: "50%", background: "#10B981" }} />
          <span style={{ marginLeft: 16, fontSize: 13, color: "#71717A", fontFamily: "monospace" }}>
            Nexus ACP Protocol Stream -- bash
          </span>
        </div>

        <div
          style={{
            padding: 28,
            fontFamily: "Menlo, Monaco, Consolas, monospace",
            fontSize: 21,
            lineHeight: 1.6,
            color: "#34D399",
            whiteSpace: "pre-wrap",
          }}
        >
          {fullCode.slice(0, typingChars)}
          <span
            style={{
              display: "inline-block",
              width: 12,
              height: 24,
              background: "#60A5FA",
              marginLeft: 4,
              verticalAlign: "middle",
              opacity: frame % 16 < 8 ? 1 : 0,
            }}
          />
        </div>
      </div>
    </AbsoluteFill>
  );
};

// ── Scene 3: REAL PHONE SCREEN MOCKUP & DEMO RECORDING (6s - 11s / 180-330f) ──
const ScenePhoneMockup: React.FC = () => {
  const frame = useCurrentFrame();

  const phoneY = interpolate(frame, [0, 35], [80, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.16, 1, 0.3, 1),
  });

  const badge1Opacity = interpolate(frame, [30, 50], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const badge2Opacity = interpolate(frame, [60, 80], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        gap: 60,
      }}
    >
      {/* Phone Mockup Frame */}
      <div
        style={{
          translate: `0px ${phoneY}px`,
          width: 360,
          height: 720,
          background: "#000000",
          borderRadius: 48,
          padding: 12,
          border: "4px solid #374151",
          boxShadow: "0 25px 60px rgba(0, 125, 255, 0.25), inset 0 0 0 2px rgba(255,255,255,0.1)",
          position: "relative",
          display: "flex",
          flexDirection: "column",
        }}
      >
        {/* Dynamic Island / Punch Hole */}
        <div
          style={{
            position: "absolute",
            top: 20,
            left: "50%",
            transform: "translateX(-50%)",
            width: 90,
            height: 22,
            background: "#18181B",
            borderRadius: 20,
            zIndex: 10,
          }}
        />

        {/* Screen Container */}
        <div
          style={{
            flex: 1,
            borderRadius: 38,
            overflow: "hidden",
            background: "#FAFAFA",
            position: "relative",
            display: "flex",
            flexDirection: "column",
          }}
        >
          {/* Status Bar */}
          <div
            style={{
              height: 48,
              padding: "16px 24px 0",
              display: "flex",
              justifyContent: "space-between",
              fontSize: 12,
              fontWeight: 700,
              color: "#111827",
            }}
          >
            <span>09:41</span>
            <span>5G 100%</span>
          </div>

          {/* Screen Content: Renders UI simulation & Real Device Demo */}
          <div style={{ flex: 1, position: "relative", overflow: "hidden" }}>
            {/* Simulated UI Overlay & Real Screen Recording Container */}
            <div
              style={{
                position: "absolute",
                inset: 0,
                background: "#FAFAFA",
                padding: 16,
                display: "flex",
                flexDirection: "column",
                gap: 12,
              }}
            >
              {/* Header Host Chip */}
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 6,
                  padding: "6px 12px",
                  background: "#EFF6FF",
                  borderRadius: 20,
                  width: "fit-content",
                }}
              >
                <div style={{ width: 6, height: 6, borderRadius: "50%", background: "#10B981" }} />
                <span style={{ fontSize: 12, fontWeight: 700, color: "#1E40AF" }}>
                  LAPTOP-3FLH46E9
                </span>
              </div>

              {/* Title Section */}
              <div style={{ fontSize: 18, fontWeight: 800, color: "#111827", marginTop: 4 }}>
                最近会话
              </div>

              {/* Session Cards */}
              <div
                style={{
                  background: "#FFFFFF",
                  padding: 14,
                  borderRadius: 14,
                  border: "1px solid #E5E7EB",
                  display: "flex",
                  alignItems: "center",
                  gap: 10,
                }}
              >
                <div style={{ width: 8, height: 8, borderRadius: "50%", background: "#10B981" }} />
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 13, fontWeight: 700, color: "#111827" }}>
                    重构 SessionManager 模块
                  </div>
                  <div style={{ fontSize: 11, color: "#6B7280" }}>oh-my-pi · 进行中 · 刚刚</div>
                </div>
              </div>

              <div
                style={{
                  background: "#FFFFFF",
                  padding: 14,
                  borderRadius: 14,
                  border: "1px solid #E5E7EB",
                  display: "flex",
                  alignItems: "center",
                  gap: 10,
                }}
              >
                <div style={{ width: 8, height: 8, borderRadius: "50%", background: "#F59E0B" }} />
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 13, fontWeight: 700, color: "#111827" }}>
                    盘古天气算法测试
                  </div>
                  <div style={{ fontSize: 11, color: "#6B7280" }}>opencode · 等待输入 · 5分钟前</div>
                </div>
              </div>

              {/* Chat Preview */}
              <div
                style={{
                  marginTop: 10,
                  background: "#18181B",
                  color: "#34D399",
                  padding: 12,
                  borderRadius: 12,
                  fontSize: 11,
                  fontFamily: "monospace",
                }}
              >
                [AI] 已在测试集中新增 14 条断言，断言总数 101 项全过 ✓
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Feature Callouts Beside Phone */}
      <div style={{ display: "flex", flexDirection: "column", gap: 24, width: 420 }}>
        <div
          style={{
            opacity: badge1Opacity,
            background: "rgba(24, 24, 27, 0.9)",
            border: "1px solid #2563EB",
            borderRadius: 20,
            padding: 20,
            boxShadow: "0 10px 30px rgba(0, 125, 255, 0.2)",
          }}
        >
          <div style={{ fontSize: 16, fontWeight: 800, color: "#60A5FA" }}>
            ✦ 真实多端连接与会话状态
          </div>
          <p style={{ fontSize: 13, color: "#D1D5DB", marginTop: 6, lineHeight: 1.5 }}>
            通过 WebSocket 实时间隔监测与磁盘状态扫描，精准判定“进行中”与“等待输入”，全增量事件流渲染。
          </p>
        </div>

        <div
          style={{
            opacity: badge2Opacity,
            background: "rgba(24, 24, 27, 0.9)",
            border: "1px solid #10B981",
            borderRadius: 20,
            padding: 20,
            boxShadow: "0 10px 30px rgba(16, 185, 129, 0.2)",
          }}
        >
          <div style={{ fontSize: 16, fontWeight: 800, color: "#34D399" }}>
            ✦ 鸿蒙 Flutter 原生高性能渲染
          </div>
          <p style={{ fontSize: 13, color: "#D1D5DB", marginTop: 6, lineHeight: 1.5 }}>
            采用 MarkdownBody 解决全局手势争抢，配合 HostStore 自动候选 IP 去重归并。
          </p>
        </div>
      </div>
    </AbsoluteFill>
  );
};

// ── Scene 4: HarmonyOS Kit Showcase & Outro (11s - 15s / 330-450f) ──
const SceneOutro: React.FC = () => {
  const frame = useCurrentFrame();

  const opacity = interpolate(frame, [0, 20], [0, 1], { extrapolateRight: "clamp" });

  return (
    <AbsoluteFill
      style={{
        opacity,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <h1 style={{ fontSize: 60, fontWeight: 900, color: "#FFF", margin: 0 }}>Nexus</h1>
      <p style={{ fontSize: 24, color: "#10B981", marginTop: 16, fontWeight: 600 }}>
        让全场景远程 AI 编程触手可及
      </p>
      <div
        style={{
          marginTop: 40,
          padding: "12px 30px",
          borderRadius: 30,
          background: "#18181B",
          border: "1px solid #007DFF",
          color: "#60A5FA",
          fontSize: 16,
          fontWeight: 700,
        }}
      >
        2026“中国高校计算机大赛——人工智能创意赛”鸿蒙赛道
      </div>
    </AbsoluteFill>
  );
};

// ── Main Composition Entry ──
export const MyComposition: React.FC = () => {
  return (
    <AbsoluteFill
      style={{
        backgroundColor: "#09090B",
        color: "#FFFFFF",
        fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
      }}
    >
      <div
        style={{
          position: "absolute",
          width: 900,
          height: 900,
          borderRadius: "50%",
          background: "radial-gradient(circle, rgba(0, 125, 255, 0.16) 0%, rgba(0,0,0,0) 70%)",
          top: "50%",
          left: "50%",
          transform: "translate(-50%, -50%)",
        }}
      />

      <Sequence name="Title" from={0} durationInFrames={75}>
        <SceneTitle />
      </Sequence>

      <Sequence name="Terminal" from={65} durationInFrames={115}>
        <SceneTerminal />
      </Sequence>

      <Sequence name="PhoneMockup" from={170} durationInFrames={160}>
        <ScenePhoneMockup />
      </Sequence>

      <Sequence name="Outro" from={320} durationInFrames={130}>
        <SceneOutro />
      </Sequence>
    </AbsoluteFill>
  );
};
