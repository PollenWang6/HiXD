# HiXD · API 26（HarmonyOS 7）适配 TODO

> 状态：已开工（分支 `feature/api26`，`build-profile.json5` 的 `targetSdkVersion` 已切到 `26.0.0`）。最后更新：2026-07-09
> 目标：梳理 HarmonyOS 7 / API 26 中与 HiXD 相关的可用新特性，并给出分阶段采纳路线。
>
> **本期范围（2026-07-09 收口）**：已落地 = 编译目标切 API26 + 通知设置入口（Tier1 #3）+ 首登课表/主题色/滑块遮罩等修复；**`@Reusable` 复用池（#2）已移出计划**；Tier 2/3 全部为候选 backlog，非本期承诺，按需评估。演示 HAP（feature/api26 构建）已装演示设备。

---

## 0. 背景与现状

- **API 26 = HarmonyOS 26.0.0（Beta1，API level 26）**。版本号从 26.0.0 起改为 **纯 SemVer `X.Y.Z`**（不再带 `(N)` 后缀）。
- 本地 SDK 事实（读 `E:/HUAWEI/DevEco Studio/sdk/default/sdk-pkg.json` 确认）：`apiVersion="26"`、`displayName="HarmonyOS 26.0.0"`、`platformVersion="26.0.0"`、`version="26.0.0.23"`、`releaseType="Beta1"`。
- 工程已切换（分支 `feature/api26`，见 `build-profile.json5`）：
  - `targetSdkVersion: 26.0.0`（纯 SemVer，已改；旧写 `26.0.0(26)` 为误，已纠正）
  - `compatibleSdkVersion: 6.0.2(22)`（保持低位，兼容老设备；⚠️ 新旧格式混用，DevEco 26 首编若报格式错，按报错把 compatible 也升到 SemVer 或对齐 `26.0.0`，但会缩小支持设备范围）
  - → 编译目标 **API 26**，新特性用 `canIUse` / `API_VERSION >= 26` 守卫。

### 升级前置条件
- 需 **DevEco Studio 26.0.0 Beta1**（26.0.0.461）方可编译目标 API 26。
- 26.0.0 目前仍为 **Beta1**：正式上架有风险，建议在独立分支试验，勿动主分支。

---

## 1. 升级步骤（一次性）

1. 从 `main` 切出分支 `feature/api26`（✅ 已完成；当前 9 个 API23 修复随分支带出）。
2. 使用 DevEco Studio 26.0.0 Beta1 打开工程。
3. 修改 `build-profile.json5`（✅ `targetSdkVersion` 已完成）：
   - `targetSdkVersion` 改为 `26.0.0`（纯 SemVer，已确认；非 `26.0.0(26)`）。
   - **`compatibleSdkVersion` 保持低位** `6.0.2(22)` 以兼容老设备；新 API 用 `canIUse('SystemCapability.xxx')` 或 `API_VERSION >= 26` 守卫后再调用。
4. 升级后**必须先清构建缓存**再编译（否则会命中旧缓存的幽灵错误）：
   - `Python shutil.rmtree` 删除 `E:/HiXD/entry/build`、`E:/HiXD/.hvigor`、`C:/Users/花粉WJL/.hvigor/project_caches`。
   - 命令行：`hvigorw.bat assembleHap --mode module -p product=default`（`DEVECO_SDK_HOME=E:/HUAWEI/DevEco Studio/sdk`）。
5. 注意：升高 `targetSdkVersion` 可能引入**运行时行为变更**，需全量回归（见 §4）。

---

## 2. 特性采纳清单（按价值/代价分级）

> 图例：价值 ★ 数量 = 预期收益；代价 = 改造工作量与风险。

### Tier 1 — 高价值、低成本，建议优先

#### [ ] 1. ArkWeb 内核升级 Chromium 132 → 144 + `SecurityParams`
- **价值**：★★★　**代价**：极低（升 SDK 自动获得）
- 收益：HiXD 有 10+ 门户 WebView（订水/报修/空间预约/Portal/睿思/校园网/校园卡/邮箱/水电缴费/物理计算），新版 Chromium 现代 JS/CSS 兼容性更好，学校老旧门户渲染 bug 更少。
- 改造：可选调用 `webview.SecurityParams` 设置网页安全属性（拦截 mixedContent / 不安全资源）。
- **⚠️ 回归重点（必测）**：CAS 登录依赖 webview cookie 透传；xgxt WebView 注入串（`XGXT_INFO:` / `CX_UID:` / `XGXT_ERR:`）的 JS bridge 是否正常。详见 §4。

#### [ ] 2. ~~`@Reusable` / `@ReusableV2` 全局复用池（课表性能）~~　**【已移出本期计划】**
- **价值**：★★★　**代价**：中
- 收益：`ClassTablePage.ets`（~3009 行）周课表网格大量课程 cell（`CustomCourseItem` type 0/1/2），上全局复用池减少组件创建/GC，滚动更顺——直接治"卡顿"痛点。
- 改造：给课程 cell 组件加 `@Reusable`，在 `LazyForEach`/`ForEach` 的 `itemGenerator` 中用 `reuseId` + `recycle` 复用。
- 备注：`@Reusable` 装饰器本身在 API 10+ 即有；**"全局复用池"配置是 26 增强**。即此项在现有 API 23 上也能先做（仅全局池特性需 26）。
- **状态(2026-07-09)**：**已移出本期计划**。用户决策——固定周网格本就流畅，抽 `Component` 重构代价大、受益小，且演示前不应冒课表回归风险。后续若确需优化课表滚动，再单独评估。

#### [x] 3. 通知设置入口 `openNotificationSettingsWithResult`（锁屏字段/实际提醒未做）
- **价值**：★★　**代价**：小
- 收益：曾因"通知权限申请不了"删除 `CourseReminderService`。该 API 可**半模态带返回值**地拉起通知设置页，给用户明确入口手动开启；配合引导文案可复活"课前提醒 / 考试提醒"。
- 改造（**已落地**）：在「我的 → 其他」增加"通知设置"菜单项，调用该 API 半模态拉起系统通知设置页；返回后 `isNotificationEnabled()` 刷新「已开启/点击开启系统通知」状态；守卫改为 `typeof` 运行时存在性判断（非版本硬编码）。
- **未做**：锁屏通知字段、课前/考试实际提醒推送（原 `CourseReminderService` 仍删，本地定时无系统 schedule API，需 `WorkScheduler`/Live View，见 Tier 3 #8）。

### Tier 2 — 视觉/适配增强，低风险锦上添花（候选 backlog，非本期承诺）

#### [ ] 4. `systemMaterial` 系统材质 + 组件级沉浸光感
- **价值**：★★　**代价**：小~中
- 收益：贴合现有 `ThemeColors` 主题系统，将卡片/弹窗/Toast/Tips 换成系统材质，获得 HarmonyOS 7 毛玻璃沉浸质感，统一视觉风格。

#### [ ] 5. `ContainerReader` 容器断点自适应
- **价值**：★★　**代价**：中
- 收益：平板/折叠屏（双折/三折/阔折）适配更稳。当前 `HdsTabs` 已手动处理折叠/分屏，可用 `ContainerReader` 按容器尺寸自适应升级。

#### [ ] 6. Chip `backgroundSystemMaterial` / `activatedBackgroundSystemMaterial`
- **价值**：★　**代价**：小
- 收益：筛选标签（如课表周次/实验筛选）用系统材质背景，与 #4 风格统一。

#### [ ] 7. `LazyVWaterFlowLayout` 懒加载瀑布流
- **价值**：★　**代价**：中
- 收益：仅在新增"校园图库 / 资讯流"等场景时采用，目前无需求。

### Tier 3 — 前瞻/重投入，按需评估（候选 backlog，非本期承诺）

#### [ ] 8. Live View 实况窗（进度环模板）+ Push Kit 支持 Wearable
- **价值**：★　**代价**：高
- 说明：考试倒计时卡可升级为锁屏/通知栏常驻实况窗；但 Push/Live View 需 **AGC 服务端配置 + 服务端下发**，校园内网环境难接，优先级靠后。

#### [ ] 9. Ability Kit ArkTS 应用 Skill / `scriptManager`
- **价值**：★　**代价**：高（Beta + 框架复杂）
- 说明：26 新增"应用内 Skill"，可让小艺/快捷指令调用 HiXD 能力（"查今天课表""查电费"）——极契合"校园助手"定位，但属新框架，建议等 Release 后再评估。

#### [ ] 10. Scan Kit `isDefaultScanSupported` / `isCustomScanSupported`
- **价值**：★　**代价**：小
- 说明：将来加扫码（绑设备/扫图书馆书）时，先查设备能力再拉起对应扫码界面。

#### [ ] 11. Device Security 星盾（风控引擎 / 超级隐私）
- **价值**：★　**代价**：中高
- 说明：CAS cookie 登录态可用风控引擎检测风险环境；超级隐私可策略化管控相机/麦克风/位置。校园 App 价值一般，接入重，暂观望。

#### [ ] 12. Data Augmentation（邮件智能分析）/ PDF Kit / Core Vision
- **价值**：—　**代价**：—
- 说明：与现有 WebView 方案重叠或无场景，暂不采纳。

---

## 3. 推荐落地组合

覆盖你之前的两个痛点（卡顿 / 通知申请不了），且风险最低：

1. **ArkWeb 144**（随 SDK 升级自动获得，仅待回归测试）→ 治门户兼容性。
2. ~~`@Reusable` 课表全局复用池~~（**已移出计划**）。
3. **通知设置入口**（已落地）→ 治通知权限。

> 本期实际落地组合 = #3 通知入口 + 编译目标切 API26 + 若干修复（首登课表/主题色/滑块遮罩）。Tier 2/3 均为候选 backlog，非本期承诺。

---

## 4. 升级回归测试清单（必做）

- [ ] **CAS 登录全流程**：webview cookie 跨页透传正常，登录成功写入会话。
- [ ] **xgxt WebView JS bridge**：`XGXT_INFO:` / `CX_UID:` / `XGXT_ERR:` 三类消息能被 `onConsole` 正确接收并处理（个人信息抓取、超星头像）。
- [ ] **全部门户 WebView 页**：订水/报修/空间预约/Portal/睿思/校园网/校园卡/邮箱/水电缴费/物理计算 渲染无白屏、表单/按钮可交互。
- [ ] **课表滚动/切换周次**：帧率与卡顿对比升级前是否有改善。
- [ ] **通知引导**：点击"去开启通知"能半模态拉起设置页并返回结果。
- [ ] **桌面卡片**：`ClassPreviewCard` / `ExamCountdownCard`（2x2、4x2）仍能构建并正确刷新。
- [ ] **沉浸式状态栏**：26 下 `statusBarHeight` / `navIndicatorHeight` 取值与标题栏避让仍正确。
- [ ] **命令行编译**：`hvigorw.bat assembleHap` 的 `CompileArkTS` 阶段 0 错误（PackageHap 在本机有 JVM 崩溃环境坑，GUI 构建可正常出包，按历史结论可忽略）。

---

## 5. 备注
- 本文件为计划文档，不随发版强制提交；待 `feature/api26` 分支实际开工后，可将已勾选项移入对应 PR 描述。
- 参考来源：华为开发者联盟文档中心 · 26.0.0 元服务版本说明 / OS 平台新增和增强特性 / 版本号格式调整说明；HarmonyOS SDK 26 发布说明（HDC 2026）。
