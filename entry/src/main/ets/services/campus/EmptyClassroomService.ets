// EmptyClassroomService.ets — 空闲教室数据服务
import { HttpUtil, HttpResponse } from '../../utils/HttpUtil';
import { CacheService } from '../common/CacheService';
import { EmptyClassroomItem, BuildingInfo, BuildingRow, EmptyClassroomRow,
         EHALL_APP_EMPTY_CLASSROOM } from '../../models/common/Models';
import { EHALL_HEADERS, extractRaw, sharedAppPost, AppPostContext } from '../ids/EhallConstants';
import { SemesterUtil } from '../ids/EhallService';
import { CasLoginService } from '../auth/CasLoginService';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'EmptyClassroomService';

export class EmptyClassroomService {
  private static inst: EmptyClassroomService;
  private http = HttpUtil.getInstance();
  private cache = CacheService.getInstance();
  private appSessionUrl: Record<string, string> = {};

  constructor() {}

  static getInstance(): EmptyClassroomService {
    if (!EmptyClassroomService.inst) EmptyClassroomService.inst = new EmptyClassroomService();
    return EmptyClassroomService.inst;
  }

  private async init(): Promise<void> { await this.cache.init(); }

  static extractRaw(body: string): object[] { return extractRaw(body, TAG); }

  private async activateAppSession(appId: string, _force: boolean = false): Promise<void> {
    const appPath = '/jwapp/sys/kxjas';

    // 对齐 Flutter useApp：每次都重新跑 appShow 拿新的 transfer URL（含新签发的 jsessionid），
    // 不复用内存里的 appSessionUrl 黏性跳过——否则一次失败/陈旧会话会永久卡死后续所有空教室请求
    //（表现为"进去失败一次，后面再怎么进都没用"）。Flutter 在每次 getBuildingList/searchData 里
    // 都重新 useApp，故天然不会卡死。

    // 先确保 CAS 登录态有效（陈旧 jsessionid 不会自动触发重登，须主动刷新 MOD_AUTH_CAS，
    // 否则 appShow 重定向无法签发新的 jsessionid）
    // ⚠️ 鉴权类异常必须原样上抛：此前此处 catch 后无条件忽略，把「登录已失效 / 需要设备验证」
    // 降级成一次普通请求失败，用户只会看到「未获取到楼栋列表」，根本不知道要去重新登录。
    try {
      await CasLoginService.getInstance().checkAndAutoLogin();
    } catch (e) {
      // ArkTS 严格模式：throw 只接受 Error 子类型（arkts-limited-throw），catch 到的需显式收窄
      const err: Error = e as Error;
      if (CasLoginService.isAuthError(err)) {
        throw err;
      }
      // 网络抖动等非鉴权错误：不阻断，继续尝试 appShow（TGC 可能仍有效）
      hilog.warn(0x0000, TAG, 'checkAndAutoLogin 失败，继续尝试激活: %{public}s', String(err));
    }

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
          // 302/跳转等非 2xx 视为激活成功（Flutter 同样不校验返回值），仅留日志便于排查
          hilog.warn(0x0000, TAG, 'postEmpty 激活返回非 2xx（可忽略）: %{public}s', String(e2));
        }
      } else {
        try {
          const directUrl = 'https://ehall.xidian.edu.cn' + appPath + '/%2Adefault%2A/index.do';
          await this.http.get(directUrl, EHALL_HEADERS);
        } catch (e3) {
          hilog.warn(0x0000, TAG, '未拿到 transfer URL，index.do 兜底也失败: %{public}s', String(e3));
        }
      }
    } catch (e) {
      try {
        const directUrl = 'https://ehall.xidian.edu.cn' + appPath + '/%2Adefault%2A/index.do';
        await this.http.get(directUrl, EHALL_HEADERS);
      } catch (e3) {
        hilog.warn(0x0000, TAG, 'appShow 失败，index.do 兜底也失败: %{public}s', String(e3));
      }
    }

    // 对齐 Flutter useApp：不在此校验 jsessionid、也不抛异常（Flutter 从不校验 useApp 返回值，
    // 由后续业务请求自然暴露失败）。去掉原先的 throw，避免"服务暂不可用"与黏性缓存叠加成永久失败。
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

  async getEmptyClassroomBuildings(forceRefresh?: boolean): Promise<BuildingInfo[]> {
    // 去掉缓存：教学楼列表每次实时请求，避免"登录失效后仍显示旧缓存"的黏性失败。
    const resp = await this.appPost('/jwapp/sys/kxjas/modules/kxjas/jxlcx.do', {
      '*order': '+XXXQDM,+PX,+JXLDM',
    });
    const raw: object[] = EmptyClassroomService.extractRaw(resp.body);
    const out: BuildingInfo[] = [];
    for (const row of raw) {
      const r: BuildingRow = row as BuildingRow;
      const code = r.JXLDM || '';
      if (code !== '') {
        out.push({ code: code, name: r.JXLJC || r.JXLMC || '未知' });
      }
    }
    return out;
  }

  async searchEmptyClassroomsByDate(buildingCode: string, date: Date): Promise<string> {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, '0');
    const d = String(date.getDate()).padStart(2, '0');
    const dateStr = y + '-' + m + '-' + d;

    const semCode = SemesterUtil.getCurrentSemesterCode();
    const semParts = semCode.split('-');
    const xn = semParts[0] + '-' + semParts[1];
    const xq = semParts[2];
    const xnxqdm = xn + '-' + xq;

    // 1) 用日期换周次 / 星期
    const resp1 = await this.appPost('/jwapp/sys/kxjas/modules/kxjas/rqzhzcjc.do', {
      'RQ': dateStr,
      'XN': xn,
      'XQ': xq,
    });
    let zc = '';
    let xqj = '';
    try {
      const obj = JSON.parse(resp1.body) as Record<string, object>;
      const datas = obj['datas'] as Record<string, object> | undefined;
      if (datas) {
        const rqdata = datas['rqzhzcjc'] as Record<string, object> | undefined;
        if (rqdata) {
          zc = String(rqdata['ZC'] ?? '');
          xqj = String(rqdata['XQJ'] ?? '');
        }
      }
    } catch { /* fallback */ }

    // 2) 查询空闲教室（必须带上 querySetting 等参数，否则服务端收不到过滤条件）
    const querySetting = JSON.stringify([
      { name: 'JXLDM', caption: '教学楼代码', builder: 'equal', linkOpt: 'AND', value: buildingCode },
      { name: 'XNXQDM', value: xnxqdm, linkOpt: 'AND', builder: 'equal' },
      { name: 'ZC', value: zc, linkOpt: 'AND', builder: 'equal' },
      { name: 'XQJ', value: xqj, linkOpt: 'AND', builder: 'equal' },
    ]);
    const resp = await this.appPost('/jwapp/sys/kxjas/modules/kxjas/cxjsqk.do', {
      'XNXQDM': xnxqdm,
      'ZC': zc,
      'XQ': xqj,
      'querySetting': querySetting,
      '*order': '+LC,+JASMC',
      'pageSize': '999',
      'pageNumber': '1',
    });
    return resp.body;
  }

  static extractEmptyClassrooms(body: string): EmptyClassroomItem[] {
    const out: EmptyClassroomItem[] = [];
    const rows = EmptyClassroomService.extractRaw(body);
    for (const row of rows) {
      const r: EmptyClassroomRow = row as EmptyClassroomRow;
      const rawName = r.JASMC || '';
      const roomName = rawName.replace(/[（(].*?[)）]/, '').trim();
      const u1 = r.JC1 || ''; const u2 = r.JC2 || ''; const u3 = r.JC3 || '';
      const u4 = r.JC4 || ''; const u5 = r.JC5 || ''; const u6 = r.JC6 || '';
      const u7 = r.JC7 || ''; const u8 = r.JC8 || ''; const u9 = r.JC9 || '';
      const u10 = r.JC10 || ''; const u11 = r.JC11 || '';

      if (out.length === 0) {
      }

      const isUsed: boolean[] = [
        !u1.includes('1_'), !u2.includes('1_'), !u3.includes('1_'),
        !u4.includes('1_'), !u5.includes('1_'), !u6.includes('1_'),
        !u7.includes('1_'), !u8.includes('1_'), !u9.includes('1_'),
        !u10.includes('1_'), !u11.includes('1_')
      ];
      out.push({
        name: roomName,
        buildingCode: r.JXLDM || '',
        roomName: rawName,
        floor: r.LC || '',
        isUsed: isUsed,
      });
    }
    return out;
  }
}
