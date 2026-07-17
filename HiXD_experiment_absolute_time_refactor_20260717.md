# HiXD 实验时间绝对时间方案重构

**日期**：2026-07-17
**状态**：已完成模型/生产者/消费者改造（待编译验证）

## 根因
`SectionTimes` 映射表在日历导出（`CalendarExportPage.impC/impE/synC/synE`）和 `CalendarSyncService.syncC/syncE` 中被重复定义（`ST[]`），且解析时对 `ST[cell.startSection].split('-')` 取 `sp[0]` 和 `ep[1]`——该代码耦合了"第几节→钟点"的算数转换，一旦节次映射更新就极难排查。同时 `w * 7` 的 offset bug（上一轮已修复）已暴露出基于 `section` 间接计算的脆弱性。

## 方案
给所有数据模型加 **`startTime`/`endTime`**（HH:MM 字符串），生产端以共享常量表 `SEC_START[1..11]`/`SEC_END[1..11]` 一次性填充，消费端优先读 `startTime`/`endTime`，存量旧数据回退 `section→table`。

## 改动清单

### 模型层
| 文件 | 模型 | 新字段 |
|------|------|--------|
| `MainPage.ets` | `PreviewCell` | `startTime: string`, `endTime: string` |
| `ClassTablePage.ets` | `ClassCell` | `startTime: string`, `endTime: string` |
| `ClassTablePage.ets` | `CustomCourseItem` | `startTime: string`, `endTime: string` |
| `CalendarExportPage.ets` | `SlimCell` | `startTime: string`, `endTime: string` |
| `CalendarSyncService.ets` | `SlimCell` | `startTime: string`, `endTime: string` |

### 共享常量（MainPage.ets 顶部 export）
```ts
export const SEC_START: string[] = ['', '08:30','09:20','10:25','11:15','14:00','14:50','15:55','16:45','19:00','19:55','20:40'];
export const SEC_END:   string[] = ['', '09:15','10:05','11:10','12:00','14:45','15:35','16:40','17:30','19:45','20:35','21:25'];
```

### 生产者（填充 startTime/endTime）
- **MainPage.ets** `mergeExperimentPreview` — `SEC_START[startSec]`/`SEC_END[endSec]`
- **MainPage.ets** `mergePhysicsPreview` — 同上
- **MainPage.ets** `mergeCustomPreview` — 同上
- **ClassTablePage.ets** `loadCustomCourses` — 从 `item.startTime`/`item.endTime` 取，旧数据兼容 `SEC_START`
- **ClassTablePage.ets** `addCustomCourse` — `SEC_START[section]`/`SEC_END[section]`
- **ClassTablePage.ets** `cellToItem` — `cell.startTime`/`cell.endTime` 回写持久化

### 消费者（优先用 startTime/endTime）
- **CalendarExportPage.ets** — 新增 `getTimeFromCell()` helper，impC/impE/synC/synE 调用，优先 `cell.startTime` → 回退 `SEC_START[section]`；删除本地 `ST[]` 数组
- **CalendarSyncService.ets** — 同 `getTimeFromCell()` helper，syncC/syncE 调用；删除本地 `ST[]` 数组

### 未修改
- `EntryFormAbility.ets` 的 `SECTION_TIMES` — 仅用于桌面卡片字符串拼接，不涉及日历时间计算，无需改动
- `MainPage.ets` / `EhallService.ets` / `ExperimentService.ets` / `Models.ets` 中的 `SECTION_TIMES` 引用 — 为课表网格 y 轴标尺渲染，不参与日历事件计算

## 向后兼容
- `CustomCourseItem` 序列化 JSON：新增 `startTime`/`endTime` 字段，默认空字符串
- `ClassCell.startTime`/`endTime`：`loadCustomCourses` 中若 `item.startTime` 为空则从 `SEC_START[item.startSection]` 兜底
- `SlimCell`：`getTimeFromCell()` 优先 `cell.startTime`，空则回退 `SEC_START[cell.startSection]`

## 待验证
- DevEco Studio 构建编译通过
- 真机：新建自定义实验 → 日历导出 → 确认时间正确
- 真机：已有实验数据迁移（`startTime`/`endTime` 为空 → 回退路径）
