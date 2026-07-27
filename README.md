# HiXD

<div align="center">

**西电校园助手 · HarmonyOS 原生应用**

一款为西安电子科技大学学生打造的鸿蒙原生校园工具，集成课表、成绩、考试、实验、空教室、图书馆、校园卡、校园网、电费查询等常用功能于一体。

[![Version](https://img.shields.io/badge/version-1.4.1-blue)](https://github.com/PollenWang6/HiXD)
[![HarmonyOS](https://img.shields.io/badge/HarmonyOS%206%20(API%2024)-orange)](https://developer.huawei.com/consumer/cn/harmonyos/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

</div>

---

## 功能

### 核心功能

| 功能 | 说明 |
|------|------|
| 📅 课程表 | 周视图课表，课程冲突提示，自定义课程，自定义背景图，一键导入系统日历 |
| 🧪 实验信息 | 实验课表查询，系统物理实验 + 其他实验 |
| 📝 考试安排 | 考试时间、地点、座位号查询，未安排考试列表 |
| 🏆 成绩查询 | 成绩列表，GPA 计算，成绩构成详情，本科生/研究生双轨支持 |
| 🏫 空教室 | 按教学楼和日期查询空闲教室 |
| 📚 图书馆 | 馆藏检索、图书详情、馆藏位置；当前借阅/续借、扫码借书（libsp 新系统） |
| 🪑 座位预约 | 超星座位引擎，WebView 一键免登直达选座 |
| 💳 校园卡 | 余额查询、付款码、消费流水；挂失/解绑/修改密码 |
| 📋 考勤查询 | 超星平台到课率、缺勤统计、可缺勤次数，分组颜色标注 |
| 🚰 宿舍水机 | 扫码绑定、远程控制宿舍饮水机 |
| 🏃 体育系统 | 体测成绩查询、体育课程信息查询 |
| 🌐 校园网 | 流量查询、在线设备管理，自助服务平台数据接入 |
| ⚡ 电费查询 | 宿舍电费余额和用量查询 |
| 📧 学生邮箱 | icoremail 邮箱入口 |
| 🎨 主题定制 | 预设主题色 + 自定义色号，深色/浅色独立配色 |

### 更多功能

「更多功能」页汇集常用的学校线上服务，均通过应用内 WebView 免登直达，支持自定义排序：

| 功能 | 说明 |
|------|------|
| 💰 水电缴费 | 线上一键缴纳水电费用 |
| 💧 订水系统 | 宿舍桶装水订购 |
| 🛠️ 后勤报修 | 足不出户提交报修 |
| 🏢 空间预约 | 研讨间 / 自习空间预约 |
| 📱 移动门户 | 校园服务一网打尽 |
| 🧭 睿思导航 | 睿思平台其他功能补充 |
| 🔬 物理计算 | 物理实验数据处理助手 |
| 📧 学生邮箱 | icoremail 邮件查看 |
| 🌐 校园网登录 | 校园网自助服务平台 |
| 🪪 校园卡服务 | 挂失 / 解绑 / 修改密码 |

### 桌面卡片

| 卡片 | 尺寸 | 功能 |
|------|------|------|
| 课程预告 | 4×2 | 今日/明日课程预览，点击跳转课表 |
| 课程预告 | 2×2 | 紧凑版课程预览，支持滚动 |
| 考试倒计时 | 4×2 | 距最近考试天数与详情，点击跳转考试页 |
| 考试倒计时 | 2×2 | 紧凑版倒计时 |

---

## 技术栈

- **平台**: HarmonyOS 6.0.2 及以上 (API 22+)，目标 API 26 (HarmonyOS 7)
- **语言**: ArkTS / ArkUI
- **网络**: @ohos.net.http + WebView
- **存储**: @ohos.data.preferences (PreferenceUtil)
- **UI**: HDS Design Kit、系统颜色资源适配深色模式
- **桌面卡片**: FormExtensionAbility + 系统颜色资源自动深色适配

---

## 已知限制

- **后台登录态**: 应用长时间后台放置后 Cookie 可能过期，重新打开 WebView 页面或触发会话重激活即可恢复

---

## 构建 & 运行

1. 安装 [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/)
2. Clone 本仓库，用 DevEco Studio 打开
3. 配置签名后连接设备或启动模拟器，点击运行

---

## License

MIT

## 致谢

本项目部分 API 接口参考了 [Traintime PDA / XDYou](https://github.com/BenderBlog/traintime_pda)（MPL-2.0），感谢该项目的接口探索工作。
