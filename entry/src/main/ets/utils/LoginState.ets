// LoginState.ets — 全局登录状态工具
// 提供统一的登录状态检查，避免各页面重复写 AppStorage.get('loginStatus') 判断。
// 对齐 Flutter IDSSession.offline：只有 loginStatus === 'ok' 才算已登录。

import { ToastUtil } from './ToastUtil';

export type LoginStatus = '' | 'checking' | 'offline' | 'expired' | 'not_logged_in' | 'ok' | 'timeout' | 'online';

export class LoginState {
  /** 当前登录状态（从 AppStorage 读取，MainPage 维护） */
  static getStatus(): LoginStatus {
    const v: string | undefined = AppStorage.get<string>('loginStatus');
    return (v ?? '') as LoginStatus;
  }

  /** 是否已登录（只有 'ok' 算已登录，对齐 Flutter offline 判定） */
  static isLoggedIn(): boolean {
    return LoginState.getStatus() === 'ok';
  }

  /** 是否处于离线/过期状态（有缓存但会话失效） */
  static isOffline(): boolean {
    const s: LoginStatus = LoginState.getStatus();
    return s === 'offline' || s === 'expired' || s === 'timeout';
  }

  /**
   * 要求已登录才能继续。未登录时显示 toast，返回 false。
   * 用法：if (!LoginState.requireLogin()) return;
   */
  static requireLogin(toastMsg?: string): boolean {
    if (LoginState.isLoggedIn()) return true;
    const msg: string = toastMsg ?? '请先登录校园账号';
    ToastUtil.show(msg);
    return false;
  }
}
