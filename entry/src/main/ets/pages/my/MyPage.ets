// MyPage.ets — "我的"页面
import { ThemeColors } from '../../utils/ThemeColors';
import { router } from '@kit.ArkUI';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { EhallService } from '../../services/EhallService';
import { common } from '@kit.AbilityKit';
import application from '@ohos.application';
import contextConstant from '@ohos.contextConstant';
import storageStatistics from '@ohos.storageStatistics';
import fileIo from '@ohos.fileio';

interface MenuItem {
  icon: string;
  title: string;
  subtitle: string;
  onClick: () => void;
}

@Entry
@Component
export struct MyPage {
  @State username: string = '';
  @State schoolnetPassword: string = '';
  @State isLoggedIn: boolean = false;
  @State isSchoolNetLoggedIn: boolean = false;
  @State menuItems: MenuItem[] = [];
  @State cacheSize: string = '计算中...';
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;

  aboutToAppear(): void {
    this.loadUserInfo();
    this.computeCacheSize();
  }

  // 计算并显示缓存大小
  private computeCacheSize(): void {
    try {
      storageStatistics.getCurrentBundleStats().then((dataSize: storageStatistics.BundleStats) => {
        this.cacheSize = this.formatBytes(dataSize.cacheSize);
      });
    } catch {
      this.cacheSize = '未知';
    }
  }

  private formatBytes(bytes: number): string {
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  }

  onPageShow(): void {
    this.loadUserInfo();
  }

  private loadUserInfo(): void {
    let loggedIn = PreferenceUtil.getBool('is_logged_in');
    this.username = PreferenceUtil.getString('ids_account');
    // 兜底：flag 可能因未刷盘而丢失，有登录痕迹就纠正
    if (!loggedIn) {
      const savedCas = PreferenceUtil.getString('mod_auth_cas');
      if (savedCas.length > 0 || this.username.length > 0) {
        loggedIn = true;
      }
    }
    this.isLoggedIn = loggedIn;
    this.schoolnetPassword = PreferenceUtil.getString('schoolnet_password');
    this.isSchoolNetLoggedIn = PreferenceUtil.getBool('schoolnet_logged_in');
    this.refreshMenuItems();
  }

  private refreshMenuItems(): void {
    const items: MenuItem[] = [];

    // 校园网登录入口
    if (this.isSchoolNetLoggedIn) {
      items.push({
        icon: '🌐',
        title: '校园网账号',
        subtitle: '已登录',
        onClick: () => {
          // 已登录，可以查看详情或重新登录
          router.pushUrl({ url: 'pages/schoolnet/SchoolNetLoginPage' });
        }
      });
    } else {
      items.push({
        icon: '🌐',
        title: '校园网登录',
        subtitle: '未登录，点击查看用量',
        onClick: () => {
          router.pushUrl({ url: 'pages/schoolnet/SchoolNetLoginPage' });
        }
      });
    }

    // 校园网查询密码设置
    items.push({
      icon: '🔑',
      title: '校园网查询密码',
      subtitle: this.schoolnetPassword.length > 0 ? '已设置' : '未设置',
      onClick: () => { router.pushUrl({ url: 'pages/schoolnet/SchoolNetPage' }); }
    });

    // 清除缓存
    items.push({
      icon: '🗑️',
      title: '清除缓存',
      subtitle: '当前 ' + this.cacheSize,
      onClick: () => {
        this.clearCache();
      }
    });

    this.menuItems = items;
  }

  // 清除缓存（不清 /web 和 /web/Cookies，保留登录态）
  private clearCache = async () => {
    this.cacheSize = '清理中...';
    try {
      let moduleContext: common.Context;
      moduleContext = await application.createModuleContext(this.context, 'entry');
      // 需要清理的缓存目录列表
      let paths: Array<string> = [moduleContext.cacheDir, moduleContext.cacheDir + '/web', this.context.cacheDir];
      // EL1 区域也清理
      moduleContext.area = contextConstant.AreaMode.EL1;
      paths.push(moduleContext.cacheDir);
      this.context.area = contextConstant.AreaMode.EL1;
      paths.push(this.context.cacheDir);
      this.context.area = contextConstant.AreaMode.EL2;

      for (let i = 0; i < paths.length; i++) {
        let path = paths[i];
        try {
          const filenames: string[] = await fileIo.listFile(path);
          for (let j = 0; j < filenames.length; j++) {
            let dirPath = path + '/' + filenames[j];
            // 跳过 WebView 缓存和 Cookies，保留登录态
            if (dirPath.endsWith('/web') || dirPath.endsWith('/web/Cookies')) {
              continue;
            }
            try {
              let isDirectory: boolean = fileIo.statSync(dirPath).isDirectory();
              if (isDirectory) {
                fileIo.rmdirSync(dirPath);
              } else {
                fileIo.unlink(dirPath).catch(() => {});
              }
            } catch {
              // 单个文件删除失败，继续
            }
          }
        } catch {
          // 目录不存在，跳过
        }
      }
    } catch (e) {
      console.error('MyPage', 'clearCache error: ' + String(e));
    }
    // 重新计算缓存大小
    this.computeCacheSize();
  }

  // 退出登录
  logout(): void {
    // 清除教务登录状态
    PreferenceUtil.putBool('is_logged_in', false);
    PreferenceUtil.putString('ids_account', '');
    // 清除校园网登录状态
    PreferenceUtil.putBool('schoolnet_logged_in', false);

    this.isLoggedIn = false;
    this.isSchoolNetLoggedIn = false;
    this.username = '';
    this.refreshMenuItems();

    // 跳转到登录页
    router.replaceUrl({ url: 'pages/Index' });
  }

  build() {
    Column() {
      // 顶部导航
      Row() {
        Image($r('sys.media.ohos_ic_public_arrow_left')).width(24).height(24).fillColor('#333333')
          .onClick(() => { router.back(); }).margin({ right: 12 })
        Text('我的').fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
      }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })
      .backgroundColor(ThemeColors.bgCard)
      Divider().color('#F0F0F0')

      if (!this.isLoggedIn) {
        // 未登录：显示登录按钮 + 引导 WebView 登录
        Column() {
          Text('请先登录').fontSize(16).fontColor(ThemeColors.textSecondary)
          Button('前往登录')
            .onClick(() => { router.pushUrl({ url: 'pages/login/LoginPage' }); })
            .margin({ top: 12 })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Column() {
          // 用户信息卡片
          Column() {
            Row() {
              Circle().width(56).height(56).fill('#2979FF')
              Column() {
                Text(this.username.length > 0 ? this.username : '已登录')
                  .fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
                Text('西电校园助手').fontSize(13).fontColor(ThemeColors.textSecondary).margin({ top: 4 })
              }.margin({ left: 16 })
            }.width('100%')
          }
          .width('100%').padding(20).backgroundColor(ThemeColors.bgCard)
          .margin({ left: 16, right: 16, top: 16 }).borderRadius(16)

          // 菜单列表
          List() {
            ForEach(this.menuItems, (item: MenuItem) => {
              ListItem() {
                Row() {
                  Text(item.icon).fontSize(20).margin({ right: 14 })
                  Column() {
                    Text(item.title).fontSize(15).fontColor(ThemeColors.textPrimary)
                    Text(item.subtitle).fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
                  }.layoutWeight(1)
                  Text('›').fontSize(18).fontColor('#CCCCCC')
                }.width('100%').padding(16)
                .onClick(() => { item.onClick(); })
              }.backgroundColor(ThemeColors.bgCard).margin({ left: 16, right: 16, top: 8 }).borderRadius(16)
            })

            // 退出登录按钮
            ListItem() {
              Row() {
                Text('🚪').fontSize(20).margin({ right: 14 })
                Text('退出登录').fontSize(15).fontColor('#FF4D4F')
                Blank()
              }.width('100%').padding(16)
              .onClick(() => { this.logout(); })
            }
            .backgroundColor(ThemeColors.bgCard)
            .margin({ left: 16, right: 16, top: 8 })
            .borderRadius(16)
          }.layoutWeight(1).padding({ bottom: 16 })
        }.width('100%').layoutWeight(1)
      }
    }.width('100%').height('100%').backgroundColor('#F8F9FA')
  }
}
