// IDSSession.ets — IDS 登录会话（已改用 WebView 登录，此类仅保留兼容）
const TAG = 'IDSSession';

export class IDSSession {
  private static instance: IDSSession;

  private constructor() {}

  static getInstance(): IDSSession {
    if (!IDSSession.instance) IDSSession.instance = new IDSSession();
    return IDSSession.instance;
  }

  isLoggedIn(): boolean {
    // 登录状态检查已迁移到 EhallService.checkEhallLogin()
    return false;
  }
}