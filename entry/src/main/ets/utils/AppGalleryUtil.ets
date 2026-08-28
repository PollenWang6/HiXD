// AppGalleryUtil.ets — 跳转到华为应用市场本应用详情页
// 用途：应用内"检查更新"引导用户通过官方应用市场更新，规避上架红线
// （AppGallery 禁止引导用户到应用市场以外的渠道下载/更新应用）。
import { productViewManager } from '@kit.StoreKit';
import { common, Want } from '@kit.AbilityKit';
import { ToastUtil } from './ToastUtil';

// 本应用在 AppGallery 的包名（与 AppScope/app.json5 的 bundleName 保持一致）
const APP_BUNDLE_NAME = 'com.HiXD.myapplication';

/**
 * 拉起华为应用市场中本应用的详情页，供用户走官方渠道更新。
 * 注意：仅当本应用已在应用市场上架后，该商店页才存在；首次上架前调用会因
 * 商店页不存在而失败，此时给出友好提示，绝不回退到外部下载链接（避免踩上架红线）。
 * @param context UIAbilityContext，用于启动应用市场视图
 */
export function openAppGalleryDetail(context: common.UIAbilityContext): void {
  try {
    const want: Want = { bundleName: APP_BUNDLE_NAME };
    productViewManager.loadProduct(context, want, {
      onError: (err: BusinessError) => {
        console.error('[AppGalleryUtil] loadProduct failed: ' + JSON.stringify(err));
        ToastUtil.show('未能打开应用市场，请在华为应用市场搜索「HiXD」查看更新');
      }
    });
  } catch (e) {
    console.error('[AppGalleryUtil] loadProduct exception: ' + (e as Error)?.message);
    ToastUtil.show('未能打开应用市场，请在华为应用市场搜索「HiXD」查看更新');
  }
}
