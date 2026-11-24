-- Seed a review session into a freshly installed Minis simulator build.
--
-- Why this exists: a brand-new simulator has an empty chat database, so the
-- screenshot only ever showed the first-run checklist. Rendering a real
-- conversation needs rows, and the app exposes no debug RPC that writes (its
-- `debug.db.query` calls assertReadOnlySQL), so the CI job writes the SQLite
-- file directly between two launches.
--
-- Column notes, all verified against src/ios/Agent/Chat:
--   * sessions.model_id is NOT NULL (ChatStore+Schema.swift:39).
--   * messages.parts_json is NOT NULL and must decode as [ContentPart]
--     (ChatStoreModels.swift:274): [{"type":"text","value":"..."}].
--   * messages.part_flags is a device-local bitmask, bit0 = hasText,
--     bit1 = hasToolUse. listSessions() filters its preview subqueries on it,
--     so a row with part_flags = 0 is invisible to the session list.
--   * messages.reasoning_content becomes the collapsed thinking block that
--     toRawMessage prepends (RawMessage+Conversion.swift:329).
--   * Role values are exactly 'user' / 'assistant' (MessageRole).
--
-- Keep every literal inside single quotes and free of apostrophes: the whole
-- file is fed to `sqlite3` verbatim.

PRAGMA journal_mode = WAL;

DELETE FROM messages WHERE session_id IN ('seed-review-session', 'seed-notes-session', 'seed-ci-session');
DELETE FROM sessions WHERE id IN ('seed-review-session', 'seed-notes-session', 'seed-ci-session');

-- Session 1: the one the screenshots open. Perfect-case chat: thinking block,
-- a tool capsule with a paired result, markdown with a table and a code fence.
INSERT INTO sessions (id, title, model_id, created_at, updated_at, memory_enabled, preview_text, preview_sort_order)
VALUES (
  'seed-review-session',
  '排版评审 · 云模拟器',
  'claude-sonnet-4-5',
  strftime('%s','now') - 540,
  strftime('%s','now'),
  1,
  '两套几何在打架，改法是把常量收敛到一处',
  2
);

INSERT INTO messages (id, session_id, role, parts_json, created_at, token_usage, sort_order, updated_at, part_flags, model_id)
VALUES (
  'seed-msg-0',
  'seed-review-session',
  'user',
  '[{"type":"text","value":"帮我看下这个聊天界面：行高一直在跳，工具卡片也显得脏。顺便说说你打算怎么改。"}]',
  strftime('%s','now') - 540,
  NULL,
  0,
  strftime('%s','now') - 540,
  1,
  NULL
);

INSERT INTO messages (id, session_id, role, parts_json, created_at, token_usage, sort_order, updated_at, part_flags, model_id, reasoning_content)
VALUES (
  'seed-msg-1',
  'seed-review-session',
  'assistant',
  '[{"type":"text","value":"行高会跳，是因为同一行的尺寸被两套系统同时决定：MessageListLayout 用手抄常量预测一遍，SwiftUI 又自己量一遍。两边只要不一致，滚动时就会跳。我先把两份值取出来对比。"},{"type":"toolUse","value":{"toolUseId":"tool_seed_1","name":"shell_execute","input":"{\"command\":\"grep -rn itemSpacing src/ios/Agent/MessageList | head -20\"}","description":"查找布局常量"}},{"type":"toolResult","value":{"toolUseId":"tool_seed_1","output":"MessageListLayout.swift:1068: var itemSpacing: CGFloat = 8\nMessageListLayout.swift:1069: let estimatedHeaderHeight: CGFloat = 26\nMessageListInfrastructure.swift:1090: messageListLayout.itemSpacing = 8","success":true,"status":"success"}}]',
  strftime('%s','now') - 480,
  NULL,
  1,
  strftime('%s','now') - 480,
  3,
  'claude-sonnet-4-5',
  '先把行高的产地找全。MessageListLayout 里手抄了一份常量，SwiftUI 自己还会量一份，两套几何同时管同一行就会跳。'
);

INSERT INTO messages (id, session_id, role, parts_json, created_at, token_usage, sort_order, updated_at, part_flags, model_id, reasoning_content)
VALUES (
  'seed-msg-2',
  'seed-review-session',
  'assistant',
  '[{"type":"text","value":"## 结论\n两套几何在打架。改法是把常量收敛到一处，而不是再补一份估算。\n\n- 行高常量只留 AssistantHeaderMetrics 一处\n- 渲染与估算共用同一个宽度常量\n- 字号跟随系统设置，不再写死 pt\n\n| 位置 | 现状 | 改法 |\n| --- | --- | --- |\n| 助手头估价 | 26 | 30，与实测一致 |\n| 输入栏内距 | 12 | 16 |\n| 工具卡片底色 | 默认灰 | ChatColors.toolBg |\n\n```swift\nstruct AssistantHeaderMetrics {\n    static let height: CGFloat = 30\n    static let iconSize: CGFloat = 22\n}\n```\n\n改完之后滚动应该稳了，工具卡片也不会再显脏。"}]',
  strftime('%s','now') - 420,
  NULL,
  2,
  strftime('%s','now') - 420,
  1,
  'claude-sonnet-4-5',
  '表格和代码块要一起验证排版，做到一次截图就能看出行距、缩进和底色。'
);

INSERT INTO messages (id, session_id, role, parts_json, created_at, token_usage, sort_order, updated_at, part_flags, model_id)
VALUES (
  'seed-msg-3',
  'seed-review-session',
  'user',
  '[{"type":"text","value":"那会话列表每一行的头像呢？我想给每个会话单独设一个。"}]',
  strftime('%s','now') - 60,
  NULL,
  3,
  strftime('%s','now') - 60,
  1,
  NULL
);

-- Sessions 2 and 3: only there so the sidebar has more than one row and the
-- grouping / ordering logic has something to draw.
INSERT INTO sessions (id, title, model_id, created_at, updated_at, memory_enabled, preview_text, preview_sort_order)
VALUES
  ('seed-notes-session', '提交记录整理', 'claude-sonnet-4-5',
   strftime('%s','now') - 86400, strftime('%s','now') - 3600, 1,
   '五个提交合成一个，信息量别丢', 1),
  ('seed-ci-session', '云构建排错', 'claude-sonnet-4-5',
   strftime('%s','now') - 172800, strftime('%s','now') - 7200, 1,
   '缓存要连 frameworks 一起存，key 也得升版', 1);

INSERT INTO messages (id, session_id, role, parts_json, created_at, token_usage, sort_order, updated_at, part_flags, model_id)
VALUES
  ('seed-notes-0', 'seed-notes-session', 'user',
   '[{"type":"text","value":"这五个提交能不能合成一个？"}]',
   strftime('%s','now') - 90000, NULL, 0, strftime('%s','now') - 90000, 1, NULL),
  ('seed-notes-1', 'seed-notes-session', 'assistant',
   '[{"type":"text","value":"能。五个提交里两个是修同一个错，合并后信息量别丢，把原因写进提交正文。"}]',
   strftime('%s','now') - 3600, NULL, 1, strftime('%s','now') - 3600, 1, 'claude-sonnet-4-5'),
  ('seed-ci-0', 'seed-ci-session', 'user',
   '[{"type":"text","value":"云端又绿了但截图是桌面，怎么查？"}]',
   strftime('%s','now') - 86400, NULL, 0, strftime('%s','now') - 86400, 1, NULL),
  ('seed-ci-1', 'seed-ci-session', 'assistant',
   '[{"type":"text","value":"先看 launch.log 里有没有 Fatal error。进程崩了 simctl io 照样能拍到桌面，所以绿不等于活着。"}]',
   strftime('%s','now') - 7200, NULL, 1, strftime('%s','now') - 7200, 1, 'claude-sonnet-4-5');

SELECT id, title, preview_text FROM sessions ORDER BY updated_at DESC;
