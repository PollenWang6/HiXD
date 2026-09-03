// PhysicsScoreService.ets — wlsy 物理实验成绩识别（整条移植自 Flutter traintime_pda：
//   repository/experiment_session/experiment_report_session.dart + image_recognition.dart）
//
// 两条链路：
//  1) getScoreImageUrls：wgyreport UNIGUI 会话。init GET（响应头 session_id）→
//     cinfo/move/activate/resize 事件 → click（提交学号+物理实验密码登录）→
//     OA7 Evt=data 网格返回各实验的成绩图 URL（行2=实验名，行3=含 <img src> 的 HTML）。
//  2) 逐图下载 → 解码取左上角 50×20 像素窗（仅不透明像素）→ FNV-1a 32 位哈希 →
//     查 SCORE_HASHES（对应 Flutter assets/experiment_score/score_hashes.json 12 项）得分数标签。
//
// 与 Flutter 一致：本服务用独立 rcp 会话 + 手写 Cookie 串，不走 HttpUtil 共享 cookie store。
// wgyreport 是独立 UNIGUI 应用（会话与 PhyEws 的 select.aspx 无关），混存会互相覆盖；
// 且 click 响应里的 sid cookie、data 请求的 UniSessionId/_S_ID 头需要逐请求手工控制。
import { rcp } from '@kit.RemoteCommunicationKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'PhysicsScoreService';
const WLSY = 'http://wlsy.xidian.edu.cn';
const UA: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
const SID_PAGE: string = WLSY + '/wgyreport/wgyreport.dll/?id=stu';
const HANDLE_EVENT: string = WLSY + '/wgyreport/wgyreport.dll/HandleEvent';
const SAM_W = 50;   // 像素采样窗宽（与 Flutter image_recognition 一致）
const SAM_H = 20;   // 像素采样窗高

// score_hashes.json（12 项，label→像素 FNV-1a 哈希）。0~9.5=分数；已上传/未上传=提交状态图。
const SCORE_HASHES: Record<string, number> = {
  '0': 3531432063,
  '5.5': 1879675493,
  '6.5': 406889604,
  '6': 1633340036,
  '7.5': 3679241944,
  '7': 923381590,
  '8.5': 4210302206,
  '8': 957817480,
  '9.5': 4187815228,
  '9': 3501829210,
  '已上传': 4077928038,
  '未上传': 843703430
};

export class PhysicsScoreResult {
  label: string = '';   // 命中分数标签；''= 未命中已知图库
  found: boolean = false;
  rawUrl: string = '';  // 成绩原图 URL（详情弹窗展示用）
}

export class PhysicsScoreService {
  private static inst: PhysicsScoreService;
  private session: rcp.Session | null = null;

  static getInstance(): PhysicsScoreService {
    if (!PhysicsScoreService.inst) {
      PhysicsScoreService.inst = new PhysicsScoreService();
    }
    return PhysicsScoreService.inst;
  }

  /**
   * 实验名规整：去掉 ⚛ 前缀与（N学时）后缀，得到成绩图网格与课表页共用的匹配键。
   * 对齐 Flutter physics_experiment_session：成绩结果 Map 以课表实验名（去（3学时））为键。
   */
  static normalizeName(name: string): string {
    let n: string = name || '';
    // 去 ⚛（U+269B）与跟随空格
    if (n.charCodeAt(0) === 0x269B) {
      n = n.substring(1).replace(/^\s+/, '');
    }
    // 去全角/半角（N学时）后缀
    n = n.replace(/[（(]\s*\d+\s*学时\s*[）)]/g, '');
    return n.trim();
  }

  // ===== 对外入口：取全部成绩图 URL → 逐图像素识别 → name→结果 =====

  async recognizeAllScores(account: string, pwd: string): Promise<Record<string, PhysicsScoreResult>> {
    const urlMap: Record<string, string> = await this.getScoreImageUrls(account, pwd);
    const out: Record<string, PhysicsScoreResult> = {};
    const names: string[] = Object.keys(urlMap);
    for (let i = 0; i < names.length; i++) {
      const name: string = names[i];
      const url: string = urlMap[name];
      const r = new PhysicsScoreResult();
      r.rawUrl = url;
      try {
        const bytes: ArrayBuffer = await this.downloadImageBytes(url);
        const hash: number = await this.calcPixelFnv1a(bytes);
        const label: string = this.lookupLabel(hash);
        r.found = label.length > 0;
        r.label = label;
        if (!r.found) {
          console.warn('[' + TAG + '] no hash match: ' + url + ' hash=' + String(hash));
        }
      } catch (e) {
        // 单图失败不拖垮整体（对齐 Flutter：catch 后 found=false 继续下一张）
        console.warn('[' + TAG + '] recognize ' + url + ' failed: ' + String(e));
      }
      out[name] = r;
    }
    return out;
  }

  // ===== 1) wgyreport UNIGUI 会话：拿各实验成绩图 URL =====

  async getScoreImageUrls(account: string, pwd: string): Promise<Record<string, string>> {
    // 通用头（对齐 Flutter commonHeaders）
    const common: Record<string, string> = {
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'User-Agent': UA,
      'Connection': 'keep-alive',
      'Origin': WLSY,
      'Referer': SID_PAGE
    };
    const getHeaders: Record<string, string> = this.mergeHeaders(common, {
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    });
    const postHeaders: Record<string, string> = this.mergeHeaders(common, {
      'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'X-Requested-With': 'XMLHttpRequest',
      'Accept': '*/*'
    });

    let cookieStr: string = '';
    let sid: string = '';

    // ① init GET：响应头 session_id 即会话 ID；响应 Set-Cookie 带 UNI_GUI_SESSION_ID
    const initResp = await this.rawFetch(SID_PAGE, 'GET', undefined, getHeaders, false);
    sid = this.headerValue(initResp, 'session_id');
    cookieStr = this.joinRespCookies(initResp);
    if (cookieStr.length === 0 || cookieStr.indexOf('UNI_GUI_SESSION_ID') < 0) {
      // 兜底：服务器未回 Set-Cookie 时按 Flutter 旧逻辑用 session_id 拼
      cookieStr = 'UNI_GUI_SESSION_ID=' + sid;
    }
    if (sid.length === 0) {
      throw new Error('物理实验成绩系统会话初始化失败（未取到 session_id）');
    }
    console.info('[' + TAG + '] init ok sid=' + sid + ' cookie=' + cookieStr);

    // ②~⑤ 事件序列（cinfo/move/activate/resize），纯模拟前端，无需关心响应体
    const events: string[] = [
      'Ajax=1&IsEvent=1&Obj=O0&Evt=cinfo&ci=br%3D33%3Bos%3D4%3Bbv%3D140%3Bww%3D2048%3Bwh%3D1018&_S_ID=' + sid + '&_seq_=0&_uo_=O0',
      'Ajax=1&IsEvent=1&Obj=O0&Evt=move&this=O0&x=868&y=381&_S_ID=' + sid + '&_seq_=1&_uo_=O0',
      'Ajax=1&IsEvent=1&Obj=O0&Evt=activate&this=O0&_S_ID=' + sid + '&_seq_=2&_uo_=O0',
      'Ajax=1&IsEvent=1&Obj=O0&Evt=resize&this=O0&w=311&h=255&_S_ID=' + sid + '&_seq_=3&_uo_=O0'
    ];
    for (let i = 0; i < events.length; i++) {
      const hdrs: Record<string, string> = this.mergeHeaders(postHeaders, { 'Cookie': cookieStr });
      await this.rawFetch(HANDLE_EVENT, 'POST', events[i], hdrs, false);
    }

    // ⑥ click = 登录提交（账号+物理实验密码在 _fp_ 里原样拼接，对齐 Flutter 原串）
    const clickData: string =
      'Ajax=1&IsEvent=1&Obj=O1F&Evt=click&this=O1F&_S_ID=' + sid +
      '&_fp_=%26O17%3D%25020%2502%2502' + account +
      '%26O1B%3D%25020%2502%2502' + pwd +
      '&_seq_=4&_uo_=O0';
    const clickHdrs: Record<string, string> = this.mergeHeaders(postHeaders, { 'Cookie': cookieStr });
    const clickResp = await this.rawFetch(HANDLE_EVENT, 'POST', clickData, clickHdrs, false);
    // click 成功后 Set-Cookie 追加 sid=<值>（会话 cookie，后续 data 请求必需）
    const sidVal: string = this.pickCookieValue(clickResp, 'sid');
    if (sidVal.length > 0) {
      cookieStr = 'UNI_GUI_SESSION_ID=' + sid + '; sid=' + sidVal;
    } else {
      console.warn('[' + TAG + '] click 响应未带回 sid cookie（登录可能失败）');
    }
    console.info('[' + TAG + '] click done, cookie=' + cookieStr);

    // ⑦ data 网格 GET：拿到成绩图 URL 列表
    const query: string =
      'IsEvent=1&Obj=OA7&Evt=data&_dc=' + String(Date.now()) +
      '&start=0&limit=25&options=1&page=1';
    const dataHeaders: Record<string, string> = this.mergeHeaders(common, {
      'X-Requested-With': 'XMLHttpRequest',
      'UniSessionId': sid,
      '_S_ID': sid,
      'Accept': '*/*',
      'Cookie': cookieStr
    });
    const dataResp = await this.rawFetch(HANDLE_EVENT + '?' + query, 'GET', undefined, dataHeaders, false);
    const text: string = this.decodeText(dataResp.body, this.contentType(dataResp));
    return this.extractExperimentInfo(text);
  }

  // 解析 OA7 data 网格：{rows:[[id,?,实验名,<img src="...">,...],...]}
  private extractExperimentInfo(text: string): Record<string, string> {
    const result: Record<string, string> = {};
    const jsonStr: string = text.replace(/\\x3C/g, '<').replace(/\\x3E/g, '>');
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(jsonStr) as Record<string, Object>;
    } catch (e) {
      throw new Error('物理实验成绩网格解析失败: ' + String(e));
    }
    const rows: Object | undefined = parsed['rows'];
    if (!(rows instanceof Array)) {
      throw new Error('物理实验成绩网格为空');
    }
    for (let i = 0; i < rows.length; i++) {
      const row: Object[] = rows[i] as Object[];
      if (!(row instanceof Array) || row.length < 4) continue;
      const name: string = row[2] ? String(row[2]) : '';
      const imgHtml: string = row[3] ? String(row[3]) : '';
      if (name.length === 0 || imgHtml.length === 0) continue;
      // <img src="..."/> 中 src 可能带 \" 转义（对齐 Flutter src=\\?" 容错）
      const cleanHtml: string = imgHtml.replace(/\\"/g, '"');
      const m: RegExpMatchArray | null = cleanHtml.match(/src="([^"]+)"/);
      if (m && m[1]) {
        let url: string = m[1];
        if (url.startsWith('/')) {
          url = WLSY + url;
        }
        result[name] = url;
      }
    }
    if (Object.keys(result).length === 0) {
      throw new Error('物理实验成绩列表为空（可能本学期无实验报告）');
    }
    return result;
  }

  // ===== 2) 像素 FNV-1a 识别 =====

  private async downloadImageBytes(url: string): Promise<ArrayBuffer> {
    const hdrs: Record<string, string> = {
      'User-Agent': UA,
      'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      'Referer': WLSY
    };
    const resp = await this.rawFetch(url, 'GET', undefined, hdrs, false);
    if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body) {
      return resp.body as ArrayBuffer;
    }
    throw new Error('HTTP ' + String(resp.statusCode) + ' for ' + url);
  }

  // 像素哈希：解码 → 左上角 SAM_W×SAM_H 窗内逐像素，仅累加 alpha==255（不透明）像素的 RGB，
  // FNV-1a 32 位。⚠️ JS Number 乘法会丢精度（hash*prime 超 2^53），必须用 Math.imul 做 32 位乘法。
  private async calcPixelFnv1a(buf: ArrayBuffer): Promise<number> {
    let src: image.ImageSource;
    try {
      src = image.createImageSource(buf);
    } catch (e) {
      throw new Error('成绩图解码失败(createImageSource): ' + String(e));
    }
    let pm: image.PixelMap;
    try {
      pm = await src.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
    } catch (e) {
      throw new Error('成绩图解码失败(createPixelMap): ' + String(e));
    }
    const info: image.ImageInfo = await pm.getImageInfo();
    const w: number = info.size.width;
    const h: number = info.size.height;
    if (w <= 0 || h <= 0) {
      throw new Error('成绩图尺寸异常');
    }
    const out: ArrayBuffer = new ArrayBuffer(w * h * 4);
    await pm.readPixelsToBuffer(out);
    const px: Uint8Array = new Uint8Array(out);
    const sw: number = w < SAM_W ? w : SAM_W;
    const sh: number = h < SAM_H ? h : SAM_H;
    let hash: number = 0x811C9DC5; // FNV offset basis
    for (let y = 0; y < sh; y++) {
      for (let x = 0; x < sw; x++) {
        const o: number = (y * w + x) * 4;
        const a: number = px[o + 3];
        if (a === 255) {
          hash ^= px[o];       // R
          hash = Math.imul(hash, 0x01000193) >>> 0;
          hash ^= px[o + 1];   // G
          hash = Math.imul(hash, 0x01000193) >>> 0;
          hash ^= px[o + 2];   // B
          hash = Math.imul(hash, 0x01000193) >>> 0;
        }
      }
    }
    return hash;
  }

  private lookupLabel(hash: number): string {
    const keys: string[] = Object.keys(SCORE_HASHES);
    for (let i = 0; i < keys.length; i++) {
      if (SCORE_HASHES[keys[i]] === hash) {
        return keys[i];
      }
    }
    return '';
  }

  // ===== rcp 底层 =====

  // Record 拷贝合并（ArkTS 禁对象展开：只能显式逐键拷贝）
  private mergeHeaders(base: Record<string, string>, extra: Record<string, string> | undefined): Record<string, string> {
    const out: Record<string, string> = {};
    const bk: string[] = Object.keys(base);
    for (let i = 0; i < bk.length; i++) {
      out[bk[i]] = base[bk[i]];
    }
    if (extra) {
      const ek: string[] = Object.keys(extra);
      for (let i = 0; i < ek.length; i++) {
        out[ek[i]] = extra[ek[i]];
      }
    }
    return out;
  }

  private async rawFetch(
    url: string,
    method: 'GET' | 'POST',
    body: string | undefined,
    headers: Record<string, string>,
    autoRedirect: boolean
  ): Promise<rcp.Response> {
    if (!this.session) {
      this.session = rcp.createSession();
    }
    const reqHeaders: rcp.RequestHeaders = {};
    const hKeys: string[] = Object.keys(headers);
    for (let i = 0; i < hKeys.length; i++) {
      reqHeaders[hKeys[i]] = headers[hKeys[i]];
    }
    if (!reqHeaders['user-agent'] && !reqHeaders['User-Agent']) {
      reqHeaders['user-agent'] = UA;
    }
    const request: rcp.Request = new rcp.Request(
      url,
      method,
      reqHeaders,
      body,
      undefined,
      undefined,
      { transfer: { autoRedirect: autoRedirect, timeout: { connectMs: 30000, transferMs: 120000 } } }
    );
    try {
      return await this.session.fetch(request);
    } catch (e) {
      const be = e as BusinessError;
      const code: string = (be && be.code !== undefined && be.code !== null) ? String(be.code) : '?';
      const raw: string = (be && be.message) ? be.message : String(e);
      console.error('[' + TAG + '] rcp failed code=' + code + ' msg=' + raw + ' url=' + url);
      throw new Error('物理实验成绩系统网络请求失败: ' + (raw.length > 0 ? raw : code));
    }
  }

  // 响应头取值（rcp 键名小写；session_id 为自定义头，取不到再试大小写变体）
  private headerValue(resp: rcp.Response, lowerKey: string): string {
    const hm = resp.headers as Record<string, string | string[] | undefined>;
    const cands: string[] = [lowerKey, lowerKey.toUpperCase()];
    for (let i = 0; i < cands.length; i++) {
      const v = hm[cands[i]];
      if (v !== undefined && v !== null) {
        if (typeof v === 'string') return v;
        if (v instanceof Array && v.length > 0) return String(v[0]);
      }
    }
    // rcp 首字母大写风格兜底
    const capKey: string = lowerKey.charAt(0).toUpperCase() + lowerKey.substring(1);
    const v2 = hm[capKey];
    if (v2 !== undefined && v2 !== null) {
      if (typeof v2 === 'string') return v2;
      if (v2 instanceof Array && v2.length > 0) return String(v2[0]);
    }
    return '';
  }

  // 将响应 Set-Cookie 全部拼成 "name=value; ..."（对齐 Flutter dio headers['cookie'] 语义）
  private joinRespCookies(resp: rcp.Response): string {
    const parts: string[] = [];
    const cs: rcp.ResponseCookie[] | undefined = resp.cookies;
    if (cs) {
      for (let i = 0; i < cs.length; i++) {
        const c = cs[i];
        if (c.name && c.name.length > 0 && c.value !== undefined && c.value !== null) {
          parts.push(c.name + '=' + String(c.value));
        }
      }
    }
    return parts.join('; ');
  }

  // 取指定名字的 cookie 值（先结构 cookies，再兜底原始 set-cookie 头文本）
  private pickCookieValue(resp: rcp.Response, name: string): string {
    const cs: rcp.ResponseCookie[] | undefined = resp.cookies;
    if (cs) {
      for (let i = 0; i < cs.length; i++) {
        if (cs[i].name === name && cs[i].value !== undefined && cs[i].value !== null) {
          return String(cs[i].value);
        }
      }
    }
    // 兜底：从原始 set-cookie 头文本解析（HttpOnly 等 cookie 可能不进结构体）
    const raw: string = this.headerValue(resp, 'set-cookie');
    if (raw.length > 0) {
      const m: RegExpMatchArray | null = raw.match(new RegExp('(?:^|;)\\s*' + name + '=([^;]+)'));
      if (m && m[1]) return m[1];
    }
    return '';
  }

  private contentType(resp: rcp.Response): string {
    const v: string = this.headerValue(resp, 'content-type');
    return v.length > 0 ? v.toLowerCase() : '';
  }

  // ArrayBuffer → string。对齐 HttpUtil.decodeBody：首字节 { / [ → UTF-8；Content-Type 含 gb → GB18030。
  private decodeText(buf: ArrayBuffer | undefined, ct: string): string {
    if (!buf || buf.byteLength === 0) {
      return '';
    }
    const bytes = new Uint8Array(buf);
    const first: number = bytes[0];
    const isJson: boolean = first === 0x7B || first === 0x5B;
    const isGb: boolean = !isJson && ct.indexOf('gb') >= 0;
    try {
      const decoder: util.TextDecoder = util.TextDecoder.create(isGb ? 'gb18030' : 'utf-8');
      return decoder.decodeToString(bytes);
    } catch (e) {
      return '';
    }
  }
}
