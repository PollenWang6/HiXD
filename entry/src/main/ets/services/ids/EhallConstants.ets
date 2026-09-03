// EhallConstants.ets — 共享的 ehall 常量（EHALL_HEADERS、APP_PATH_MAP、extractRaw）
import { HttpUtil, HttpResponse } from '../../utils/HttpUtil';
import { EHALL_APP_CLASS_TABLE, EHALL_APP_EXAM, EHALL_APP_SCORE, EHALL_APP_EMPTY_CLASSROOM } from '../../models/common/Models';
import { CasLoginService, NeedReAuthError } from '../auth/CasLoginService';

export const EHALL_HEADERS: Record<string, string> = {
  // Referer 必须 https：西电服务端按 Referer scheme 拼重定向 service 前缀
  'Referer': 'https://ehall.xidian.edu.cn/new/index_xd.html',
  'Host': 'ehall.xidian.edu.cn',
  'Accept': 'application/json, text/javascript, */*; q=0.01',
  'Accept-Language': 'zh-CN,zh;q=0.9',
  'Accept-Encoding': 'gzip, deflate, br',
  'Connection': 'keep-alive',
  'X-Requested-With': 'XMLHttpRequest',
};

export const APP_PATH_MAP: Map<string, string> = new Map([
  [EHALL_APP_CLASS_TABLE, '/jwapp/sys/wdkb'],
  [EHALL_APP_EXAM, '/jwapp/sys/studentWdksapApp'],
  [EHALL_APP_SCORE, '/jwapp/sys/cjcx'],
  [EHALL_APP_EMPTY_CLASSROOM, '/jwapp/sys/kxjas'],
]);

// ehall 会话失效：业务接口返回登录页 HTML 或 302 到 login。
// 独立异常类型而非裸 Error + 内部码，好处：
//   ① 上层可 instanceof 区分「需要重新登录」与「普通业务失败」，给不同 UI（重登入口 vs 重试）；
//   ② 直接携带面向用户的中文文案。此前抛 'EHALL_SESSION_EXPIRED' 内部码，
//      页面直接把英文码拼进「加载楼栋失败: EHALL_SESSION_EXPIRED」，体验很差。
export class EhallSessionExpiredError extends Error {
  constructor(msg: string = '登录状态已失效，请重新登录') {
    super(msg);
    this.name = 'EhallSessionExpiredError';
  }
}

// 服务端明确返回的业务失败（extParams.code != 1）。
// 对齐 Flutter score_session.dart：code != 1 直接 throw GetScoreFailedException(extParams.msg)。
// 不校验的话，「服务端报错」会被 extractRaw 当成「查无数据」返回空数组，页面显示空白/暂无成绩，
// 用户既看不到原因也无法判断是没数据还是出错了。
export class EhallDataError extends Error {
  constructor(msg: string) {
    super(msg);
    this.name = 'EhallDataError';
  }
}

// 校验 ehall / yjspt 响应里的 extParams.code：存在且 != 1 即抛 EhallDataError(msg)。
// 约定：code 缺省（部分模块不返回）不做断言，避免误伤；仅在服务端显式给出非 1 时才判定失败。
// 返回失败原因（空串 = 通过），由调用方决定抛出时机（须在写缓存之前，否则坏响应会被缓存）。
export function extParamsError(body: string): string {
  let verdict: string = '';
  try {
    const obj = JSON.parse(body) as Record<string, object>;
    const datas = obj['datas'] as Record<string, object>;
    if (datas === null || datas === undefined || typeof datas !== 'object') {
      return '';
    }
    for (const key of Object.keys(datas)) {
      const sub: object = datas[key];
      if (sub === null || sub === undefined || typeof sub !== 'object') {
        continue;
      }
      const ext: object = (sub as Record<string, object>)['extParams'];
      if (ext === null || ext === undefined || typeof ext !== 'object') {
        continue;
      }
      const extMap: Record<string, object> = ext as Record<string, object>;
      const code: object = extMap['code'];
      if (code === null || code === undefined) {
        continue;
      }
      if (Number(code) !== 1) {
        const msg: object = extMap['msg'];
        verdict = (msg !== null && msg !== undefined && String(msg).length > 0)
          ? String(msg)
          : '服务端返回异常（code=' + String(code) + '）';
        break;
      }
    }
  } catch (e) {
    // JSON 解析失败：不做断言，交由后续 extractRaw 的既有容错逻辑处理
    return '';
  }
  return verdict;
}

// 便捷断言：非 1 直接抛，供业务服务在写缓存前调用
export function assertExtParamsOk(body: string): void {
  const err: string = extParamsError(body);
  if (err.length > 0) {
    throw new EhallDataError(err);
  }
}

export class AppPostContext {
  readonly http: HttpUtil;
  readonly activateAppSession: (appId: string, force?: boolean) => Promise<void>;
  appSessionUrl: Record<string, string>;
  readonly tag: string;

  constructor(
    http: HttpUtil,
    activateAppSession: (appId: string, force?: boolean) => Promise<void>,
    appSessionUrl: Record<string, string>,
    tag: string
  ) {
    this.http = http;
    this.activateAppSession = activateAppSession;
    this.appSessionUrl = appSessionUrl;
    this.tag = tag;
  }
}

/** 共享 ehall 业务 POST — DRY：Class/Score/Exam/EmptyClassroom/Ehall 共用一个实现 */
export async function sharedAppPost(
  ctx: AppPostContext, path: string, body: Record<string, string>
): Promise<HttpResponse> {
  const url = 'https://ehall.xidian.edu.cn' + path;
  let resp = await ctx.http.postFormNoRedirect(url, body, EHALL_HEADERS);

  const isAuthFail = (r: HttpResponse): boolean =>
    (r.isRedirect && r.location != null && r.location.includes('login'))
    || r.body.trimStart().startsWith('<!') || r.body.trimStart().startsWith('<html');

  if (isAuthFail(resp)) {
    // 根因修复：会话过期时，陈旧 jsessionid 会让 activateAppSession 误判"已登录"而跳过 CAS 重登，
    // 导致 ehall 接口持续返回登录页 HTML → 解析空 → 页面空白。此处先刷新 CAS 登录态，
    // 再强制重新激活 app session（清掉陈旧 jsessionid）并重试一次，对齐 Flutter EhallSession 的透明重登。
    try {
      await CasLoginService.getInstance().checkAndAutoLogin();
    } catch (e) {
      // NeedReAuthError：静默续登遇到二次验证（信任设备被删/上限），必须抛给上层弹 reAuth 弹窗，
      // 不能在此吞掉——吞掉会导致"登录失效但不弹二次验证"，用户只能干等。
      if (e instanceof NeedReAuthError) {
        throw new EhallSessionExpiredError();
      }
      /* 其他错误忽略，继续尝试激活 */
    }
    ctx.appSessionUrl = {};
    const appId = findAppIdByPath(path);
    if (appId) {
      await ctx.activateAppSession(appId, true);
      resp = await ctx.http.postFormNoRedirect(url, body, EHALL_HEADERS);
    }
  }

  // 重试后仍为登录页/重定向 → 会话确实失效（未登录、信任设备被删、或 jsessionid 陈旧重签失败）。
  // 必须抛错：否则调用方会把登录页 HTML 当正常数据交给 CacheService.getOrFetch 缓存
  //（尤其空教室楼栋列表缓存 60min），造成"进去失败一次、之后怎么进都没用"的黏性失败。
  // 对齐 Flutter EhallSession：会话失效应抛异常暴露，由上层走错误展示/重登，而非静默返回 HTML。
  if (isAuthFail(resp)) {
    throw new EhallSessionExpiredError();
  }

  return resp;
}

/// ── 向后兼容别名（EhallService 内部仍可通过实例方法调用）──

export function findAppIdByPath(path: string): string {
  if (path.includes('wdkb')) return EHALL_APP_CLASS_TABLE;
  if (path.includes('studentWdksapApp') || path.includes('wdksap')) return EHALL_APP_EXAM;
  if (path.includes('cjcx')) return EHALL_APP_SCORE;
  if (path.includes('kxjas')) return EHALL_APP_EMPTY_CLASSROOM;
  return '';
}

export function extractRaw(body: string, tag: string): object[] {
  try {
    const obj = JSON.parse(body) as Record<string, object>;

    const datas = obj['datas'];
    if (datas !== null && typeof datas === 'object') {
      const datasMap = datas as Record<string, object>;
      for (const key of Object.keys(datasMap)) {
        const sub = datasMap[key];
        if (sub !== null && typeof sub === 'object') {
          const subMap = sub as Record<string, object>;
          const rows = subMap['rows'];
          if (Array.isArray(rows)) {
            return rows as object[];
          }
          const extParams = subMap['extParams'];
          if (extParams !== null && typeof extParams === 'object') {
            const extMap = extParams as Record<string, object>;
            const extRows = extMap['rows'];
            if (Array.isArray(extRows)) {
              return extRows as object[];
            }
          }
        }
      }
    }

    for (const second of Object.values(obj)) {
      if (second !== null && typeof second === 'object') {
        const smap: Record<string, object> = second as Record<string, object>;
        for (const third of Object.values(smap)) {
          if (third !== null && typeof third === 'object') {
            const tmap: Record<string, object> = third as Record<string, object>;
            const rows = tmap['rows'];
            if (Array.isArray(rows)) {
              return rows as object[];
            }
          }
        }
      }
    }

    return [];
  } catch (e) {
    return [];
  }
}
