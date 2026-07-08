// EhallConstants.ets — 共享的 ehall 常量（EHALL_HEADERS、APP_PATH_MAP、extractRaw）
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { EHALL_APP_CLASS_TABLE, EHALL_APP_EXAM, EHALL_APP_SCORE, EHALL_APP_EMPTY_CLASSROOM } from './Models';

export const EHALL_HEADERS: Record<string, string> = {
  'Referer': 'http://ehall.xidian.edu.cn/new/index_xd.html',
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
  const cookies = ctx.http.getCookiesForDomain('ehall.xidian.edu.cn');
  const hasCas: boolean = cookies.indexOf('MOD_AUTH_CAS') >= 0;
  const hasJsession: boolean = cookies.toLowerCase().indexOf('jsessionid') >= 0;
  let resp = await ctx.http.postForm(url, body, EHALL_HEADERS);

  if (resp.isRedirect && resp.location && resp.location.includes('login')) {
    ctx.appSessionUrl = {};
    const appId = findAppIdByPath(path);
    if (appId) {
      await ctx.activateAppSession(appId, true);
      resp = await ctx.http.postForm(url, body, EHALL_HEADERS);
    }
  }

  if (resp.body.trimStart().startsWith('<!') || resp.body.trimStart().startsWith('<html')) {
    ctx.appSessionUrl = {};
    const appId = findAppIdByPath(path);
    if (appId) {
      await ctx.activateAppSession(appId, true);
      resp = await ctx.http.postForm(url, body, EHALL_HEADERS);
    }
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
