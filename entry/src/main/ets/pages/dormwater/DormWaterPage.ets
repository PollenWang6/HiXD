import { ToastUtil } from '../../utils/ToastUtil';
﻿// DormWaterPage.ets — 宿舍水机控制页面
import { DormWaterService, DormWaterDevice, CaptchaData } from '../../services/DormWaterService';
import { ThemeColors } from '../../utils/ThemeColors';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { scanCore, scanBarcode } from '@kit.ScanKit';
import { BusinessError } from '@kit.BasicServicesKit';
@Component
export struct DormWaterPage {
  pageInfo: NavPathStack = new NavPathStack();
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  private accentTextColor(): string {
    const hex = this.accentColor.replace('#', '');
    const r = parseInt(hex.substring(0, 2), 16);
    const g = parseInt(hex.substring(2, 4), 16);
    const b = parseInt(hex.substring(4, 6), 16);
    const lum = (0.299 * r + 0.587 * g + 0.114 * b);
    return lum > 160 ? '#333333' : '#FFFFFF';
  }

  // 登录态
  @State loggedIn: boolean = false;
  @State loginLoading: boolean = false;
  @State loginMsg: string = '';
  @State phone: string = '';
  @State captchaBase64: string = '';
  @State imageCode: string = '';
  @State smsCode: string = '';
  @State smsCountdown: number = 0;
  @State captchaLoading: boolean = false;

  // 设备列表
  @State devices: DormWaterDevice[] = [];
  @State loading: boolean = false;
  @State errorMsg: string = '';

  // 运行中设备
  @State runningDeviceId: string = '';
  @State runningMsg: string = '';
  private statusTimer: number = -1;
  private smsTimer: number = -1;

  // 手动添加弹窗
  @State showManualAdd: boolean = false;
  @State manualDeviceId: string = '';

  private svc: DormWaterService = DormWaterService.getInstance();

    @Builder buildWhiteTitle(t: string) {
    Row() {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.close'))
          .height(22)
          .fillColor(ThemeColors.textPrimary)
          .draggable(false)
      }
      .height(40).width(40)
      .onClick(() => { this.pageInfo.pop(); })
      Text(t)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.accentTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .height(52 + this.statusBarHeight)
    .padding({ left: 12, right: 16, top: this.statusBarHeight })
  }

  aboutToAppear(): void {
    // 检查是否已登录
    const token: string = PreferenceUtil.getString('dorm_water_token');
    if (token.length > 0) {
      this.loggedIn = true;
      this.loadDevices();
    } else {
      // 未登录，自动加载验证码
      this.loadCaptcha();
    }
  }

  aboutToDisappear(): void {
    this.clearStatusTimer();
    if (this.smsTimer >= 0) { clearInterval(this.smsTimer); this.smsTimer = -1; }
  }

  private clearStatusTimer(): void {
    if (this.statusTimer >= 0) { clearInterval(this.statusTimer); this.statusTimer = -1; }
  }

  // ===== 加载设备列表 =====
  async loadDevices(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      this.devices = await this.svc.getDeviceList();
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      if (msg.indexOf('过期') >= 0 || msg.indexOf('登录') >= 0) {
        this.svc.logout();
        this.loggedIn = false;
        this.devices = [];
        this.loginMsg = '登录已过期，请重新登录';
        this.loadCaptcha();
      } else {
        this.errorMsg = msg;
      }
    } finally {
      this.loading = false;
    }
  }

  // ===== 加载验证码（进入页面自动调用）=====
  async loadCaptcha(): Promise<void> {
    this.captchaLoading = true;
    try {
      const cd: CaptchaData = await this.svc.getCaptcha();
      this.captchaBase64 = cd.imageBase64;
    } catch (e) {
      this.loginMsg = '验证码获取失败，请重试';
    } finally {
      this.captchaLoading = false;
    }
  }

  // ===== 扫码添加设备 =====
  async doScanAdd(): Promise<void> {
    try {
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.ALL],
        enableMultiMode: false,
        enableAlbum: false
      };

      // startScanForResult 是 callback 形式，用 Promise 包装
      const result: scanBarcode.ScanResult = await new Promise<scanBarcode.ScanResult>(
        (resolve, reject) => {
          scanBarcode.startScanForResult(
            this.getUIContext().getHostContext(),
            options,
            (error: BusinessError, result: scanBarcode.ScanResult) => {
              if (error) { reject(error); return; }
              resolve(result);
            }
          );
        });

      if (!result || !result.originalValue) { return; }

      const url: string = result.originalValue;
      const deviceId: string = this.extractDeviceIdFromUrl(url);
      if (!deviceId) {
        ToastUtil.show('无效的水机二维码');
        return;
      }

      await this.svc.toggleFavorite(deviceId, false);
      ToastUtil.show('设备添加成功');
      this.loadDevices();
    } catch (e) {
      ToastUtil.show('扫码失败，请重试');
    }
  }

  private extractDeviceIdFromUrl(url: string): string {
    // https://i.hnkzy.com/q/1/{deviceId}
    const idx: number = url.lastIndexOf('/');
    if (idx < 0) return '';
    return url.substring(idx + 1);
  }

  // ===== 手动输入设备编号 =====
  async doManualAdd(): Promise<void> {
    const id: string = this.manualDeviceId.trim();
    if (id.length === 0) { ToastUtil.show('请输入设备编号'); return; }
    try {
      await this.svc.toggleFavorite(id, false);
      ToastUtil.show('设备添加成功');
      this.showManualAdd = false;
      this.manualDeviceId = '';
      this.loadDevices();
    } catch (e) {
      ToastUtil.show('添加失败');
    }
  }

  // ===== 发送短信 =====
  async doSendSms(): Promise<void> {
    if (this.phone.length !== 11) { this.loginMsg = '请输入正确手机号'; return; }
    if (this.imageCode.length === 0) { this.loginMsg = '请输入图形验证码'; return; }
    this.loginLoading = true;
    this.loginMsg = '';
    try {
      await this.svc.sendSmsCode(this.phone, this.imageCode);
      this.loginMsg = '短信已发送';
      this.smsCountdown = 60;
      this.smsTimer = setInterval(() => {
        this.smsCountdown--;
        if (this.smsCountdown <= 0) { clearInterval(this.smsTimer); this.smsTimer = -1; }
      }, 1000);
    } catch (e) {
      this.loginMsg = (e as Error).message;
      this.loadCaptcha(); // 刷新验证码
    } finally {
      this.loginLoading = false;
    }
  }

  // ===== 登录 =====
  async doLogin(): Promise<void> {
    if (this.smsCode.length === 0) { this.loginMsg = '请输入短信验证码'; return; }
    this.loginLoading = true;
    this.loginMsg = '';
    try {
      await this.svc.login(this.phone, this.smsCode);
      // 登录成功，p就会通过 PreferenceUtil 持久化
      this.loggedIn = true;
      this.loadDevices();
    } catch (e) {
      this.loginMsg = (e as Error).message;
    } finally {
      this.loginLoading = false;
    }
  }

  // ===== 开始接水 =====
  async doStartWater(dev: DormWaterDevice): Promise<void> {
    try {
      await this.svc.startWater(dev.id);
      this.runningDeviceId = dev.id;
      this.runningMsg = dev.name + ' 正在出水...';
      this.startStatusPolling(dev.id);
    } catch (e) {
      ToastUtil.show('启动失败: ' + (e as Error).message);
    }
  }

  // ===== 停止接水 =====
  async doEndWater(dev: DormWaterDevice): Promise<void> {
    this.clearStatusTimer();
    try {
      await this.svc.endWater(dev.id);
      this.runningDeviceId = '';
      this.runningMsg = dev.name + ' 已停止';
    } catch (e) {
      ToastUtil.show('停止失败');
    }
  }

  // ===== 删除设备 =====
  async doRemoveDevice(dev: DormWaterDevice): Promise<void> {
    try {
      await this.svc.toggleFavorite(dev.id, true);
      this.devices = this.devices.filter((d: DormWaterDevice) => d.id !== dev.id);
      ToastUtil.show('已移除 ' + dev.name);
    } catch (e) {
      ToastUtil.show('移除失败');
    }
  }

  // ===== 状态轮询 =====
  private startStatusPolling(deviceId: string): void {
    this.clearStatusTimer();
    let idleCount: number = 0;
    this.statusTimer = setInterval(async () => {
      try {
        const status: number = await this.svc.checkDeviceStatus(deviceId);
        if (status === 99) {
          idleCount++;
          if (idleCount >= 3) {
            this.clearStatusTimer();
            this.runningDeviceId = '';
            this.runningMsg = '接水完成 ✓';
          }
        } else {
          idleCount = 0;
        }
      } catch (_) { idleCount = 0; }
    }, 3000);
  }

  // ===== 登出 =====
  doLogout(): void {
    this.svc.logout();
    this.loggedIn = false;
    this.devices = [];
    this.phone = '';
    this.smsCode = '';
    this.imageCode = '';
    this.captchaBase64 = '';
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          if (this.loggedIn) {
            Row() {
              Blank()
              Button('退出').fontSize(13).fontColor('#FF7043').backgroundColor('#00000000')
                .onClick(() => { this.doLogout(); })
            }.width('100%').padding({ right: 16, top: 4 })
          }

          if (this.loggedIn) {
            this.buildDeviceList();
          } else {
            this.buildLoginForm();
          }
        }
        .width('100%').height('100%').backgroundColor(ThemeColors.bgPage)

        // 手动添加弹窗
        if (this.showManualAdd) {
          this.buildManualAddDialog()
        }
      }
    }
    .title({ builder: this.buildWhiteTitle('宿舍水机'), height: 52 + this.statusBarHeight }, { backgroundColor: this.accentColor })
    .hideBackButton(true).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onBackPressed(() => { this.pageInfo.pop(); return true; })
    .backgroundColor(ThemeColors.bgPage)
  }

  // ===== 设备列表 UI =====
  @Builder
  buildDeviceList() {
    Column() {
      if (this.runningMsg.length > 0) {
        Row() {
          Text(this.runningMsg).fontSize(14).fontColor(ThemeColors.textPrimary).layoutWeight(1)
          if (this.runningDeviceId.length > 0) {
            Text('停止').fontSize(13).fontColor(ThemeColors.textPrimary)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor('#FFFFFF44').borderRadius(6)
              .onClick(() => {
                const dev: DormWaterDevice | undefined = this.devices.find(
                  (d: DormWaterDevice): boolean => d.id === this.runningDeviceId);
                if (dev) this.doEndWater(dev);
              })
          }
        }
        .width('100%').padding(12)
        .backgroundColor('#4CAF50').borderRadius(10)
        .margin({ left: 16, right: 16, top: 12 })
      }

      // 扫码 / 手动添加按钮
      Row({ space: 10 }) {
        Button() {
          Row() {
            Text('📷').fontSize(16)
            Text('扫码添加').fontSize(14)
          }
        }
        .backgroundColor(this.accentColor + '15').fontColor(this.accentColor)
        .borderRadius(10).height(40).layoutWeight(1)
        .onClick(() => { this.doScanAdd(); })

        Button() {
          Row() {
            Text('✏️').fontSize(16)
            Text('手动添加').fontSize(14)
          }
        }
        .backgroundColor(ThemeColors.bgInput).fontColor(ThemeColors.textSecondary)
        .borderRadius(10).height(40).layoutWeight(1)
        .onClick(() => { this.showManualAdd = true; })
      }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 4 })

      if (this.loading) {
        LoadingProgress().margin({ top: 40 })
      } else if (this.errorMsg.length > 0) {
        Column() {
          Text(this.errorMsg).fontSize(14).fontColor('#FF7043').margin({ top: 40 })
          Text('重试').fontSize(14).fontColor(this.accentColor).margin({ top: 12 })
            .onClick(() => { this.loadDevices(); })
        }
      } else if (this.devices.length > 0) {
        List({ space: 12 }) {
          ForEach(this.devices, (dev: DormWaterDevice) => {
            ListItem() { this.buildDeviceCard(dev) }
          })
        }
        .width('100%').layoutWeight(1).padding({ left: 16, right: 16, top: 8 })
      } else {
        Column() {
          Text('🚰').fontSize(48).margin({ top: 60 })
          Text('暂无绑定设备').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
          Text('点击上方「扫码添加设备」扫描水机上二维码').fontSize(12).fontColor(ThemeColors.textHint).margin({ top: 4 })
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      }
    }
    .width('100%').layoutWeight(1)
  }

  @Builder
  buildDeviceCard(dev: DormWaterDevice) {
    Row() {
      Column() {
        Text(dev.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(dev.id).fontSize(11).fontColor(ThemeColors.textHint).margin({ top: 2 })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)

      if (this.runningDeviceId === dev.id) {
        Text('出水中...').fontSize(13).fontColor('#4CAF50')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .border({ width: 1, color: '#4CAF50', radius: 8 })
      } else {
        Text('开始接水').fontSize(13).fontColor(ThemeColors.textOnColor(this.accentColor))
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor(this.accentColor).borderRadius(8)
          .onClick(() => { this.doStartWater(dev); })
      }

      // 长按删除
      Text('✕').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ left: 12 })
        .onClick(() => { this.doRemoveDevice(dev); })
    }
    .width('100%').padding(16)
    .backgroundColor(ThemeColors.bgCard).borderRadius(12)
    .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
  }

  // ===== 手动添加设备弹窗 =====
  @Builder
  buildManualAddDialog() {
    Column() {
      Column() {
        Text('手动添加设备').fontSize(16).fontWeight(FontWeight.Bold)
          .fontColor(ThemeColors.textPrimary).margin({ bottom: 16 })
        Text('请输入水机上的设备编号').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ bottom: 12 })
        TextInput({ placeholder: '设备编号', text: this.manualDeviceId })
          .width('100%').height(44)
          .backgroundColor(ThemeColors.bgInput).borderRadius(8).padding({ left: 12 })
          .type(InputType.Number)
          .onChange((v: string) => { this.manualDeviceId = v; })
        Row({ space: 10 }) {
          Button('取消').layoutWeight(1).height(40)
            .backgroundColor(ThemeColors.bgInput).fontColor(ThemeColors.textPrimary).borderRadius(10)
            .onClick(() => { this.showManualAdd = false; this.manualDeviceId = ''; })
          Button('添加').layoutWeight(1).height(40)
            .backgroundColor(this.accentColor).fontColor(ThemeColors.textOnColor(this.accentColor)).borderRadius(10)
            .onClick(() => { this.doManualAdd(); })
        }.width('100%').margin({ top: 16 })
      }
      .width('80%').padding(24).backgroundColor(ThemeColors.bgCard).borderRadius(16)
      .shadow({ radius: 20, color: '#30000000' })
      .onClick(() => {})
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeColors.overlay)
    .onClick(() => { this.showManualAdd = false; this.manualDeviceId = ''; })
  }

  // ===== 登录表单 UI =====
  @Builder
  buildLoginForm() {
    Scroll() {
      Column() {
        Text('🚰').fontSize(48).margin({ top: 24, bottom: 4 })
        Text('登录慧生活798').fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor(ThemeColors.textPrimary).margin({ bottom: 8 })
        Text('请使用「慧生活798」APP 或支付宝小程序\n充值余额或开通免密支付后使用')
          .fontSize(11).fontColor(ThemeColors.textHint).textAlign(TextAlign.Center)
          .margin({ bottom: 14 })

        // 手机号
        this.inputRow('📱', '手机号', true, (v: string) => { this.phone = v; })
        Divider().color(ThemeColors.border).margin({ left: 48 })

        // 图形验证码（自动加载）
        Row() {
          Text('🔐').fontSize(18).margin({ right: 10 })
          TextInput({ placeholder: '图形验证码', text: this.imageCode })
            .layoutWeight(1).height(44).backgroundColor('#00000000')
            .maxLength(6).type(InputType.Number)
            .onChange((v: string) => { this.imageCode = v; })
          if (this.captchaBase64.length > 0) {
            Image('data:image/png;base64,' + this.captchaBase64)
              .width(90).height(36).objectFit(ImageFit.Contain).borderRadius(4).margin({ left: 8 })
              .onClick(() => { this.loadCaptcha(); })
          } else if (this.captchaLoading) {
            LoadingProgress().width(20).height(20).margin({ left: 8 })
          } else {
            Text('加载失败').fontSize(12).fontColor('#FF7043')
              .width(90).height(36).textAlign(TextAlign.Center)
              .border({ width: 1, color: '#FF7043', radius: 4 }).margin({ left: 8 })
              .onClick(() => { this.loadCaptcha(); })
          }
        }
        .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
        Divider().color(ThemeColors.border).margin({ left: 48 })

        // 短信验证码
        Row() {
          Text('✉️').fontSize(18).margin({ right: 10 })
          TextInput({ placeholder: '短信验证码', text: this.smsCode })
            .layoutWeight(1).height(44).backgroundColor('#00000000')
            .type(InputType.Number).maxLength(6)
            .onChange((v: string) => { this.smsCode = v; })
          Button(this.smsCountdown > 0 ? this.smsCountdown + 's' : '获取验证码')
            .fontSize(12).height(32)
            .backgroundColor(this.smsCountdown > 0 ? ThemeColors.bgInput : this.accentColor)
            .fontColor(this.smsCountdown > 0 ? ThemeColors.textSecondary : ThemeColors.textOnColor(this.accentColor))
            .borderRadius(6).enabled(this.smsCountdown === 0)
            .onClick(() => { this.doSendSms(); })
        }
        .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
        Divider().color(ThemeColors.border).margin({ left: 48 })

        if (this.loginMsg.length > 0) {
          Text(this.loginMsg).fontSize(13).width('100%').textAlign(TextAlign.Center)
            .fontColor(this.loginMsg.indexOf('失败') >= 0 || this.loginMsg.indexOf('错误') >= 0 ? '#FF7043' : '#4CAF50')
            .margin({ top: 12 })
        }

        Button(this.loginLoading ? '登录中...' : '登 录')
          .width('100%').height(46)
          .fontSize(16).fontColor(ThemeColors.textOnColor(this.accentColor))
          .backgroundColor(this.accentColor).borderRadius(10)
          .margin({ left: 16, right: 16, top: 24 })
          .enabled(!this.loginLoading)
          .onClick(() => { this.doLogin(); })
      }
      .width('100%')
    }
    .width('100%').layoutWeight(1).align(Alignment.Top)
  }

  @Builder
  inputRow(icon: string, placeholder: string, isPhone: boolean, onChange: (v: string) => void) {
    Row() {
      Text(icon).fontSize(18).margin({ right: 10 })
      TextInput({ placeholder: placeholder })
        .layoutWeight(1).height(44).backgroundColor('#00000000')
        .type(isPhone ? InputType.PhoneNumber : InputType.Normal)
        .maxLength(isPhone ? 11 : 4)
        .onChange(onChange)
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }
}
