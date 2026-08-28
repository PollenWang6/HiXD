// ScoreService.ets — 成绩数据服务
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { CacheService } from './CacheService';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { CasLoginService } from './CasLoginService';
import { ScoreItemModel, ScoreRow, ComposeDetail, EHALL_APP_SCORE } from './Models';
import { EHALL_HEADERS, APP_PATH_MAP, extractRaw, sharedAppPost, AppPostContext } from './EhallConstants';

const TAG = 'ScoreService';

export class ScoreService {
  private static inst: ScoreService;
  private http = HttpUtil.getInstance();
  private cache = CacheService.getInstance();
  private appSessionUrl: Record<string, string> = {};

  constructor() {}

  static getInstance(): ScoreService {
    if (!ScoreService.inst) ScoreService.inst = new ScoreService();
    return ScoreService.inst;
  }

  private async init(): Promise<void> { await this.cache.init(); }

  /**
   * 激活 app session
   */
  private async activateAppSession(appId: string, _force: boolean = false): Promise<void> {
    const appPath = APP_PATH_MAP.get(appId) || '/jwapp/sys/wdkb';

    // 对齐 Flutter useApp：每次都重新跑 appShow 拿新的 transfer URL（含新签发的 jsessionid），
    // 不复用内存里的 appSessionUrl 黏性跳过——否则一次失败/陈旧会话会永久卡死后续所有该 app 请求。
    // Flutter 在每次业务请求里都重新 useApp，故天然不会卡死。

    // 先确保 CAS 登录态有效（陈旧 jsessionid 不会自动触发重登，须主动刷新 MOD_AUTH_CAS）
    try { await CasLoginService.getInstance().checkAndAutoLogin(); } catch (e) { /* 忽略，继续尝试 */ }

    try {
      // 对齐 Flutter useApp：GET appShow 不跟随重定向，拿 302 Location（transfer URL，含 jsessionid）
      const resp = await this.http.getNoRedirect(
        'https://ehall.xidian.edu.cn/appShow?appId=' + appId,
        EHALL_HEADERS
      );
      let transferUrl: string | undefined = resp.location;
      if (transferUrl && transferUrl.length > 0) {
        if (transferUrl.startsWith('/')) {
          transferUrl = 'https://ehall.xidian.edu.cn' + transferUrl;
        }
        // 对齐 Flutter：去掉 ';jsessionid=...?' → '?'（jsessionid 已由 Set-Cookie 落入 cookie store）
        transferUrl = transferUrl.replace(/;jsessionid=[^?]*\?/, '?');
        // 对齐 Flutter dioEhall.post(get)：POST 到 transfer URL 真正建立该 app 会话
        try {
          await this.http.postEmpty(transferUrl, EHALL_HEADERS);
        } catch (e2) {
          // 302/跳转等非 2xx 视为激活成功（Flutter 同样不校验返回值）
        }
      } else {
        // 兼容兜底：拿不到 Location 时沿用旧 GET *default*/index.do 导航
        try {
          const directUrl = 'https://ehall.xidian.edu.cn' + appPath + '/%2Adefault%2A/index.do';
          await this.http.get(directUrl, EHALL_HEADERS);
        } catch (e3) {
        }
      }
    } catch (e) {
      // appShow 异常：再退一步用 GET *default*/index.do 兜底
      try {
        const directUrl = 'https://ehall.xidian.edu.cn' + appPath + '/%2Adefault%2A/index.do';
        await this.http.get(directUrl, EHALL_HEADERS);
      } catch (e3) {
      }
    }
  }

  private readonly _appCtx: AppPostContext = new AppPostContext(
    this.http,
    (appId: string, force: boolean = false) => this.activateAppSession(appId, force),
    this.appSessionUrl,
    TAG
  );

  private async appPost(path: string, body: Record<string, string>): Promise<HttpResponse> {
    return sharedAppPost(this._appCtx, path, body);
  }

  static extractRaw(body: string): object[] { return extractRaw(body, TAG); }

  async getScores(sid: string): Promise<string> {
    if (PreferenceUtil.getBool('role')) {
      const key: string = 'score_' + sid;
      return this.cache.getOrFetch<string>(key, async (): Promise<string> => {
        return this.getScoreYjspt();
      }, 5 * 60 * 1000);
    }
    await this.init();
    const key = 'score_' + sid;
    return this.cache.getOrFetch<string>(key, async (): Promise<string> => {
      await this.activateAppSession(EHALL_APP_SCORE);
      // 对齐 Flutter getScoreFromEhall：xscjcx.do 必须带完整查询参数，
      // 否则 ehall 返回 302 重定向，NETSTACK 自动跟随重定向链时 URL 校验失败(parameter error / 401)
      // querySetting 对应 Flutter json.encode({name:'SFYX',value:'1',linkOpt:'and',builder:'m_value_equal'})
      const querySetting: string = '[{"name":"SFYX","value":"1","linkOpt":"and","builder":"m_value_equal"}]';
      const body: Record<string, string> = {
        '*json': '1',
        'querySetting': querySetting,
        '*order': '+XNXQDM,KCH,KXH',
        'pageSize': '1000',
        'pageNumber': '1',
      };
      return (await this.appPost('/jwapp/sys/cjcx/modules/cjcx/xscjcx.do', body)).body;
    }, 5 * 60 * 1000);
  }

  // 判断成绩缓存是否为【未过期】的（用于区分「实时数据」与「离线缓存」）
  // CacheService.getOrFetch 在网络失败时已自动回退到过期缓存，
  // 因此 getScores 即便离线也可能返回数据；此函数用「未过期缓存」来判断数据是否新鲜，
  // 让页面在显示缓存数据时给出「离线/登录过期」提示而非假装实时。
  async isScoreCacheFresh(sid: string): Promise<boolean> {
    return (await this.cache.get('score_' + sid)) !== null;
  }

  async getScoreDetail(jxbid: string, semesterCode: string): Promise<ComposeDetail[]> {
    await this.init();
    await this.activateAppSession(EHALL_APP_SCORE);
    const sid = PreferenceUtil.getString('ids_account') || '';
    const body: Record<string, string> = {
      'JXBID': jxbid,
      'XH': sid,
      'XNXQDM': semesterCode,
      'CKLY': '1',
    };
    const resp = await this.appPost('/jwapp/sys/cjcx/modules/cjcx/cxkckgcxlrcj.do', body);
    const result: ComposeDetail[] = [];
    try {
      const obj = JSON.parse(resp.body) as Record<string, object>;
      const datas = obj['datas'] as Record<string, object>;
      const sub = datas['cxkckgcxlrcj'] as Record<string, object>;
      const rows = sub['rows'] as Record<string, string>[];
      if (rows.length > 0) {
        const row = rows[0];
        const formula = row['GCXKHLRCJGS'];
        const detailStr = row['KCGCXKHLRCJ'];
        if (formula && detailStr) {
          const formulaParts = formula.split(/ \+ |\*| = /);
          const detailParts = detailStr.split(',');
          const detailMap = new Map<string, string>();
          for (const dp of detailParts) {
            const kv = dp.split(':');
            if (kv.length === 2) detailMap.set(kv[0], kv[1]);
          }
          let i = 0;
          while (i < formulaParts.length) {
            const name = formulaParts[i].trim();
            if (name === '总评成绩') { i++; continue; }
            const ratio = formulaParts[i + 1] ? `${parseFloat(formulaParts[i + 1]) * 100}%` : '';
            const score = detailMap.get(name) || '未登记';
            result.push({ content: name, ratio: ratio, score: score } as ComposeDetail);
            i += 2;
          }
        }
      }
    } catch (e) {
    }
    return result;
  }

  // ==================== 研究生 (yjspt) API ====================

  async getScoreYjspt(): Promise<string> {
    const cas = CasLoginService.getInstance();
    const http = HttpUtil.getInstance();
    await cas.navigateToYjspt(
      'https://yjspt.xidian.edu.cn/gsapp/sys/wdcjapp/*default/index.do');
    const emptyArr: Object[] = [];
    const scoreBody: Record<string, Object> = {'querySetting':emptyArr,'pageSize':1000,'pageNumber':1};
    const resp: HttpResponse = await http.post(
      'https://yjspt.xidian.edu.cn/gsapp/sys/wdcjapp/modules/wdcj/xscjcx.do', scoreBody);
    const data: Record<string, Object> = resp.json<Record<string, Object>>();
    const datas: Record<string, Object> = data['datas'] as Record<string, Object>;
    const wdcj: Record<string, Object> = datas['xscjcx'] as Record<string, Object>;
    const rows: Object[] = wdcj['rows'] as Object[] || [];
    const wrapped: Record<string, string>[] = [];
    for (const r of rows) {
      const row: Record<string, Object> = r as Record<string, Object>;
      const out: Record<string, string> = {};
      out['XNXQDM'] = String(row['XNXQDM_DISPLAY'] ?? '');
      out['XSKCM'] = String(row['KCMC'] ?? '');
      // CJFZDM: 0=百分制, 1=三级, 2=五级, 3=两级
      const cjfzdm: string = String(row['CJFZDM'] ?? '0');
      const cjxsz: string = String(row['CJXSZ'] ?? '');
      // DJCJLXDM_DISPLAY — 分制显示名（ScorePage 用 '五级成绩' 判断分制）
      if (cjfzdm === '1') out['DJCJLXDM_DISPLAY'] = '三级成绩';
      else if (cjfzdm === '2') out['DJCJLXDM_DISPLAY'] = '五级成绩';
      else if (cjfzdm === '3') out['DJCJLXDM_DISPLAY'] = '两级成绩';
      else out['DJCJLXDM_DISPLAY'] = '';
      // ZCJ — 统一为数值，非百分制时从等级文字映射为数值
      if (cjfzdm === '0' || cjfzdm === '') {
        out['ZCJ'] = String(row['DYBFZCJ'] ?? '');
      } else {
        out['ZCJ'] = ScoreService.mapCjxsToNumber(cjxsz);
      }
      out['XF'] = String(row['XF'] ?? '');
      out['XGXKLBDM_DISPLAY'] = '';
      out['SFJG'] = String(row['SFJG'] ?? '');
      out['KCLBDM_DISPLAY'] = String(row['KCLBMC'] ?? '');
      out['CXCKDM_DISPLAY'] = '';
      out['JXBID'] = String(row['KCDM'] ?? '');
      wrapped.push(out);
    }
    const rowsObj: Record<string, Object> = {'rows': wrapped};
    const xscObj: Record<string, Object> = {'xscjcx': rowsObj};
    return JSON.stringify({'datas': xscObj});
  }

  // 等级文字 → 数值映射（用于 GPA 计算）
  static mapCjxsToNumber(cjxs: string): string {
    if (cjxs.includes('优秀') || cjxs.includes('优')) return '95';
    if (cjxs.includes('良好') || cjxs.includes('良')) return '85';
    if (cjxs.includes('中等') || cjxs.includes('中')) return '75';
    if (cjxs.includes('及格') || cjxs.includes('通过')) return '65';
    if (cjxs.includes('不及格') || cjxs.includes('不通过')) return '55';
    return '0';
  }

  static parseScores(body: string): ScoreItemModel[] {
    const raw: object[] = ScoreService.extractRaw(body);
    const out: ScoreItemModel[] = [];
    for (const row of raw) {
      const r: ScoreRow = row as ScoreRow;
      const item: ScoreItemModel = new ScoreItemModel();
      item.xnxqdm = String(r.XNXQDM ?? '');
      item.xskcm = String(r.XSKCM ?? '');
      item.zcj = String(r.ZCJ ?? '');
      item.xf = String(r.XF ?? '');
      item.xgxklbdmDisplay = String(r.XGXKLBDM_DISPLAY ?? '');
      item.sfjg = String(r.SFJG ?? '');
      item.kclbdmDisplay = String(r.KCLBDM_DISPLAY ?? '');
      item.cxckdmDisplay = String(r.CXCKDM_DISPLAY ?? '');
      item.djcjlxdmDisplay = String(r.DJCJLXDM_DISPLAY ?? '');
      item.jxbid = String(r.JXBID ?? '');
      out.push(item);
    }
    return out;
  }
}
