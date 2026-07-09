// ToastUtil — 统一封装 promptAction.showToast，并在 API 26 上自动附加系统沉浸材质（沉浸光感）。
//
// 用法：将各页面的 `promptAction.showToast({ message: ... })` 替换为 `ToastUtil.show(...)`，
// 即可在 HarmonyOS 7 设备上获得系统级毛玻璃/沉浸质感，老设备自动降级为普通 Toast。
import { promptAction, ShowToastOptions } from '@kit.ArkUI';
import { toastMaterial } from './MaterialKit';

export class ToastUtil {
  /**
   * 显示 Toast，并在 API 26 及以上自动附加系统沉浸材质。
   * @param message 文案
   * @param duration 可选，显示时长（毫秒）
   */
  static show(message: string, duration?: number): void {
    // systemMaterial 是 API 26 新增字段，旧版 ShowToastOptions 类型未含；用 ESObject 动态赋值，
    // 运行时由 promptAction 读取（老设备忽略未知字段），避免类型报错。
    const param: ESObject = { message };
    if (duration !== undefined) {
      param.duration = duration;
    }
    param.systemMaterial = toastMaterial();
    promptAction.showToast(param as ShowToastOptions);
  }
}
