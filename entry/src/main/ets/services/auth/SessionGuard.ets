// SessionGuard.ets — 静默续登原子操作（对齐 traintime_pda 的 IDSSession.checkAndLogin）
//
// 设计目标：业务请求检测到会话过期时，先调用 ensureLoggedIn() 透明续登一次，
// 成功则原请求可重试、用户几乎无感；仅在遇到「需设备验证 / 密码错误 / 无保存凭证」
// 等无法静默处理的情况时抛 SessionExpiredError，由调用方回退到现有手动「重新登录」弹层。
//
// 与 HiXD 现有 doRelogin（TGC 优先 → 滑块兜底、原地弹层、含设备验证）的关系：
//   SessionGuard = 静默版（无 UI，滑块自动过）；doRelogin = 手动兜底。
//   先静默、失败再手动，正是 traintime_pda「checkAndLogin 先自动、UI 仅兜底」的哲学。

import { CasLoginService, NeedReAuthError, CasFormFields, LoginProgress, PasswordWrongException, AccountLockedException, LoginFailedException, CaptchaException, LoginPageException, ReAuthCancelledException, ReAuthExpiredException } from './CasLoginService';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { SecureStorageUtil, SecureAlias } from '../../utils/SecureStorageUtil';

// 会话过期且无法静默续登：交给 UI 走手动重新登录流程
export class SessionExpiredError extends Error {
  constructor(msg: string = '登录已过期，请重新登录') {
    super(msg);
    this.name = 'SessionExpiredError';
  }
}

export class SessionGuard {
  private static instance: SessionGuard | null = null;

  static getInstance(): SessionGuard {
    if (SessionGuard.instance === null) {
      SessionGuard.instance = new SessionGuard();
    }
    return SessionGuard.instance!;
  }

  // 并发续登合并锁（对齐 traintime_pda 的 _idslock）：多个业务请求同时过期，
  // 只真正续登一次，其余复用同一结果，避免重复弹/重复打 CAS。
  private inFlight: Promise<boolean> | null = null;

  // 确保登录态：TGC 静默恢复 → 失败则用保存凭证静默重登（滑块自动过，无 UI）。
  // 返回 true=已就绪；抛 SessionExpiredError=需手动处理。
  async ensureLoggedIn(onReAuthNeeded?: (username: string, onProgress?: (p: LoginProgress) => void) => Promise<boolean>): Promise<boolean> {
    if (this.inFlight) {
      return this.inFlight;
    }
    this.inFlight = this.ensureOnce(onReAuthNeeded);
    try {
      return await this.inFlight;
    } finally {
      this.inFlight = null;
    }
  }

  private async ensureOnce(onReAuthNeeded?: (username: string, onProgress?: (p: LoginProgress) => void) => Promise<boolean>): Promise<boolean> {
    const cas: CasLoginService = CasLoginService.getInstance();

    // 1) TGC 静默恢复（已有 cookie，无需密码、无 UI）
    try {
      if (await cas.tryAutoRestoreLogin()) {
        return true;
      }
    } catch (_e) {
      // TGC 探测失败，继续走凭证重登
    }

    // 2) 用保存的账号密码静默重登（滑块自动过，不弹 UI）
    const username: string = PreferenceUtil.getString('ids_account');
    const password: string = await SecureStorageUtil.get(SecureAlias.LOGIN_PASSWORD);
    if (!username || !password) {
      throw new SessionExpiredError('本地未保存登录凭证，请重新登录');
    }

    let fields: CasFormFields;
    try {
      fields = await cas.getLoginPageForm();
    } catch (e) {
      // 拉表单失败（多为网络问题）：交给调用方按离线处理
      const msg: string = (e instanceof Error && e.message) ? e.message : String(e);
      throw new SessionExpiredError(msg || '获取登录页失败，请检查网络');
    }

    if (!fields.execution) {
      // 拉表单过程中 TGC 又生效（CAS 直接 302 到 ehall）
      try {
        if (await cas.tryAutoRestoreLogin()) {
          return true;
        }
      } catch (_e) {
      }
    }

    // 优先自动过滑块；失败则回退手动（由调用方触发 doRelogin）
    let sliderOk: boolean = false;
    try {
      sliderOk = await cas.autoSolveSlider();
    } catch (_e) {
      sliderOk = false;
    }
    if (!sliderOk) {
      throw new SessionExpiredError('滑块验证失败，请手动重新登录');
    }

    try {
      // 传入 onReAuthNeeded → 若服务端要求设备验证，postLogin 直接弹二次验证弹窗；
      // 未传入则抛 NeedReAuthError，由调用方走手动登录流程。
      const ok: boolean = await cas.postLogin(username, password, fields, undefined, onReAuthNeeded);
      if (ok) {
        // 注：登录后"信任设备被删/推迟的 step-up 二次验证"不再用单独的 detectPendingReAuth()
        // 探测（对齐 Flutter followIDSRedirects 的内联识别）：后续 ehall 业务请求在 request()
        // 重定向跟随链中命中 reAuthLoginView 时会由 HttpUtil 内联触发全局 reAuth 处理器；
        // 若在校验环节被截，checkEhallLogin 会抛 NeedReAuthError 由上层兜弹验证码。
        await PreferenceUtil.putBool('is_logged_in', true);
        return true;
      }
      throw new SessionExpiredError('重新登录失败，请手动登录');
    } catch (e) {
      if (e instanceof NeedReAuthError) {
        throw new SessionExpiredError('需要设备验证，请手动重新登录');
      }
      // 密码错 / 账号冻结 / 登录失败等自定义异常：直接上抛，保留类型信息，
      // 让 MainPage 能精确判断失败原因并显示对应提示（对齐 traintime_pda）
      if (e instanceof PasswordWrongException || e instanceof AccountLockedException ||
          e instanceof LoginFailedException || e instanceof CaptchaException ||
          e instanceof LoginPageException || e instanceof ReAuthCancelledException ||
          e instanceof ReAuthExpiredException) {
        throw e as Error;
      }
      // 其他未知错误：包装为 SessionExpiredError
      const msg: string = (e instanceof Error && e.message) ? e.message : String(e);
      throw new SessionExpiredError(msg || '重新登录失败，请手动登录');
    }
  }
}
