# HiXD

<div align="center">

**西电校园助手 · HarmonyOS 原生应用**

一款为西安电子科技大学学生打造的鸿蒙原生校园工具，集成课表、成绩、考试、实验、空教室、图书馆、校园卡、校园网、电费查询等常用功能于一体。

[![Version](https://img.shields.io/badge/version-1.3.1-blue)](https://github.com/PollenWang6/HiXD)
[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-Next%20API%2012-orange)](https://developer.huawei.com/consumer/cn/harmonyos/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

</div>

---

## 功能

### 核心功能

| 功能 | 说明 |
|------|------|
| 📅 课程表 | 周视图课表，课程冲突提示，自定义课程，自定义背景图，一键导入系统日历 |
| 🔄 课程变更 | 查看调课/停课/补课信息 |
| 📋 未安排课程 | 已选课但尚未排课的课程列表 |
| 🧪 实验信息 | 实验课表查询，系统物理实验 + 其他实验 |
| 📝 考试安排 | 考试时间、地点、座位号查询，未安排考试列表 |
| 🏆 成绩查询 | 成绩列表，GPA 计算，成绩构成详情，本科生/研究生双轨支持 |
| 🏫 空教室 | 按教学楼和日期查询空闲教室 |
| 📚 图书馆 | 馆藏检索，图书详情，馆藏位置 |
| 💳 校园卡 | 余额查询、付款码、消费流水；挂失/解绑/修改密码 |
| 📋 考勤查询 | 超星平台到课率、缺勤统计、可缺勤次数，分组颜色标注 |
| 🚰 宿舍水机 | 扫码绑定、远程控制宿舍饮水机 |
| 🌐 校园网 | 流量查询、在线设备管理 |
| ⚡ 电费查询 | 宿舍电费余额和用量查询 |
| 📧 学生邮箱 | icoremail 邮箱入口 |
| 🎨 主题定制 | 预设主题色 + 自定义色号，深色/浅色独立配色 |

### 校园门户

通过应用内 WebView 访问西电移动门户，支持：
- 水电缴费 · 订水服务
- 请销假 · 报修服务
- 空间预约 · 睿思导航
- 校园卡挂失/解绑/修改密码

### 桌面卡片

| 卡片 | 尺寸 | 功能 |
|------|------|------|
| 课程预告 | 4×2 | 今日/明日课程预览，点击跳转课表 |
| 课程预告 | 2×2 | 紧凑版课程预览，支持滚动 |

---

## 技术栈

- **平台**: HarmonyOS 5.0及以上 (API 12+)
- **语言**: ArkTS / ArkUI
- **网络**: @ohos.net.http + WebView
- **存储**: @ohos.data.preferences (PreferenceUtil)
- **UI**: HDS Design Kit、系统颜色资源适配深色模式
- **桌面卡片**: FormExtensionAbility + 系统颜色资源自动深色适配

---

## 已知限制

- **校园卡原生页**: 首次使用需先登录并通过 WebView 版建立 Cookie 会话，之后原生 API 即可正常查询余额和付款码
- **后台登录态**: 应用长时间后台放置后 Cookie 可能过期，重新打开 WebView 页面即可恢复

---

## 构建 & 运行

1. 安装 [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/)
2. Clone 本仓库，用 DevEco Studio 打开
3. 配置签名后连接设备或启动模拟器，点击运行

---

## License

MIT

## 致谢

本项目部分 API 接口参考了 [Traintime PDA / XDYou](https://github.com/SuperBart/traintime_pda)（MPL-2.0），感谢该项目的接口探索工作。
