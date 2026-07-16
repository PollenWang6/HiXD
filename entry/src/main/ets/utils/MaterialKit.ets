// MaterialKit — 沉浸光感材质统一入口。
//
// 项目以稳定版 API（6.1.0/23）上架，@ohos.arkui.uiMaterial（@since 26.0.0）在该 SDK 中不存在，
// 故此处统一回退到非材质方案：Toast 不挂 systemMaterial，菜单使用 backgroundBlurStyle。
// 若后续升级到 API 26+ 并切回对应高版本 SDK，可恢复 uiMaterial 分支。
import { deviceInfo } from '@kit.BasicServicesKit';

/** 是否运行在支持系统材质（uiMaterial）的版本上；稳定版恒为 false，统一走回退 */
export const IS_MATERIAL_API: boolean = deviceInfo.distributionOSApiVersion >= 260000;

/**
 * Toast / Tips 用的系统沉浸材质。稳定版返回 undefined，调用方据此不设置 systemMaterial 字段。
 */
export function toastMaterial(): undefined {
  return undefined;
}

/**
 * 组件级沉浸材质。稳定版返回 undefined。
 */
export function componentMaterial(): undefined {
  return undefined;
}

/**
 * 菜单 / 长按菜单（bindMenu）的沉浸材质选项。
 * 稳定版回退到 backgroundBlurStyle（保持原 COMPONENT_THICK 毛玻璃）。
 */
export function menuOptions(): MenuOptions {
  return { backgroundBlurStyle: BlurStyle.COMPONENT_THICK };
}
