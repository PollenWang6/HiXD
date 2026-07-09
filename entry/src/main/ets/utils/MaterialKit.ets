// MaterialKit — HarmonyOS 7 (API 26) 系统材质（沉浸光感）统一入口。
//
// 背景：
// - `@ohos.arkui.uiMaterial` 为 @since 26.0.0，老设备（distributionOSApiVersion < 260000）运行时
//   并不提供该模块的符号，因此所有材质的「构造/调用」必须包裹在 IS_MATERIAL_API 守卫内，
//   老设备上返回 undefined，调用方据此跳过该字段，绝不触碰 uiMaterial。
// - 本文件是所有 API 26 沉浸光感能力的唯一来源，便于统一守卫与后续调整。
import uiMaterial from '@ohos.arkui.uiMaterial';
import { deviceInfo } from '@kit.BasicServicesKit';

/** 是否运行在 HarmonyOS 7 (API 26) 及以上 */
export const IS_MATERIAL_API: boolean = deviceInfo.distributionOSApiVersion >= 260000;

/**
 * Toast / Tips 用的系统沉浸材质。
 * 老设备返回 undefined，调用方（ToastUtil）据此不设置 systemMaterial 字段。
 */
export function toastMaterial(): uiMaterial.Material | undefined {
  if (!IS_MATERIAL_API) {
    return undefined;
  }
  return new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR });
}

/**
 * 组件级沉浸材质（用于支持 backgroundSystemMaterial 的组件，如 advanced Chip / SegmentButton）。
 * 注意：当前工程并未直接使用 advanced Chip / SegmentButton，此函数预留给后续接入。
 */
export function componentMaterial(): uiMaterial.Material | undefined {
  if (!IS_MATERIAL_API) {
    return undefined;
  }
  return new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR });
}

/**
 * 菜单 / 长按菜单（bindMenu）的沉浸材质选项。
 * - API 26+：挂系统材质（systemMaterial），获得 HarmonyOS 7 毛玻璃质感；
 * - 老设备：回退到 backgroundBlurStyle（保持原 COMPONENT_THICK 毛玻璃）。
 * 返回对象字面量，调用处直接 `bindMenu(builder, menuOptions())` 即可。
 */
export function menuOptions(): MenuOptions {
  if (!IS_MATERIAL_API) {
    return { backgroundBlurStyle: BlurStyle.COMPONENT_THICK };
  }
  return { systemMaterial: toastMaterial() };
}
