import { ThemeColors } from '../../../utils/ThemeColors';
import { PressScale } from '../../../components/PressScale';
import { ACCENT_PRESETS } from '../../../utils/AccentColors';
import { PreferenceUtil } from '../../../utils/PreferenceUtil';
import { SemesterUtil } from '../../../services/ids/EhallService';
import { deviceInfo } from '@kit.BasicServicesKit';

// 我的 Tab：用户信息卡片 + 个性化/学习/其他 三组菜单
// 弹窗打开逻辑全部通过回调上抛 MainPage（弹窗状态由 MainPage 统一管理）
@Component
export struct MyTab {
  // 主题/系统状态（AppStorage 共享）
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  // 用户信息
  @Prop userDisplayName: string = '';
  @Prop username: string = '';
  @Prop userAvatarUrl: string = '';
  @Prop userGender: string = '';
  @Prop userCollege: string = '';
  @Prop userMajor: string = '';
  @Prop userStudentType: string = '';
  @Prop userGrade: string = '';
  @Prop userClassName: string = '';
  @Prop userRefreshing: boolean = false;

  // 菜单显示状态
  @Prop isLoggedIn: boolean = false;
  @Prop currentThemeLabel: string = '';
  @Prop accentIdx: number = 0;
  @Prop bgShow: boolean = false;
  @Prop phyPwdStatus: string = '';
  @Prop schoolnetPwdStatus: string = '';
  @Prop sportPwdStatus: string = '';
  @Prop cacheSize: string = '';

  // 回调
  onRefreshUserInfo: () => void = () => {};
  onOpenThemeDialog: () => void = () => {};
  onOpenColorDialog: () => void = () => {};
  onOpenBgDialog: () => void = () => {};
  onOpenSemesterDialog: () => void = () => {};
  onOpenLogoutDialog: () => void = () => {};
  onOpenPhyPwdDialog: () => void = () => {};
  onOpenSchoolnetPwdDialog: () => void = () => {};
  onOpenSportPwdDialog: () => void = () => {};
  onClearCache: () => void = () => {};
  onNavigateCalendar: () => void = () => {};
  onNavigateAbout: () => void = () => {};
  onLogin: () => void = () => {};

  // 根据主题色亮度选择白色或黑色文字
  accentTextColor(): string {
    const hex = this.accentColor.replace('#', '');
    const r = parseInt(hex.substring(0, 2), 16);
    const g = parseInt(hex.substring(2, 4), 16);
    const b = parseInt(hex.substring(4, 6), 16);
    const lum = (0.299 * r + 0.587 * g + 0.114 * b);
    return lum > 160 ? '#333333' : '#FFFFFF';
  }

  // ===== 菜单行组件 =====
  @Builder themeRow() {
    PressScale({ onTap: () => { this.onOpenThemeDialog() } }) {
    Row() {
      Text('🌓').fontSize(26).margin({ right: 16 })
      Column() {
        Text('深色设置').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
        Text(this.currentThemeLabel).fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
      }.layoutWeight(1)
      Text('›').fontSize(20).fontColor(ThemeColors.textSecondary)
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
        }
  }

  @Builder colorRow() {
    PressScale({ onTap: () => { this.onOpenColorDialog() } }) {
    Row() {
      Circle().width(22).height(22).fill(this.accentColor).margin({ right: 16 })
      Column() {
        Text('主题色').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
        Text(this.accentIdx === -1 ? '自定义' : (ACCENT_PRESETS[this.accentIdx]?.[2] ?? '')).fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
      }.layoutWeight(1)
      Text('›').fontSize(20).fontColor(ThemeColors.textSecondary)
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
        }
  }

  @Builder bgRow() {
    PressScale({ onTap: () => { this.onOpenBgDialog() } }) {
    Row() {
      Text('🖼️').fontSize(26).margin({ right: 16 })
      Column() {
        Text('课表背景').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
        Text(this.bgShow ? '已设置图片' : '未自定义').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
      }.layoutWeight(1)
      Text('›').fontSize(20).fontColor(ThemeColors.textSecondary)
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
        }
  }

  @Builder semesterRow() {
    PressScale({ onTap: () => { this.onOpenSemesterDialog() } }) {
    Row() {
      Text('📅').fontSize(26).margin({ right: 16 })
      Column() {
        Text('学期设置').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
        Text(SemesterUtil.formatSemester(SemesterUtil.getCurrentSemesterCode())).fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
      }.layoutWeight(1)
      Text('›').fontSize(20).fontColor(ThemeColors.textSecondary)
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
        }
  }

  @Builder logoutRow() {
    PressScale({ onTap: () => { this.onOpenLogoutDialog() } }) {
    Row() {
      Text('🔓').fontSize(26).margin({ right: 16 })
      Column() {
        Text('退出登录').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
        Text('清除登录状态').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
      }.layoutWeight(1)
      Text('›').fontSize(20).fontColor(ThemeColors.textSecondary)
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
        }
  }

  @Builder cacheRow() {
    PressScale({ onTap: () => { this.onClearCache() } }) {
    Row() {
      Text('🗑️').fontSize(26).margin({ right: 16 })
      Column() {
        Text('清除缓存').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
        Text('当前 ' + this.cacheSize).fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
      }.layoutWeight(1)
      Text('›').fontSize(20).fontColor(ThemeColors.textSecondary)
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
        }
  }

  build() {
    Column() {
      // 顶部
      Row() {
        Text('我的').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.accentTextColor())
      }
      .width('100%').height(52 + this.statusBarHeight).padding({ left: 20, top: this.statusBarHeight })
      .backgroundColor(this.accentColor)
      Divider().color('#F0F0F0')

      // 用户区域：有缓存数据就显示信息卡片，否则显示登录入口
      if (this.userDisplayName || this.username) {
        Column() {
          // 顶部主题色装饰条
          Row()
            .width('100%').height(64)
            .linearGradient({
              direction: GradientDirection.Right,
              colors: [[this.accentColor, 0], [this.accentColor + 'CC', 0.5], [this.accentColor + '66', 1]]
            })

          // 内容区：头像 overlap 装饰条 + 信息
          Row() {
            // 头像 — 大号，带白边
            Stack() {
              Circle().width(72).height(72).fill('#FFFFFF')
              if (this.userAvatarUrl) {
                Image(this.userAvatarUrl).width(66).height(66).borderRadius(33).objectFit(ImageFit.Cover)
              } else {
                Stack() {
                  Circle().width(66).height(66).fill(this.accentColor + '18')
                  Text('🎓').fontSize(32)
                }.width(66).height(66).borderRadius(33)
              }
            }
            .width(72).height(72)
            .offset({ y: -20 })
            .margin({ left: 20 })

            // 右侧信息区
            Column() {
              // 姓名行 + 刷新按钮
              Row() {
                Text(this.userDisplayName || this.username || '已登录')
                  .fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.userGender && this.userGender !== '') {
                  Text(this.userGender === '男' ? '♂' : '♀')
                    .fontSize(18).fontWeight(FontWeight.Bold)
                    .fontColor(this.userGender === '男' ? '#5D9CEC' : '#EC5D8A')
                    .margin({ left: 6 })
                }
                Blank()
                // 刷新按钮
                Row() {
                  if (this.userRefreshing) {
                    LoadingProgress().width(16).height(16).color(this.accentColor)
                  } else {
                    Text('🔄').fontSize(16)
                  }
                }
                .width(32).height(32)
                .justifyContent(FlexAlign.Center)
                .borderRadius(16)
                .backgroundColor(this.accentColor + '10')
                .hoverEffect(HoverEffect.Auto).onClick(() => { this.onRefreshUserInfo(); })
              }.width('100%')

              // 学院 · 专业
              if (this.userCollege || this.userMajor) {
                Row() {
                  if (this.userCollege) {
                    Text(this.userCollege).fontSize(12).fontColor(ThemeColors.textSecondary).maxLines(1)
                  }
                  if (this.userCollege && this.userMajor) {
                    Text(' · ').fontSize(12).fontColor(ThemeColors.textHint)
                  }
                  if (this.userMajor) {
                    Text(this.userMajor).fontSize(12).fontColor(ThemeColors.textSecondary)
                      .layoutWeight(1).textOverflow({ overflow: TextOverflow.Ellipsis }).maxLines(1)
                  }
                }.margin({ top: 4 })
              }
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
            .margin({ left: 14, right: 20, top: 8 })
          }.width('100%')

          // 标签行 — 与信息区左对齐（头像左边距20 + 头像72 + 间距14 = 106vp）
          Row() {
            if (this.userStudentType) {
              Text(this.userStudentType)
                .fontSize(11).fontColor('#FFFFFF')
                .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                .backgroundColor(this.accentColor)
                .borderRadius(10)
            } else {
              Text(PreferenceUtil.getBool('role') ? '研究生' : '本科生')
                .fontSize(11).fontColor('#FFFFFF')
                .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                .backgroundColor(this.accentColor)
                .borderRadius(10)
            }
            if (this.userGrade) {
              Text(this.userGrade + '级')
                .fontSize(11).fontColor(ThemeColors.textSecondary)
                .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                .backgroundColor(this.accentColor + '12')
                .borderRadius(10)
                .margin({ left: 8 })
            }
            if (this.userClassName) {
              Text(this.userClassName + '班')
                .fontSize(11).fontColor(ThemeColors.textSecondary)
                .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                .backgroundColor(this.accentColor + '12')
                .borderRadius(10)
                .margin({ left: 8 })
            }
          }
          .width('100%')
          .padding({ left: 106, right: 20, top: 8, bottom: 16 })
        }
        .width('100%')
        .backgroundColor(ThemeColors.bgCard)
        .borderRadius(16)
        .shadow({ radius: 6, color: '#00000012', offsetY: 2 })
        .margin({ left: 14, right: 14, top: 10 })
        .clip(true)
      } else {
        // 未登录提示
        Button('登录以使用完整功能')
          .width('90%').height(44).fontSize(15).fontColor('#FFFFFF')
          .backgroundColor('#2979FF').borderRadius(22)
          .margin({ top: 24 })
          .hoverEffect(HoverEffect.Auto).onClick(() => { this.onLogin(); })
      }

      // 菜单（始终显示）
      List({ space: 12 }) {
        // ===== 个性化 =====
        ListItem() {
          Column() {
            Text('个性化').fontSize(15).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              .padding({ left: 16, top: 14, bottom: 10 })
            Divider().color('#E0E0E0').strokeWidth(0.5).margin({ left: 16, right: 16 })
            this.themeRow()
            Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 60, right: 16 })
            this.colorRow()
            Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 60, right: 16 })
            this.bgRow()
          }
          .borderRadius(12).clip(true).backgroundColor(ThemeColors.bgCard)
          .shadow({ radius: 10, color: '#00000014', offsetY: 3 }).border({ width: 1, color: ThemeColors.border })
        }

        // ===== 学习 =====
        if (this.isLoggedIn) {
        ListItem() {
          Column() {
            Text('学习').fontSize(15).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              .padding({ left: 16, top: 14, bottom: 10 })
            Divider().color('#E0E0E0').strokeWidth(0.5).margin({ left: 16, right: 16 })
            this.semesterRow()
            Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 60, right: 16 })
            // 物理实验设置
            PressScale({ onTap: () => { this.onOpenPhyPwdDialog() } }) {
            Row() {
              Text('⚛️').fontSize(26).margin({ right: 16 })
              Column() {
                Text('物理实验设置').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                Text(this.phyPwdStatus).fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
              }.layoutWeight(1)
              Text('›').fontSize(20).fontColor(ThemeColors.textSecondary)
            }
            .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
                        }
            Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 60, right: 16 })
            // 校园网密码设置
            PressScale({ onTap: () => { this.onOpenSchoolnetPwdDialog() } }) {
            Row() {
              Text('🌐').fontSize(26).margin({ right: 16 })
              Column() {
                Text('校园网密码').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                Text(this.schoolnetPwdStatus).fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
              }.layoutWeight(1)
              Text('›').fontSize(20).fontColor(ThemeColors.textSecondary)
            }
            .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
                        }
            Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 60, right: 16 })
            // 体育密码设置
            PressScale({ onTap: () => { this.onOpenSportPwdDialog() } }) {
            Row() {
              Text('🏀').fontSize(26).margin({ right: 16 })
              Column() {
                Text('体育系统密码').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                Text(this.sportPwdStatus).fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
              }.layoutWeight(1)
              Text('›').fontSize(20).fontColor(ThemeColors.textSecondary)
            }
            .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
                        }
            Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 60, right: 16 })
            // 导入系统日历
            PressScale({ onTap: () => { this.onNavigateCalendar() } }) {
            Row() {
              Text('📅').fontSize(26).margin({ right: 16 })
              Column() {
                Text('导入系统日历').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                Text('课程/实验/考试导入日历').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
              }.layoutWeight(1)
              Text('›').fontSize(20).fontColor(ThemeColors.textSecondary)
            }
            .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
                        }
          }
          .borderRadius(12).clip(true).backgroundColor(ThemeColors.bgCard)
          .shadow({ radius: 10, color: '#00000014', offsetY: 3 }).border({ width: 1, color: ThemeColors.border })
        }
        }

        // ===== 其他 =====
        ListItem() {
          Column() {
            Text('其他').fontSize(15).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              .padding({ left: 16, top: 14, bottom: 10 })
            Divider().color('#E0E0E0').strokeWidth(0.5).margin({ left: 16, right: 16 })
            // 关于软件
            PressScale({ onTap: () => { this.onNavigateAbout() } }) {
            Row() {
              Text('ℹ️').fontSize(26).margin({ right: 16 })
              Column() {
                Text('关于软件').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                Text('用户协议 · 隐私政策 · 检查更新').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
              }.layoutWeight(1)
              Text('›').fontSize(20).fontColor(ThemeColors.textSecondary)
            }
            .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
                        }
            Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 60, right: 16 })
            this.logoutRow()
            Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 60, right: 16 })
            this.cacheRow()
          }
          .borderRadius(12).clip(true).backgroundColor(ThemeColors.bgCard)
          .shadow({ radius: 10, color: '#00000014', offsetY: 3 }).border({ width: 1, color: ThemeColors.border })
        }
        ListItem().height(deviceInfo.distributionOSApiVersion >= 60100 ? 60 : 48)
      }
      .padding({ left: 16, right: 16, top: 8 })
      .layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(ThemeColors.bgPage)
  }
}
