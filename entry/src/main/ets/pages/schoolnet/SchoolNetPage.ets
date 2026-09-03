import { AccentColors } from '../../utils/AccentColors';
// SchoolNetPage.ets — 校园网页面（流量概览 + 在线设备 + ZFW详细账单）
// 对齐 Flutter: NetworkCardWindow (两个Tab: 自服务平台 + 认证系统)
import { ThemeColors } from '../../utils/ThemeColors';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { SecureStorageUtil, SecureAlias } from '../../utils/SecureStorageUtil';
import { SchoolnetService, ZfwIpEntry, ZfwUsageData } from '../../services/campus/SchoolnetService';
import { SegmentTab } from '../../components/SegmentTab';

@Component
export struct SchoolNetPage {
  pageInfo: NavPathStack = new NavPathStack();
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  @Builder buildWhiteTitle(t: string) {
    Row() {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.close'))
          .height(22)
          .fillColor(ThemeColors.textPrimary)
          .draggable(false)
      }
      .height(40).width(40)
      .hoverEffect(HoverEffect.Auto).onClick(() => { this.pageInfo.pop(); })
      Text(t)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(AccentColors.textContrast)
        .layoutWeight(1)
    }
    .width('100%')
    .height(52 + this.statusBarHeight)
    .padding({ left: 12, right: 16, top: this.statusBarHeight })
  }

  // Tab 切换
  @State currentTab: number = 0;

  // === 认证系统 Tab (w.xidian.edu.cn) ===
  @State authLoading: boolean = false;
  @State authOnline: boolean = false;
  @State authErrorMsg: string = '';
  @State authUsername: string = '';
  @State authUsedFlow: string = '';
  @State authRemainFlow: string = '';
  @State authTotalFlow: string = '';
  @State authUsedPercent: number = 0;
  @State authDeviceIp: string = '';
  @State authOnlineTime: string = '';
  @State authProductName: string = '';
  @State authUserBalance: string = '';
  @State authBytesIn: string = '';
  @State authOnlineSeconds: string = '';
  @State authUserMac: string = '';
  @State authCheckoutDate: string = '';

  // === 自服务平台 Tab (ZFW) ===
  @State zfwLoading: boolean = false;
  @State zfwState: string = 'idle'; // idle | needs_captcha | logging_in | logged_in | error
  @State hasZfwPwd: boolean = false;
  @State zfwCaptchaInput: string = '';
  @State zfwCaptchaBase64: string = '';
  @State zfwCsrf: string = '';
  @State zfwRsaKey: string = '';
  @State zfwErrorMsg: string = '';
  @State zfwUsedFlow: string = '';
  @State zfwRemainFlow: string = '';
  @State zfwSettleDate: string = '';
  @State zfwIpList: ZfwIpEntry[] = [];

  // 校园网密码弹窗
  @State showPwdDialog: boolean = false;
  @State pwdInput: string = '';
  @State pwdOpacity: number = 0;
  @State pwdTranslate: number = 30;

  private schoolnet = SchoolnetService.getInstance();

  aboutToAppear(): void {
    this.loadAuthData();
    this.loadZfwIfNeeded();
    SecureStorageUtil.get(SecureAlias.SCHOOLNET_PASSWORD).then((pwd: string) => { this.hasZfwPwd = pwd.length > 0; });
  }

  /** 切到自服务平台时自动加载 */
  async loadZfwIfNeeded(): Promise<void> {
    const savedPwd = await SecureStorageUtil.get(SecureAlias.SCHOOLNET_PASSWORD);
    if (this.zfwState === 'idle' && savedPwd.length > 0) {
      this.startZfwFlow();
    }
  }

  // ===== 认证系统数据 =====

  async loadAuthData(): Promise<void> {
    this.authLoading = true;
    this.authErrorMsg = '';
    try {
      const info = await this.schoolnet.getCurrentOnlineInfo();
      // not_online_error：账号未做校园网认证登录，rad_user_info 只回 error/res 字段，无 sum_flow/user_name
      const hasOnlineData: boolean = !!info['user_name']
        || Number(info['sum_flow'] || 0) > 0
        || Number(info['remain_flow'] || 0) > 0
        || info['is_online'] === 1;
      if (!hasOnlineData) {
        this.authOnline = false;
        this.authErrorMsg = '未检测到校园网在线信息，请先连接西电 WiFi 并完成上网认证后重试';
        return;
      }
      this.authOnline = true;
      this.authUsername = String(info['user_name'] || '');

      const sumFlow: number = parseFloat(String(info['sum_flow'] || 0));
      const remainFlow: number = parseFloat(String(info['remain_flow'] || 0));
      const totalFlow: number = sumFlow + remainFlow;

      this.authUsedFlow = this.formatFlowNum(sumFlow);
      this.authRemainFlow = this.formatFlowNum(remainFlow);
      this.authTotalFlow = this.formatFlowNum(totalFlow);
      this.authUsedPercent = totalFlow > 0 ? sumFlow / totalFlow : 0;

      this.authDeviceIp = String(info['user_ip'] || '');
      const addTimeTs = parseInt(String(info['add_time_ts'] || info['add_time'] || 0)) || 0;
      if (addTimeTs > 0) {
        this.authOnlineTime = this.formatTimestamp(addTimeTs);
      }
      this.authProductName = String(info['products_name'] || '');
      const balance: number = parseFloat(String(info['user_balance'] || 0));
      this.authUserBalance = '¥' + balance.toFixed(2);

      // 扩展字段
      const bytesIn: number = parseFloat(String(info['bytes_in'] || 0));
      this.authBytesIn = this.formatFlowNum(bytesIn);
      const sumSeconds: number = parseInt(String(info['sum_seconds'] || 0)) || 0;
      this.authOnlineSeconds = this.formatDuration(sumSeconds);
      this.authUserMac = String(info['user_mac'] || '');
      const checkoutDate: number = parseInt(String(info['checkout_date'] || 0)) || 0;
      if (checkoutDate > 0) {
        // checkout_date 可能是 20260701 格式的数字
        const cdStr: string = String(checkoutDate);
        if (cdStr.length === 8) {
          this.authCheckoutDate = cdStr.substring(0, 4) + '-' + cdStr.substring(4, 6) + '-' + cdStr.substring(6, 8);
        } else {
          this.authCheckoutDate = cdStr;
        }
      }
    } catch (_e) {
      console.error('[SchoolNetPage] loadAuthData fail: ' + (_e ? (_e as Error).message : _e));
      this.authOnline = false;
      this.authErrorMsg = '无法获取校园网信息（请确认已连接校园网）';
    } finally {
      this.authLoading = false;
    }
  }

  // ===== ZFW 自服务平台 =====

  async startZfwFlow(): Promise<void> {
    const savedPwd: string = await SecureStorageUtil.get(SecureAlias.SCHOOLNET_PASSWORD);
    if (savedPwd.length === 0) {
      this.zfwState = 'error';
      this.zfwErrorMsg = '请先设置校园网密码';
      return;
    }

    this.zfwLoading = true;
    this.zfwErrorMsg = '';
    try {
      // 先尝试复用已有 session，避免每次都输验证码
      const existingData = await this.schoolnet.tryFetchZfwHome();
      if (existingData !== null) {
        this.applyZfwHomeData(existingData);
        this.zfwState = 'logged_in';
        return;
      }
      // 无有效 session → 走登录流程
      const loginData = await this.schoolnet.startZfwLogin();
      this.zfwCsrf = loginData.csrf;
      this.zfwRsaKey = loginData.rsaKey;
      this.zfwCaptchaBase64 = await this.schoolnet.getZfwCaptcha();
      this.zfwCaptchaInput = '';
      this.zfwState = 'needs_captcha';
    } catch (e) {
      this.zfwState = 'error';
      this.zfwErrorMsg = '连接自服务平台失败';
    } finally {
      this.zfwLoading = false;
    }
  }

  async submitCaptcha(): Promise<void> {
    if (this.zfwCaptchaInput.length === 0) return;
    this.zfwLoading = true;
    this.zfwErrorMsg = '';
    const savedPwd: string = await SecureStorageUtil.get(SecureAlias.SCHOOLNET_PASSWORD);
    const username: string = PreferenceUtil.getString('ids_account');
    try {
      const encryptedPwd = await this.schoolnet.encryptPasswordRSA(savedPwd, this.zfwRsaKey);

      // Step 1: validate-user
      const validateResult = await this.schoolnet.validateZfwUser(
        username, encryptedPwd, this.zfwCaptchaInput, this.zfwCsrf
      );
      if (!validateResult.success) {
        this.zfwState = 'needs_captcha';
        this.zfwErrorMsg = validateResult.message || '验证失败';
        this.zfwCaptchaBase64 = await this.schoolnet.getZfwCaptcha();
        this.zfwCaptchaInput = '';
        this.zfwLoading = false;
        return;
      }

      // Step 2: complete login
      const loginOk = await this.schoolnet.completeZfwLogin(
        username, encryptedPwd, this.zfwCaptchaInput, this.zfwCsrf
      );
      if (!loginOk) {
        this.zfwState = 'needs_captcha';
        this.zfwErrorMsg = '登录失败，请重试';
        this.zfwCaptchaBase64 = await this.schoolnet.getZfwCaptcha();
        this.zfwCaptchaInput = '';
        this.zfwLoading = false;
        return;
      }

      // Step 3: 获取数据
      const usage = await this.schoolnet.getZfwUsage();
      this.applyZfwHomeData(usage);
      this.zfwState = 'logged_in';
      AppStorage.set('home_data_dirty', String(Date.now()));
    } catch (e) {
      this.zfwState = 'error';
      this.zfwErrorMsg = '登录失败，请重试';
    } finally {
      this.zfwLoading = false;
    }
  }

  private applyZfwHomeData(data: ZfwUsageData): void {
    this.zfwUsedFlow = data.usedFlow;
    this.zfwRemainFlow = data.remainFlow;
    this.zfwSettleDate = data.settleDate;
    this.zfwIpList = data.ipList;
  }

  // ===== 密码弹窗 =====

  openPwdDialog(): void {
    SecureStorageUtil.get(SecureAlias.SCHOOLNET_PASSWORD).then((pwd: string) => { this.pwdInput = pwd; });
    this.showPwdDialog = true;
    animateTo({ duration: 300, curve: Curve.EaseOut }, () => { this.pwdOpacity = 1; this.pwdTranslate = 0; });
  }

  closePwdDialog(): void {
    animateTo({ duration: 200, curve: Curve.EaseIn }, () => { this.pwdOpacity = 0; this.pwdTranslate = 30; });
    setTimeout(() => { this.showPwdDialog = false; }, 200);
  }

  // ===== 工具方法 =====

  private formatFlowNum(num: number): string {
    if (num >= 1024 * 1024 * 1024) return (num / (1024 * 1024 * 1024)).toFixed(2) + ' GB';
    if (num >= 1024 * 1024) return (num / (1024 * 1024)).toFixed(2) + ' MB';
    if (num >= 1024) return (num / 1024).toFixed(2) + ' KB';
    return num.toFixed(2) + ' B';
  }

  private formatTimestamp(ts: number): string {
    const d = new Date(ts * 1000);
    const offsetMs = 8 * 60 * 60 * 1000;
    const local = new Date(d.getTime() + offsetMs + d.getTimezoneOffset() * 60 * 1000);
    const pad = (n: number): string => n < 10 ? '0' + n : '' + n;
    return local.getUTCFullYear() + '-' + pad(local.getUTCMonth() + 1) + '-' + pad(local.getUTCDate())
  }

  private formatDuration(seconds: number): string {
    const h: number = Math.floor(seconds / 3600);
    const m: number = Math.floor((seconds % 3600) / 60);
    const s: number = seconds % 60;
    if (h > 0) return h + '时' + m + '分' + s + '秒';
    if (m > 0) return m + '分' + s + '秒';
    return s + '秒';
  }

  // ===== 认证系统 Tab UI =====

  @Builder
  AuthTab(): void {
    if (this.authLoading) {
      Column() {
        LoadingProgress().width(40).height(40).color(this.accentColor)
        Text('加载中...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
      }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
    } else if (this.authOnline) {
      Scroll() {
        Column() {
          // 提示
          Row() {
            Text('⚠️').fontSize(14).margin({ right: 8 })
            Text('数据来自校园网认证系统，仅供参考').fontSize(12).fontColor('#BF4D00')
          }.width('100%').padding(12).borderRadius(10)
            .backgroundColor('#FFF3E0').margin({ bottom: 12 })

          // 用户信息卡片
          Column() {
            Text('概览').fontSize(14).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              .width('100%').margin({ bottom: 12 })

            Row() {
              Text('👤').fontSize(16).margin({ right: 8 })
              Text('账号').fontSize(13).fontColor(ThemeColors.textSecondary).width('20%')
              Text(this.authUsername).fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor(ThemeColors.textPrimary).layoutWeight(1)
            }.width('100%').margin({ bottom: 8 })

            Row() {
              Text('📋').fontSize(16).margin({ right: 8 })
              Text('套餐').fontSize(13).fontColor(ThemeColors.textSecondary).width('20%')
              Text(this.authProductName).fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor('#2E7D32').layoutWeight(1)
            }.width('100%').margin({ bottom: 8 })

            Row() {
              Text('💰').fontSize(16).margin({ right: 8 })
              Text('余额').fontSize(13).fontColor(ThemeColors.textSecondary).width('20%')
              Text(this.authUserBalance).fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor('#2E7D32').layoutWeight(1)
            }.width('100%')
          }.width('100%').padding(16).borderRadius(12)
            .backgroundColor(ThemeColors.bgCard)
            .shadow({ radius: 2, color: '#00000008', offsetY: 1 })

          // 流量使用卡片
          Column() {
            Text('流量使用').fontSize(14).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              .width('100%').margin({ bottom: 12 })

            // 进度条
            Progress({ value: this.authUsedPercent * 100, total: 100, type: ProgressType.Linear })
              .width('100%').color(this.authUsedPercent > 0.9 ? '#C62828' : this.accentColor)
              .margin({ bottom: 6 })
            Text('已使用 ' + (this.authUsedPercent * 100).toFixed(1) + '%')
              .fontSize(11).fontColor(ThemeColors.textSecondary)
              .width('100%').textAlign(TextAlign.End).margin({ bottom: 12 })

            Row() {
              Text('🔴').fontSize(14).margin({ right: 8 })
              Text('已用').fontSize(13).fontColor(ThemeColors.textSecondary).width('20%')
              Text(this.authUsedFlow).fontSize(13).fontWeight(FontWeight.Bold)
                .fontColor('#C62828').layoutWeight(1)
            }.width('100%').margin({ bottom: 8 })

            Row() {
              Text('🟢').fontSize(14).margin({ right: 8 })
              Text('剩余').fontSize(13).fontColor(ThemeColors.textSecondary).width('20%')
              Text(this.authRemainFlow).fontSize(13).fontWeight(FontWeight.Bold)
                .fontColor('#2E7D32').layoutWeight(1)
            }.width('100%').margin({ bottom: 8 })

            Row() {
              Text('🔵').fontSize(14).margin({ right: 8 })
              Text('总量').fontSize(13).fontColor(ThemeColors.textSecondary).width('20%')
              Text(this.authTotalFlow).fontSize(13).fontWeight(FontWeight.Bold)
                .fontColor('#1565C0').layoutWeight(1)
            }.width('100%')
          }.width('100%').padding(16).borderRadius(12).margin({ top: 12 })
            .backgroundColor(ThemeColors.bgCard)
            .shadow({ radius: 2, color: '#00000008', offsetY: 1 })

          // 在线设备
          if (this.authDeviceIp.length > 0) {
            Column() {
              Text('当前设备').fontSize(14).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
                .width('100%').margin({ bottom: 12 })

              Row() {
                Text('🌐').fontSize(14).margin({ right: 8 })
                Text('IP').fontSize(13).fontColor(ThemeColors.textSecondary).width('20%')
                Text(this.authDeviceIp).fontSize(13).fontColor(ThemeColors.textPrimary).layoutWeight(1)
              }.width('100%').margin({ bottom: 8 })

              Row() {
                Text('🕐').fontSize(14).margin({ right: 8 })
                Text('上线').fontSize(13).fontColor(ThemeColors.textSecondary).width('20%')
                Text(this.authOnlineTime).fontSize(13).fontColor(ThemeColors.textPrimary).layoutWeight(1)
              }.width('100%').margin({ bottom: 8 })

              if (this.authOnlineSeconds.length > 0) {
                Row() {
                  Text('⏱').fontSize(14).margin({ right: 8 })
                  Text('时长').fontSize(13).fontColor(ThemeColors.textSecondary).width('20%')
                  Text(this.authOnlineSeconds).fontSize(13).fontColor(ThemeColors.textPrimary).layoutWeight(1)
                }.width('100%').margin({ bottom: 8 })
              }

              if (this.authBytesIn.length > 0) {
                Row() {
                  Text('📊').fontSize(14).margin({ right: 8 })
                  Text('已用流量').fontSize(13).fontColor(ThemeColors.textSecondary).width('20%')
                  Text(this.authBytesIn).fontSize(13).fontColor(ThemeColors.textPrimary).layoutWeight(1)
                }.width('100%').margin({ bottom: 8 })
              }

              if (this.authUserMac.length > 0) {
                Row() {
                  Text('📟').fontSize(14).margin({ right: 8 })
                  Text('MAC').fontSize(13).fontColor(ThemeColors.textSecondary).width('20%')
                  Text(this.authUserMac).fontSize(12).fontColor(ThemeColors.textSecondary).layoutWeight(1)
                }.width('100%')
              }
            }.width('100%').padding(16).borderRadius(12).margin({ top: 12 })
              .backgroundColor(ThemeColors.bgCard)
              .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
          }

          // 结算日期
          if (this.authCheckoutDate.length > 0) {
            Row() {
              Text('📅').fontSize(14).margin({ right: 8 })
              Text('结算日期').fontSize(13).fontColor(ThemeColors.textSecondary).width('25%')
              Text(this.authCheckoutDate).fontSize(13).fontColor(ThemeColors.textPrimary).layoutWeight(1)
            }.width('100%').padding(16).borderRadius(12).margin({ top: 12 })
              .backgroundColor(ThemeColors.bgCard)
              .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
          }

          // 刷新按钮
          Button('刷新').fontSize(14).width('100%').height(42)
            .backgroundColor(this.accentColor).borderRadius(10)
            .margin({ top: 20, bottom: 20 })
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.loadAuthData(); })
        }.width('100%').padding({ left: 16, right: 16, top: 8 })
      }
    } else {
      Column() {
        Text('🌐').fontSize(48)
        Text('未连接校园网').fontSize(16).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
        Text('请确认已连接到校园WiFi或有线网络').fontSize(13).fontColor(ThemeColors.textHint).margin({ top: 4 })
        Button('重试').margin({ top: 16 }).hoverEffect(HoverEffect.Auto).onClick(() => { this.loadAuthData(); })
      }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
    }
  }

  // ===== ZFW 自服务平台 Tab UI =====

  @Builder
  ZfwTab(): void {
    if (this.zfwLoading) {
      Column() {
        LoadingProgress().width(40).height(40).color(this.accentColor)
        Text('加载中...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
      }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
    } else if (this.zfwState === 'idle') {
      Column() {
        Text('🔑').fontSize(40)
        Text('自服务平台').fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.textPrimary).margin({ top: 12 })
        Text('查看详细流量和在线设备信息').fontSize(13).fontColor(ThemeColors.textSecondary).margin({ top: 4 })

        if (!this.hasZfwPwd) {
          Text('未设置校园网密码，点击设置').fontSize(13).fontColor(this.accentColor).margin({ top: 12 })
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.openPwdDialog(); })
        } else {
          LoadingProgress().width(24).height(24).color(this.accentColor).margin({ top: 16 })
        }
      }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
    } else if (this.zfwState === 'needs_captcha') {
      Scroll() {
        Column() {
          Text('请输入验证码').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(ThemeColors.textPrimary).width('100%').margin({ bottom: 12 })

          if (this.zfwCaptchaBase64.length > 0) {
            Image(this.zfwCaptchaBase64).width(140).height(50).objectFit(ImageFit.Contain)
              .borderRadius(6).border({ width: 1, color: '#E0E0E0' })
              .hoverEffect(HoverEffect.Auto).onClick(() => {
                this.schoolnet.getZfwCaptcha().then((b64: string) => {
                  this.zfwCaptchaBase64 = b64;
                });
              })
            Text('点击图片刷新').fontSize(10).fontColor(ThemeColors.textHint).margin({ top: 4, bottom: 8 })
          }

          if (this.zfwErrorMsg.length > 0) {
            Text(this.zfwErrorMsg).fontSize(12).fontColor('#C62828').margin({ bottom: 8 })
          }

          TextInput({ placeholder: '请输入验证码', text: this.zfwCaptchaInput })
            .width('100%').height(42).fontSize(15).margin({ bottom: 12 })
            .onChange((value: string) => { this.zfwCaptchaInput = value; })

          Row() {
            Button('登录').fontSize(14).layoutWeight(1).height(42)
              .backgroundColor(this.accentColor).borderRadius(10)
              .hoverEffect(HoverEffect.Auto).onClick(() => { this.submitCaptcha(); })
              .enabled(this.zfwCaptchaInput.length > 0)
            Button('取消').fontSize(14).layoutWeight(1).height(42).margin({ left: 12 })
              .backgroundColor(ThemeColors.bgCard).fontColor(ThemeColors.textSecondary)
              .borderRadius(10).border({ width: 1, color: '#E0E0E0' })
              .hoverEffect(HoverEffect.Auto).onClick(() => { this.zfwState = 'idle'; this.zfwCaptchaInput = ''; })
          }.width('100%')
        }.width('100%').padding(20).borderRadius(12)
          .backgroundColor(ThemeColors.bgCard)
          .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
          .margin({ top: 20, left: 16, right: 16 })
      }
    } else if (this.zfwState === 'logged_in') {
      Scroll() {
        Column() {
          // 提示
          Row() {
            Text('⚠️').fontSize(14).margin({ right: 8 })
            Text('数据来自自服务平台(zfw)，仅供参考').fontSize(12).fontColor('#BF4D00')
          }.width('100%').padding(12).borderRadius(10)
            .backgroundColor('#FFF3E0').margin({ bottom: 12 })

          // 流量概览
          Column() {
            Row() {
              Text('流量概览').fontSize(14).fontWeight(FontWeight.Bold)
                .fontColor(ThemeColors.textPrimary).layoutWeight(1)
              Text('🔄 刷新').fontSize(12).fontColor(this.accentColor)
                .hoverEffect(HoverEffect.Auto).onClick(() => { this.startZfwFlow(); })
            }.width('100%').margin({ bottom: 12 })

            Row() {
              Column() {
                Text(this.zfwUsedFlow || '—').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#C62828')
                Text('已用流量').fontSize(11).fontColor(ThemeColors.textSecondary).margin({ top: 4 })
              }.layoutWeight(1)

              Column() {
                Text(this.zfwRemainFlow || '—').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#2E7D32')
                Text('剩余流量').fontSize(11).fontColor(ThemeColors.textSecondary).margin({ top: 4 })
              }.layoutWeight(1)

              Column() {
                Text(this.zfwSettleDate || '—').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#BF4D00')
                Text('结算日期').fontSize(11).fontColor(ThemeColors.textSecondary).margin({ top: 4 })
              }.layoutWeight(1)
            }.width('100%')
          }.width('100%').padding(16).borderRadius(12)
            .backgroundColor(ThemeColors.bgCard)
            .shadow({ radius: 2, color: '#00000008', offsetY: 1 })

          // 在线设备列表
          if (this.zfwIpList.length > 0) {
            Column() {
              Text('在线设备').fontSize(14).fontWeight(FontWeight.Bold)
                .fontColor(ThemeColors.textPrimary).width('100%').margin({ bottom: 12 })

              // 表头
              Row() {
                Text('IP地址').fontSize(11).fontColor(ThemeColors.textSecondary).layoutWeight(3)
                Text('上线时间').fontSize(11).fontColor(ThemeColors.textSecondary).layoutWeight(4)
                Text('使用流量').fontSize(11).fontColor(ThemeColors.textSecondary).layoutWeight(3)
              }.width('100%').padding({ bottom: 8 })
                .border({ width: { bottom: 0.5 }, color: '#E0E0E0' })

              ForEach(this.zfwIpList, (item: ZfwIpEntry, index: number) => {
                Row() {
                  Text(item.ip).fontSize(12).fontColor(ThemeColors.textPrimary)
                    .layoutWeight(3).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.onlineTime).fontSize(11).fontColor(ThemeColors.textSecondary)
                    .layoutWeight(4).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.usedFlow).fontSize(12).fontColor('#00ACC1')
                    .layoutWeight(3).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.width('100%').padding({ top: 10, bottom: 10 })
                  .border({ width: { bottom: 0.5 }, color: '#F0F0F0' })
              }, (item: ZfwIpEntry, index: number): string => index.toString())
            }.width('100%').padding(16).borderRadius(12).margin({ top: 12 })
              .backgroundColor(ThemeColors.bgCard)
              .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
          }

          // 退出登录按钮
          Button('退出登录').fontSize(13).width('100%').height(38)
            .backgroundColor(ThemeColors.bgCard).fontColor('#C62828')
            .borderRadius(10).border({ width: 1, color: '#FFCDD2' })
            .margin({ top: 20, bottom: 20 })
            .hoverEffect(HoverEffect.Auto).onClick(() => {
              this.zfwState = 'idle';
              this.zfwIpList = [];
              this.zfwUsedFlow = '';
              this.zfwRemainFlow = '';
              this.zfwSettleDate = '';
            })
        }.width('100%').padding({ left: 16, right: 16, top: 8 })
      }
    } else if (this.zfwState === 'error') {
      Column() {
        Text('⚠️').fontSize(40)
        Text(this.zfwErrorMsg || '加载失败').fontSize(14).fontColor('#C62828').margin({ top: 8 })
        Row() {
          Button('重试').fontSize(13).height(36)
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.startZfwFlow(); })
          if (this.zfwErrorMsg.includes('密码')) {
            Button('设置密码').fontSize(13).height(36).margin({ left: 12 })
              .backgroundColor(this.accentColor)
              .hoverEffect(HoverEffect.Auto).onClick(() => { this.openPwdDialog(); })
          }
          Button('取消').fontSize(13).height(36).margin({ left: 12 })
            .backgroundColor(ThemeColors.bgCard).fontColor(ThemeColors.textSecondary)
            .border({ width: 1, color: '#E0E0E0' })
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.zfwState = 'idle'; })
        }.margin({ top: 16 })
      }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
    }
  }

  build() {
    NavDestination() {
      Column() {
        SegmentTab({
          tabs: ['认证系统', '自服务平台'],
          currentIndex: $currentTab,
          accentColor: this.accentColor,
          onTabChange: (idx: number) => { if (idx === 1) this.loadZfwIfNeeded(); }
        }) {
          Column() { this.AuthTab() }.width('100%')
          Column() { this.ZfwTab() }.width('100%')
        }

        // 校园网密码弹窗
        if (this.showPwdDialog || this.pwdOpacity > 0) {
        Column() {
          Column() {
            Row() {
              Text('校园网密码').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              Blank()
              Row() { Text('\u2715').fontSize(18).fontColor(ThemeColors.textSecondary) }
                .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
                .justifyContent(FlexAlign.Center)
                .hoverEffect(HoverEffect.Auto).onClick(() => { this.closePwdDialog(); })
            }.width('100%').margin({ bottom: 16 })
            Text('用于查询自服务平台的详细流量数据').fontSize(12).fontColor(ThemeColors.textSecondary)
              .width('100%').margin({ bottom: 12 })
            TextInput({ placeholder: '输入校园网密码', text: this.pwdInput })
              .type(InputType.Password)
              .width('100%').height(44).fontSize(15)
              .backgroundColor(ThemeColors.bgInput).borderRadius(8)
              .onChange((v: string) => { this.pwdInput = v; })
            Row() {
              Button('取消').layoutWeight(1).height(40)
                .backgroundColor(ThemeColors.bgInput)
                .hoverEffect(HoverEffect.Auto).onClick(() => { this.closePwdDialog(); })
              Button('保存').layoutWeight(1).height(40).margin({ left: 12 })
                .backgroundColor(this.accentColor).fontColor('#FFFFFF')
                .hoverEffect(HoverEffect.Auto).onClick(async () => {
                  if (this.pwdInput.length > 0) {
                    try {
                      await SecureStorageUtil.put(SecureAlias.SCHOOLNET_PASSWORD, this.pwdInput);
                      const verify = await SecureStorageUtil.get(SecureAlias.SCHOOLNET_PASSWORD);
                      if (verify.length === 0) { this.zfwErrorMsg = '密码保存失败，请重试'; return; }
                    } catch (e) {
                      this.zfwErrorMsg = '密码保存失败: ' + String(e);
                      return;
                    }
                    this.hasZfwPwd = true;
                    // 同步到 AppStorage，MainPage 我的页面实时刷新
                    AppStorage.setOrCreate('schoolnet_pwd_status', '已设置');
                    this.closePwdDialog();
                    // 保存后自动开始查询
                    this.startZfwFlow();
                  }
                })
            }.width('100%').margin({ top: 16 })
          }
          .width('80%').padding(24).backgroundColor(ThemeColors.bgCard).borderRadius(16)
          .shadow({ radius: 20, color: '#30000000' })
          .opacity(this.pwdOpacity)
          .translate({ y: this.pwdTranslate })
          .hoverEffect(HoverEffect.Auto).onClick(() => {})
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .backgroundColor(ThemeColors.overlay)
        .opacity(this.pwdOpacity)
        .hitTestBehavior(this.showPwdDialog ? HitTestMode.Default : HitTestMode.None)
        .hoverEffect(HoverEffect.Auto).onClick(() => { this.closePwdDialog(); })
        }
      }.width('100%').height('100%').backgroundColor(ThemeColors.bgPage)
    }
    .title({ builder: this.buildWhiteTitle('校园网'), height: 52 + this.statusBarHeight }, { backgroundColor: this.accentColor })
    .hideBackButton(true).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .backgroundColor(ThemeColors.bgPage)
  }
}
