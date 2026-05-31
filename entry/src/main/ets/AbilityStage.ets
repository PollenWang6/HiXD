import { AbilityStage, Want } from '@kit.AbilityKit';

/**
 * AbilityStage 是应用模块运行时入口。
 * 每个模块首次启动时，系统会创建其实例并调用 onAcceptWant。
 */
export default class MyAbilityStage extends AbilityStage {
  onAcceptWant(want: Want): string {
    const params: Record<string, string> = want.parameters as Record<string, string>;
    const abilityName: string = params['abilityName'];
    return abilityName !== undefined ? abilityName : '';
  }
}
