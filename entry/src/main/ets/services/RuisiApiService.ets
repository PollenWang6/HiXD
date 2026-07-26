// RuisiApiService.ets — 睿思论坛业务 API
// 对标 Flutter api_service.dart，完整实现所有业务接口
// HTML 解析用正则表达式

import { RuisiService, RuisiResponse } from './RuisiService';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import {
  Forum, ForumGroup, Topic, Post, ImageAttachment, TopicDetail,
  VoteData, VoteOption, VoteResultItem, VoteStatus,
  ReplyNotification, AtNotification, SignResult, SignStats, UserInfo,
  PmConversation, ChatMessage, ChatResult, ChatDetailResult, FriendResult,
  PostPageMeta, SearchResult, RuisiConstants, RuisiFileAttachment,
  LoginResult, ReplyResult, NewPostResult, FavoriteResult, UploadResult,
  ReportResult, ReportForm,
  LoginPageInfo, TopicListResult, CatIndex, ForumTypeOption, RuisiAttachment,
  Smiley
} from './RuisiModels';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';

const TAG = 'RuisiApiService';
const DOMAIN = 0xFF00;

// ArkTS 严格模式：不能用内联对象类型/未声明类的对象字面量，故用显式类承载统计提取结果
class RuisiStatsResult {
  replies: number = 0;
  views: number = 0;
}

class RuisiNumItem {
  v: number = 0;
  idx: number = 0;
}

// 临时调试：把列表/详情实际收到的 HTML 打到 hilog，便于精修正则。定位完根因后改回 false。
const RUISI_DEBUG_DUMP: boolean = false;

// 桌面版 UA：guide/板块列表用桌面 UA 请求，服务器返回桌面 #threadlist > tbody > td.num
// （<a>回复数 + <em>浏览数），对齐 Flutter。移动 UA 会返回手机版模板，统计数落在 xg1 文本里难解析。
const RUISI_DESKTOP_UA: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

export class RuisiApiService {
  private static instance: RuisiApiService;
  private http: RuisiService;
  // 搜索翻页：第 1 页 POST 拿到 searchid，后续页用 searchid + kw 直接 GET（对齐官方 Android）
  private lastSearchId: string = '';
  private lastKeyword: string = '';

  private constructor() {
    this.http = RuisiService.getInstance();
  }

  static getInstance(): RuisiApiService {
    if (!RuisiApiService.instance) RuisiApiService.instance = new RuisiApiService();
    return RuisiApiService.instance;
  }

  private baseUrl(path: string): string {
    if (path.startsWith('http')) return path;
    return RuisiConstants.BASE_URL + '/' + path.replace(/^\//, '');
  }

  // ==================== 登录 ====================

  /**
   * GET 登录页 → 提取 formhash + loginhash + seccodehash
   */
  async getLoginPageInfo(): Promise<LoginPageInfo> {
    const url = this.baseUrl('member.php?mod=logging&action=login');
    const resp = await this.http.get(url);
    let formhash = '';
    let loginhash = '';
    let seccodehash = '';

    if (resp.isOk && resp.body.length > 0) {
      // 提取 formhash（多种格式兼容）
      // 实际HTML: <input type="hidden" name="formhash" id="formhash" value='918b8d57' />
      // name 和 value 之间可能有其他属性（id=...），用 [^>]* 桥接
      const fh1 = resp.body.match(/name=["']formhash["'][^>]*value=["']([a-f0-9]+)["']/i);
      if (fh1) formhash = fh1[1];
      // 方式2: value 在 name 之前
      if (!formhash) {
        const fh2 = resp.body.match(/value=["']([a-f0-9]+)["'][^>]*name=["']formhash["']/i);
        if (fh2) formhash = fh2[1];
      }
      // 方式3: formhash='hash' in JS 或 URL
      if (!formhash) {
        const fh3 = resp.body.match(/formhash[=:]['"]?([a-f0-9]{6,12})['"]?/i);
        if (fh3) formhash = fh3[1];
      }

      // 提取 loginhash
      const lhMatch = resp.body.match(/loginhash=([a-zA-Z0-9]+)/i);
      if (lhMatch) loginhash = lhMatch[1];

      // 提取 seccodehash（验证码，可能不存在）
      // 方式1: <input name="seccodehash" value="HASH" />
      const scInput = resp.body.match(/name=["']seccodehash["']\s+value=["'](\w+)["']/i);
      if (scInput) seccodehash = scInput[1];

      // 方式2: idhash=HASH
      if (!seccodehash) {
        const scMatch = resp.body.match(/idhash=([a-zA-Z0-9_%]+)/i);
        if (scMatch) seccodehash = decodeURIComponent(scMatch[1]);
      }

      // 方式3: updateseccode('HASH', ...) — Discuz JS 动态渲染
      if (!seccodehash) {
        const sc3 = resp.body.match(/updateseccode\(['"](\w+)['"]/i);
        if (sc3) seccodehash = sc3[1];
      }

      // 方式4: seccodehash=:"HASH" 或 seccodehash="HASH"
      if (!seccodehash) {
        const sc4 = resp.body.match(/seccodehash['"]?\s*[:=]\s*['"]([a-zA-Z0-9_%]+)['"]/i);
        if (sc4) seccodehash = decodeURIComponent(sc4[1]);
      }

      if (formhash) this.http.setFormhash(formhash);
    }

    const result = new LoginPageInfo();
    result.formhash = formhash;
    result.loginhash = loginhash;
    result.seccodehash = seccodehash;
    return result;
  }

  /**
   * 登录
   * @param username 用户名
   * @param password 明文密码（方法内 MD5）
   * @param formhash CSRF token
   * @param loginhash 登录 hash
   * @param seccodeverify 验证码（可选）
   * @param seccodehash 验证码 hash（可选）
   */
  async login(
    username: string,
    password: string,
    formhash: string,
    loginhash: string,
    seccodeverify?: string,
    seccodehash?: string
  ): Promise<LoginResult> {
    const pwdMd5 = await this.http.md5(password);
    const data: Record<string, string> = {
      'formhash': formhash,
      'referer': RuisiConstants.BASE_URL + '/',
      'loginfield': 'username',
      'username': username,
      'password': pwdMd5,
      'cookietime': '315360000',
      'questionid': '0',
      'answer': '',
    };

    if (seccodeverify && seccodehash) {
      data['seccodehash'] = seccodehash;
      data['seccodeverify'] = seccodeverify;
    }

    const url = this.baseUrl(
      `member.php?mod=logging&action=login&loginsubmit=yes&loginhash=${loginhash}&inajax=1`
    );

    const resp = await this.http.post(url, data);

    let success = false;
    let message = '';
    let uid = 0;
    let newFormhash = formhash;

    if (resp.isOk && resp.body.length > 0) {
      const body = resp.body;
      // Discuz 登录成功响应包含 "欢迎您回来" 或 "succeedhandle_login" 或重定向脚本
      if (body.indexOf('欢迎您回来') >= 0 || body.indexOf('succeedhandle_login') >= 0
        || body.indexOf('succeedlocation') >= 0
        || body.indexOf("window.location.href=") >= 0) {
        success = true;
        message = '登录成功';
        // 尝试从响应中提取 uid
        const uidMatch = body.match(/succeedhandle_login\s*\([^,]+,\s*(\d+)/);
        if (uidMatch) uid = parseInt(uidMatch[1]);
        // 尝试提取新 formhash
        const fhMatch = body.match(/formhash=([a-f0-9]+)/i);
        if (fhMatch) {
          newFormhash = fhMatch[1];
          this.http.setFormhash(newFormhash);
        }
      } else if (body.indexOf('登录失败') >= 0 || body.indexOf('密码错误') >= 0) {
        message = '用户名或密码错误';
      } else if (body.indexOf('验证码') >= 0 || body.indexOf('seccode') >= 0) {
        message = '验证码错误或已过期';
      } else {
        // 尝试其他判断
        const errMatch = body.match(/<p[^>]*>([^<]+)<\/p>/i);
        message = errMatch ? errMatch[1] : '登录失败';
      }
    }

    if (success) {
      await this.http.setLoggedIn(true);
      if (uid > 0) await this.http.setUid(uid);
      await this.http.setUsername(username);
      await this.http.setPassword(password);
      // 登录成功后再请求首页获取 formhash 和 uid
      if (uid === 0 || newFormhash === formhash) {
        await this.fetchSessionInfo();
      }
    }

    const result = new LoginResult();
    result.success = success;
    result.message = message;
    result.uid = uid;
    result.formhash = newFormhash;
    return result;
  }

  /**
   * 获取验证码图片
   */
  async getCaptchaImage(seccodehash: string): Promise<ArrayBuffer | null> {
    if (!seccodehash) return null;
    const url = this.baseUrl(
      `misc.php?mod=seccode&action=update&idhash=${encodeURIComponent(seccodehash)}&inajax=1&${Date.now()}`
    );
    try {
      return await this.http.getRaw(url, {
        'Referer': RuisiConstants.BASE_URL + '/',
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'getCaptchaImage failed: ' + JSON.stringify(e));
      return null;
    }
  }

  // ==================== 会话验证 + 三层续登 ====================

  /**
   * 检查登录状态 + 自动续登
   * 三层策略：
   * 1. Cookie 存在 + formhash 存在 → GET 首页验证
   * 2. Cookie 失效 → 用保存的用户名密码重新登录
   * 3. 重新登录也失败 → 返回未登录
   */
  async checkAndAutoLogin(): Promise<boolean> {
    if (!this.http.hasCookies()) {
      // 无 Cookie → 尝试用保存的凭证登录
      const username = this.http.getUsername();
      const password = this.http.getPassword();
      if (username.length > 0 && password.length > 0) {
        return await this.relogin();
      }
      return false;
    }

    // 有 Cookie → 验证是否有效
    await this.http.loadFormhash();
    const valid = await this.checkSessionValid();
    if (valid) return true;

    // Cookie 失效 → 尝试重新登录
    return await this.relogin();
  }

  /**
   * 检查会话是否有效（GET 首页，检查是否被重定向到登录页）
   */
  async checkSessionValid(): Promise<boolean> {
    const url = this.baseUrl('forum.php?mobile=2');
    try {
      const resp = await this.http.get(url);
      if (resp.statusCode === 200 && resp.body.length > 0) {
        // 检查是否包含登录链接（未登录态）
        if (resp.body.indexOf('登录') >= 0 && resp.body.indexOf('member.php?mod=logging') >= 0) {
          return false;
        }
        // 尝试提取 formhash
        const fhMatch = resp.body.match(/formhash=([a-f0-9]{6,})/i);
        if (fhMatch) {
          this.http.setFormhash(fhMatch[1]);
          return true;
        }
        // 没有 formhash 但也没被重定向 → 可能已登录
        return !resp.isRedirect;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /**
   * 用保存的凭证重新登录
   */
  async relogin(): Promise<boolean> {
    const username = this.http.getUsername();
    const password = this.http.getPassword();
    if (username.length === 0 || password.length === 0) return false;

    try {
      const loginInfo = await this.getLoginPageInfo();
      const result = await this.login(username, password, loginInfo.formhash, loginInfo.loginhash);
      if (result.success) {
        await this.fetchSessionInfo();
        return true;
      }
      return false;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'relogin failed: ' + JSON.stringify(e));
      return false;
    }
  }

  /**
   * 获取会话信息：uid, formhash
   */
  async fetchSessionInfo(): Promise<void> {
    const url = this.baseUrl('forum.php?mobile=2');
    try {
      const resp = await this.http.get(url);
      if (resp.body.length === 0) return;
      // 提取 formhash
      const fhMatch = resp.body.match(/formhash=([a-f0-9]{6,})/i);
      if (fhMatch) this.http.setFormhash(fhMatch[1]);
      // 提取 uid（从 "欢迎您回来" 或用户链接中）
      const uidMatch = resp.body.match(/uid[=:]\s*(\d+)/i) || resp.body.match(/space-uid-(\d+)/);
      if (uidMatch) await this.http.setUid(parseInt(uidMatch[1]));
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchSessionInfo failed: ' + JSON.stringify(e));
    }
  }

  // ==================== 板块列表 ====================

  /**
   * 获取板块列表（4 策略降级）
   * 1. AJAX 接口 forum.php?inajax=1&forumlist=1&mobile=2
   * 2. 普通 forum.php?mobile=2
   * 3. forum.php（桌面版）
   * 4. 固定板块列表
   */
  async getForumList(): Promise<ForumGroup[]> {
    // 策略 1: AJAX 接口
    try {
      const resp = await this.http.get(this.baseUrl('forum.php?inajax=1&forumlist=1&mobile=2'));
      if (resp.isOk && resp.body.length > 100) {
        const groups = this.parseForumListAjax(resp.body);
        if (groups.length > 0) return groups;
      }
    } catch (e) {}

    // 策略 2: 普通移动版
    try {
      const resp = await this.http.get(this.baseUrl('forum.php?mobile=2'));
      if (resp.isOk && resp.body.length > 100) {
        const groups = this.parseForumListHtml(resp.body);
        if (groups.length > 0) return groups;
      }
    } catch (e) {}

    // 策略 3: 桌面版
    try {
      const resp = await this.http.get(this.baseUrl('forum.php'));
      if (resp.isOk && resp.body.length > 100) {
        const groups = this.parseForumListHtml(resp.body);
        if (groups.length > 0) return groups;
      }
    } catch (e) {}

    // 策略 4: 固定板块
    return this.getDefaultForumList();
  }

  private parseForumListAjax(html: string): ForumGroup[] {
    const groups: ForumGroup[] = [];
    // AJAX 返回的是 XML 包装的 HTML
    let inner = html;
    const cdataMatch = html.match(/<!\[CDATA\[([\s\S]*?)\]\]>/i);
    if (cdataMatch) inner = cdataMatch[1];

    // 按分类分割
    const catRegex = /<h2[^>]*>([^<]+)<\/h2>/gi;
    const catMatches = Array.from(inner.matchAll(catRegex));
    
    if (catMatches.length === 0) {
      // 尝试其他分割方式
      const catRegex2 = /<div[^>]*class="category_[^"]*"[^>]*>/gi;
      const catSplits = inner.split(catRegex2);
      for (let i = 1; i < catSplits.length; i++) {
        const group = this.parseForumBlock(catSplits[i], `分类${i}`);
        if (group.forums.length > 0) groups.push(group);
      }
    } else {
      let lastIdx = 0;
      for (const m of catMatches) {
        const title = m[1].trim();
        const startIdx = m.index! + m[0].length;
        const endIdx = catMatches[m.index! + 1]?.index ?? inner.length;
        const block = inner.substring(startIdx, endIdx);
        const group = this.parseForumBlock(block, title);
        if (group.forums.length > 0) groups.push(group);
      }
    }
    return groups;
  }

  private parseForumListHtml(html: string): ForumGroup[] {
    const groups: ForumGroup[] = [];
    const catRegex = /<h2[^>]*class="[^"]*flb[^"]*"[^>]*>[\s\S]*?<a[^>]*>([^<]+)<\/a>/gi;
    let catMatch: RegExpExecArray | null;
    const catIndices: CatIndex[] = [];
    while ((catMatch = catRegex.exec(html)) !== null) {
      const ci = new CatIndex();
      ci.title = catMatch[1].trim();
      ci.index = catMatch.index;
      catIndices.push(ci);
    }

    if (catIndices.length === 0) {
      // 回退到固定列表
      return this.getDefaultForumList();
    }

    for (let i = 0; i < catIndices.length; i++) {
      const title = catIndices[i].title;
      const startIdx = catIndices[i].index;
      const endIdx = i < catIndices.length - 1 ? catIndices[i + 1].index : html.length;
      const block = html.substring(startIdx, endIdx);
      const group = this.parseForumBlock(block, title);
      if (group.forums.length > 0) groups.push(group);
    }
    return groups;
  }

  private parseForumBlock(block: string, title: string): ForumGroup {
    const group = new ForumGroup();
    group.title = title;
    // 匹配板块链接
    const forumRegex = /<a[^>]*href="forum\.php\?mod=forumdisplay&fid=(\d+)[^"]*"[^>]*>([^<]+)<\/a>/gi;
    let fMatch: RegExpExecArray | null;
    const seenFids = new Set<number>();
    while ((fMatch = forumRegex.exec(block)) !== null) {
      const fid = parseInt(fMatch[1]);
      if (seenFids.has(fid)) continue;
      seenFids.add(fid);
      const forum = new Forum();
      forum.fid = fid;
      forum.name = fMatch[2].trim();
      // 尝试提取帖子数
      const threadMatch = block.substring(fMatch.index).match(/<em[^>]*>(\d+)<\/em>/);
      if (threadMatch) forum.threads = parseInt(threadMatch[1]);
      // 尝试提取今日发帖数
      const todayMatch = block.substring(fMatch.index).match(/今日[^<]*<strong[^>]*>(\d+)<\/strong>/i) ||
        block.substring(fMatch.index).match(/today[^<]*<strong[^>]*>(\d+)<\/strong>/i);
      if (todayMatch) forum.todayPosts = parseInt(todayMatch[1]);
      group.forums.push(forum);
    }
    return group;
  }

  private getDefaultForumList(): ForumGroup[] {
    // 完整板块列表（对齐 Flutter 参考项目 forums.json，rs.xidian.edu.cn 睿思）
    // 注：校园交易 fid 用 110（Flutter 内部将旧 id 106 归一化为 110）
    const g1 = new ForumGroup();
    g1.title = '西电生活';
    g1.forums = [
      this.makeForum(549, '文章天地'),
      this.makeForum(550, '心灵花园'),
      this.makeForum(110, '校园交易'),
      this.makeForum(108, '我是女生'),
      this.makeForum(115, '版聊专区'),
      this.makeForum(217, '缘聚睿思'),
      this.makeForum(142, '失物招领'),
      this.makeForum(551, '西电问答'),
      this.makeForum(157, '校园活动'),
      this.makeForum(552, '我要毕业啦'),
      this.makeForum(554, '就业招聘'),
    ];

    const g2 = new ForumGroup();
    g2.title = '学术交流';
    g2.forums = [
      this.makeForum(560, '技术博客'),
      this.makeForum(548, '学习交流'),
      this.makeForum(145, '软件技术'),
      this.makeForum(144, '嵌入式技术'),
      this.makeForum(91, '考研交流'),
      this.makeForum(152, '竞赛交流'),
      this.makeForum(134, 'Abroad & English'),
    ];

    const g3 = new ForumGroup();
    g3.title = '休闲娱乐';
    g3.forums = [
      this.makeForum(72, '灌水专区', true),
      this.makeForum(561, '摄影天地'),
      this.makeForum(147, '原创精品区'),
      this.makeForum(215, '西电后街'),
      this.makeForum(216, '我爱运动'),
      this.makeForum(125, '音乐纵贯线'),
      this.makeForum(140, '绝对漫域'),
      this.makeForum(139, '游间客栈'),
      this.makeForum(122, '大话体坛'),
    ];

    const g4 = new ForumGroup();
    g4.title = '社团&站务';
    g4.forums = [
      this.makeForum(566, '新人指南'),
      this.makeForum(138, '腾讯创新俱乐部'),
      this.makeForum(150, '华为创新俱乐部'),
      this.makeForum(119, '举报专区'),
      this.makeForum(2, '帮助专区'),
      this.makeForum(141, '发展建议'),
      this.makeForum(137, '邀请码申请'),
      this.makeForum(94, '公告活动'),
    ];

    return [g1, g2, g3, g4];
  }

  private makeForum(fid: number, name: string, isHot: boolean = false): Forum {
    const f = new Forum();
    f.fid = fid;
    f.name = name;
    f.isHot = isHot;
    return f;
  }

  // ==================== 帖子列表 ====================

  /**
   * 获取帖子列表（3 策略降级）
   * 1. forum.php?mod=forumdisplay&fid=XX&page=N&mobile=2
   * 2. forum.php?mod=forumdisplay&fid=XX&page=N（桌面版）
   * 3. forum-XX-N.html（静态 URL）
   */
  async getTopicList(fid: number, page: number = 1): Promise<TopicListResult> {
    const topics: Topic[] = [];
    let totalPages = 1;

    // 策略 1: 桌面版（用桌面 UA 拿 #threadlist > tbody > td.num，对齐 Flutter，统计数可靠）
    try {
      const url = this.baseUrl(`forum.php?mod=forumdisplay&fid=${fid}&page=${page}`);
      const resp = await this.http.get(url, { 'User-Agent': RUISI_DESKTOP_UA });
      if (resp.isOk && resp.body.length > 100) {
        const result = this.parseTopicList(resp.body);
        if (result.topics.length > 0) return result;
      }
    } catch (e) {
      hilog.error(0xFF00, 'RuisiApiService', `getTopicList mobile=2 error: ${JSON.stringify(e)}`);
    }

    // 策略 2: 桌面版
    try {
      const url = this.baseUrl(`forum.php?mod=forumdisplay&fid=${fid}&page=${page}`);
      const resp = await this.http.get(url);
      if (resp.isOk && resp.body.length > 100) {
        const result = this.parseTopicList(resp.body);
        if (result.topics.length > 0) return result;
      }
    } catch (e) {}

    // 策略 3: 静态 URL
    try {
      const url = this.baseUrl(`forum-${fid}-${page}.html`);
      const resp = await this.http.get(url);
      if (resp.isOk && resp.body.length > 100) {
        return this.parseTopicList(resp.body);
      }
    } catch (e) {}

    const fallbackResult = new TopicListResult();
    fallbackResult.topics = topics;
    fallbackResult.totalPages = totalPages;
    return fallbackResult;
  }

  private parseTopicList(html: string): TopicListResult {
    const map: Map<number, Topic> = new Map();

    // 合并策略：结构化解析优先，通用降级只补空缺字段
    const addOrMerge = (t: Topic) => {
      const ex = map.get(t.tid);
      if (!ex) { map.set(t.tid, t); return; }
      if (!ex.title) ex.title = t.title;
      if (!ex.author && t.author) { ex.author = t.author; ex.authorId = t.authorId; }
      if (ex.replies === 0 && t.replies > 0) ex.replies = t.replies;
      if (ex.views === 0 && t.views > 0) ex.views = t.views;
      if (!ex.lastReplyTime && t.lastReplyTime) ex.lastReplyTime = t.lastReplyTime;
      if (!ex.isStick && t.isStick) ex.isStick = t.isStick;
    };

    // 提取总页数
    const pageMatch = html.match(/共\s*(\d+)\s*页/) || html.match(/page=(\d+)[^"]*"[^>]*class="last"/);
    const totalPages = pageMatch ? parseInt(pageMatch[1]) : 1;

    // 策略1: 移动版 <li class="plc">（注意原始 HTML 中 & 为 &amp;）
    const amp = '(?:&amp;|&)';
    const mobileRegex = new RegExp(
      `<li[^>]*class="[^"]*plc[^"]*"[^>]*>[\\s\\S]*?<a[^>]*href="forum\\.php\\?mod=viewthread${amp}tid=(\\d+)[^"]*"[^>]*>([^<]+)<\\/a>[\\s\\S]*?<\\/li>`, 'gi');
    let m: RegExpExecArray | null;
    while ((m = mobileRegex.exec(html)) !== null) {
      const t = new Topic();
      t.tid = parseInt(m[1]);
      t.title = this.stripTags(m[2]).trim();
      const am = m[0].match(new RegExp(`<a[^>]*href="home\\.php\\?mod=space${amp}uid=(\\d+)[^"]*"[^>]*>([^<]+)<\\/a>`, 'i'));
      if (am) { t.authorId = parseInt(am[1]); t.author = am[2].trim(); }
      const stats = this.extractStatsFromBlock(m[0]);
      t.replies = stats.replies;
      t.views = stats.views;
      const tm = m[0].match(/(\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2})/) ||
        m[0].match(/<span[^>]*class="[^"]*time[^"]*"[^>]*>([^<]+)<\/span>/i);
      if (tm) t.lastReplyTime = tm[1].trim();
      t.isStick = m[0].indexOf('stickthread') >= 0 || m[0].indexOf('置顶') >= 0;
      t.isImage = m[0].indexOf('<img') >= 0 && m[0].indexOf('attachimg') >= 0;
      addOrMerge(t);
    }

    // 策略2: 桌面版 #threadlist tbody#normalthread_（guide 与 forumdisplay 同结构）
    const desktopRegex = /<tbody[^>]*id="(?:normalthread|stickthread)_(\d+)"[^>]*>([\s\S]*?)<\/tbody>/gi;
    while ((m = desktopRegex.exec(html)) !== null) {
      const t = new Topic();
      t.tid = parseInt(m[1]);
      t.isStick = m[0].indexOf('stickthread') >= 0;
      const block = m[2];
      const tm2 = block.match(new RegExp(`<a[^>]*href="[^"]*viewthread${amp}tid=\\d+[^"]*"[^>]*class="[^"]*xst[^"]*"[^>]*>([\\s\\S]*?)<\\/a>`, 'i')) ||
        block.match(new RegExp(`<a[^>]*href="[^"]*viewthread${amp}tid=\\d+[^"]*"[^>]*>([\\s\\S]*?)<\\/a>`, 'i'));
      if (tm2) t.title = this.stripTags(tm2[1]).trim();
      const am = block.match(new RegExp(`<a[^>]*href="home\\.php\\?mod=space${amp}uid=(\\d+)[^"]*"[^>]*>([^<]+)<\\/a>`, 'i'));
      if (am) { t.authorId = parseInt(am[1]); t.author = am[2].trim(); }
      const nb = block.match(/<td[^>]*class="num"[^>]*>([\s\S]*?)<\/td>/i);
      if (nb) {
        const a = nb[1].match(/<a[^>]*>(\d+)<\/a>/i); if (a) t.replies = parseInt(a[1]);
        const e = nb[1].match(/<em[^>]*>(\d+)<\/em>/i); if (e) t.views = parseInt(e[1]);
      }
      const times = block.match(/\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2}/g);
      if (times && times.length) t.lastReplyTime = times[times.length - 1];
      // 提取所述板块名（guide 首页聚合流里每个线程块含 forumdisplay 链接；单板块 forumdisplay 页一般不含，故不冗余）
      const flMatch = block.match(/<a[^>]*href="[^"]*forum\.php\?mod=forumdisplay(?:&amp;|&)fid=(\d+)[^"]*"[^>]*>([^<]+)<\/a>/i);
      if (flMatch) {
        t.forumName = flMatch[2].trim();
        if (t.fid === 0) t.fid = parseInt(flMatch[1]);
      }
      if (t.title) addOrMerge(t);
    }

    // 策略3: 通用降级 —— 扫描所有 viewthread 链接（兼容 guide / 移动模板 / 任意结构，不依赖 &）
    const linkRegex = new RegExp(`<a[^>]*href="[^"]*viewthread[^"]*tid=(\\d+)[^"]*"[^>]*>([\\s\\S]*?)<\\/a>`, 'gi');
    while ((m = linkRegex.exec(html)) !== null) {
      const tid = parseInt(m[1]);
      if (map.has(tid)) continue;
      const title = this.stripTags(m[2]).trim();
      if (!title) continue;
      const t = new Topic();
      t.tid = tid;
      t.title = title;
      addOrMerge(t);
    }

    const result = new TopicListResult();
    result.topics = Array.from(map.values());
    result.totalPages = totalPages;
    return result;
  }

  /**
   * 从移动模板的帖子块中提取回复数 / 查看数。
   * 移动端 Discuz 把统计写在 <p class="xg1">N 个回复 - N 次查看</p> 或类似文本里，
   * 而不是桌面模板的 <td class="num"><a>N</a><em>N</em></td>。
   * 优先从 xg1 段落的文本中用「回复」「查看/浏览」关键词定位数字，避免标题/日期里的数字污染。
   */
  private extractStatsFromBlock(block: string): RuisiStatsResult {
    const result = new RuisiStatsResult();
    const xg1 = block.match(/<p[^>]*class="[^"]*xg1[^"]*"[^>]*>([\s\S]*?)<\/p>/i);
    const text = xg1 ? xg1[1] : block;
    const plain = text.replace(/<[^>]+>/g, ' ');

    // 主：规范移动模板 "N 个回复 - N 次查看"（或 "N回复 N查看" / "N回复 N浏览"）
    const canon = plain.match(/(\d+)\s*个?回复[^\d]*?(\d+)\s*次?(?:查看|浏览)/i);
    if (canon) {
      result.replies = parseInt(canon[1]);
      result.views = parseInt(canon[2]);
    } else {
      // 兜底：取离关键词最近的数字（应对变体格式），用 exec 循环兼容 ArkTS
      const replyKw = plain.search(/回复|reply/i);
      const viewKw = plain.search(/查看|浏览|view/i);
      const numRe = /\d+/g;
      const nums: Array<RuisiNumItem> = [];
      let nm: RegExpExecArray | null;
      while ((nm = numRe.exec(plain)) !== null) {
        const item = new RuisiNumItem();
        item.v = parseInt(nm[0]);
        item.idx = nm.index;
        nums.push(item);
      }
      if (replyKw >= 0 && nums.length > 0) {
        let best: number = 0;
        let bd: number = Infinity;
        for (const n of nums) {
          const center = n.idx + ('' + n.v).length / 2;
          const d = Math.abs(center - replyKw);
          if (d < bd) { bd = d; best = n.v; }
        }
        result.replies = best;
      }
      if (viewKw >= 0 && nums.length > 0) {
        let best: number = 0;
        let bd: number = Infinity;
        for (const n of nums) {
          const center = n.idx + ('' + n.v).length / 2;
          const d = Math.abs(center - viewKw);
          if (d < bd) { bd = d; best = n.v; }
        }
        result.views = best;
      }
    }
    if (isNaN(result.replies)) result.replies = 0;
    if (isNaN(result.views)) result.views = 0;
    return result;
  }

  private extractFidFromBlock(block: string): number {
    const fidMatch = block.match(/fid=(\d+)/);
    return fidMatch ? parseInt(fidMatch[1]) : 0;
  }

  // 临时调试：把 HTML 分块打到 hilog（标签 RuisiDump），便于照真结构精修正则
  private dumpHtml(label: string, body: string): void {
    if (!RUISI_DEBUG_DUMP) return;
    const max = 14000;
    const s = body.length > max ? body.substring(0, max) : body;
    const chunk = 900;
    let i = 0;
    let part = 0;
    while (i < s.length) {

      i += chunk;
      part++;
    }

  }

  // ==================== 帖子详情 ====================

  /**
   * 获取帖子详情
   */
  async getTopicDetail(tid: number, page: number = 1): Promise<TopicDetail | null> {
    const url = this.baseUrl(`forum.php?mod=viewthread&tid=${tid}&page=${page}`);
    try {
      // 用桌面 UA 拿桌面 viewthread 模板（楼层结构为 <div id="post_PID"><td class="t_f" id="postmessage_PID">），
      // 与列表解析（getTopicList/getGuideList 同样用桌面 UA）保持一致；移动 UA 返回手机模板解析不到楼层。
      const resp = await this.http.get(url, { 'User-Agent': RUISI_DESKTOP_UA });
      if (!resp.isOk || resp.body.length === 0) return null;
      this.dumpHtml('DETAIL', resp.body);
      return this.parseTopicDetail(resp.body, tid, page);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'getTopicDetail failed: ' + JSON.stringify(e));
      return null;
    }
  }

  private parseTopicDetail(html: string, tid: number, currentPage: number): TopicDetail {
    const detail = new TopicDetail();
    detail.tid = tid;
    detail.currentPage = currentPage;

    // 提取标题（对标安卓：标题在 <title> 中，形如 "标题 - 板块 - 站点"，取第一个 " - " 之前即为纯标题）
    let titleSrc = '';
    const h1Match = html.match(/<h1[^>]*class="[^"]*ts[^"]*"[^>]*>([\s\S]*?)<\/h1>/i);
    if (h1Match && h1Match[1]) {
      titleSrc = h1Match[1];
    } else {
      const tm = html.match(/<title>([^<]+)<\/title>/i);
      if (tm && tm[1]) titleSrc = tm[1];
    }
    if (titleSrc) {
      let t = this.stripTags(titleSrc).trim();
      const dashIdx = t.indexOf(' - ');
      if (dashIdx > 0) t = t.substring(0, dashIdx).trim();
      detail.title = t;
    }

    // 提取 fid
    const fidMatch = html.match(/fid=(\d+)/);
    if (fidMatch) detail.fid = parseInt(fidMatch[1]);

    // 提取作者信息
    const authorMatch = html.match(/<a[^>]*href="home\.php\?mod=space(?:&amp;|&)uid=(\d+)[^"]*"[^>]*>([^<]+)<\/a>/i);
    if (authorMatch) {
      detail.authorId = parseInt(authorMatch[1]);
      detail.author = authorMatch[2].trim();
    }

    // 提取总页数
    const pageMatch = html.match(/共\s*(\d+)\s*页/) || html.match(/class="pg"[^>]*>[\s\S]*?共(\d+)页/i);
    if (pageMatch) detail.totalPages = parseInt(pageMatch[1]);

    // 提取回复数（真实桌面版：回复:</span> <span class="xi1">58</span>；兼容旧 <em> 与移动写法）
    const replyMatch =
      html.match(/回复:<\/span>\s*<span[^>]*>(\d+)<\/span>/i) ||
      html.match(/回复[：:\s]*<em[^>]*>(\d+)<\/em>/i) ||
      html.match(/<em[^>]*>(\d+)<\/em>[^<]*回复/i) ||
      html.match(/回复[：:\s]*(\d+)/i) ||
      html.match(/(\d+)\s*个?回复/i) ||
      html.match(/(\d+)\s*条回复/i);
    if (replyMatch) detail.replies = parseInt(replyMatch[1]);

    // 提取浏览量（真实桌面版：查看:</span> <span class="xi1">7223</span>；兼容旧 <em> 与移动写法）
    const viewMatch =
      html.match(/查看:<\/span>\s*<span[^>]*>(\d+)<\/span>/i) ||
      html.match(/浏览[：:\s]*<em[^>]*>(\d+)<\/em>/i) ||
      html.match(/查看[：:\s]*<em[^>]*>(\d+)<\/em>/i) ||
      html.match(/点击[：:\s]*<em[^>]*>(\d+)<\/em>/i) ||
      html.match(/浏览[：:\s]*(\d+)/i) ||
      html.match(/(\d+)\s*次查看/i) ||
      html.match(/(\d+)\s*浏览/i);
    if (viewMatch) detail.views = parseInt(viewMatch[1]);

    // 解析楼层
    detail.posts = this.parsePosts(html, currentPage);

    // 解析投票
    const voteData = this.parseVote(html);
    if (voteData) detail.vote = voteData;

    if (RUISI_DEBUG_DUMP) {
      const first = detail.posts.length > 0 ? `${detail.posts[0].author}#${detail.posts[0].pid}` : 'NONE';

    }

    return detail;
  }

  private parsePosts(html: string, currentPage: number = 1): Post[] {
    const posts: Post[] = [];
    // 真实 Discuz 桌面版楼层结构：
    // <div id="post_PID"><table class="plhin">
    //   <tr><td class="pls">作者栏(含 home.php?mod=space&uid=XXX)</td>
    //   <td class="plc">...<td class="t_f" id="postmessage_PID">内容</td>...</td></tr>
    // </table></div>
    // 按楼层容器 <div id="post_PID"> 切分（split 的捕获组会把 pid 也放进结果数组）。
    // 注意：不同板块模板属性顺序不同，可能是 <div id="post_X"> 也可能是 <div class="plhin" id="post_X">，
    // 故用 [^>]* 允许 id 之前/之后有其他属性（属性顺序无关），否则会切不到 → 返回 0 层。
    const parts = html.split(/<div[^>]*\bid="post_(\d+)"[^>]*>/i);
    for (let i = 1; i < parts.length - 1; i += 2) {
      const pidStr = parts[i];
      const block = parts[i + 1];
      const pid = parseInt(pidStr);
      if (isNaN(pid) || block.length === 0) continue;

      const post = new Post();
      post.pid = pid;
      // 楼层号在 RuisiTopicDetailPage.loadDetail 中按全局位置统一连续编号（1,2,3…），
      // 这里不本地计数，避免翻页重置。

      // 作者（author 侧栏里的 uid 链接）
      const authorMatch = block.match(/home\.php\?mod=space(?:&amp;|&)uid=(\d+)[^>]*>([^<]+)<\/a>/i)
        || block.match(/uid=(\d+)[^>]*>([^<]+)<\/a>/i);
      if (authorMatch) {
        post.authorId = parseInt(authorMatch[1]);
        post.author = authorMatch[2].trim();
      }

      // 头像
      const avatarMatch = block.match(/src="([^"]*avatar[^"]*)"/i)
        || block.match(/src="([^"]*uc2_link[^"]*)"/i)
        || block.match(/src="([^"]*uc_server[^"]*)"/i);
      if (avatarMatch) post.avatar = avatarMatch[1].replace(/&amp;/g, '&');

      // 时间：发表于 2010-4-28 12:34:57 或 <em id="authorpostonPID">2010-4-28 12:34:57</em>
      const timeMatch = block.match(/发表于\s*([\d\-]+\s*[\d:]+)/)
        || block.match(/id="authorposton\d+"[^>]*>([\d\-]+\s*[\d:]+)</);
      if (timeMatch) post.time = timeMatch[1].trim();

      // 内容：每个楼层正文在 <div class="message"> 容器内（对标安卓/iOS 的 .message 选择器）。
      // 用 div 深度计数取完整 innerHTML，正文内嵌套 <table> 的 </td> 不会干扰（只数 div），
      // 避免"签到奖励明细"等带表格的正文被截断（旧方案按 <td> 计数会被 table 内的 </td> 提前闭合）。
      const raw = this.extractPostContent(block, pid);
      if (raw.length > 0) {
        post.content = this.cleanContent(raw);
        post.isQuote = raw.indexOf('引用') >= 0 || raw.toLowerCase().indexOf('quote') >= 0;
      }

      // 图片（parseImages 已过滤头像/表情，且扫整个 block：既含 .message 内联图，也含 dl.tattl.attm 附件图）
      post.images = this.parseImages(block);
      // 附件图补进正文：cleanContent 只处理 .message 内部，而卖东西帖/带图帖的图片大量以
      // dl.tattl.attm 附件块形式躺在 .message 之外，不会被转成 [[img]] 标记 → 表现为"图片一张都不显示"。
      // 这里把正文里没出现过的图片（即 .message 之外的附件图）追加到正文末尾，紧跟文字之后，
      // 既解决"图片消失"，也解决"离得远"（位置就在对应文字下方，而非堆到楼底）。
      if (post.content.length > 0 && post.images.length > 0) {
        const inlineSet = new Set<string>();
        const re = /\[\[img:([^\]]+)\]\]/g;
        let rm: RegExpExecArray | null;
        while ((rm = re.exec(post.content)) !== null) {
          inlineSet.add(rm[1]);
        }
        const extra = post.images.filter((img: ImageAttachment) => !inlineSet.has(img.url));
        if (extra.length > 0) {
          post.content += '\n' + extra.map((img: ImageAttachment) => `[[img:${img.url}]]`).join('\n');
        }
      }
      // 纯文件附件（PDF/文档等，非图片）
      post.fileAttachments = this.parseFileAttachments(block);

      posts.push(post);
    }

    return posts;
  }

  /**
   * 提取某楼正文（对标安卓/iOS：楼层正文在 <div class="message"> 容器内）。
   * 优先取 .message 容器并用 div 深度计数取完整 innerHTML；极少数模板无 .message 时，
   * 回退到 postmessage_PID 的 <td> 内容（td 深度计数）。
   */
  private extractPostContent(block: string, pid: number): string {
    const mStart = block.search(/<div[^>]*class="[^"]*message[^"]*"[^>]*>/i);
    if (mStart >= 0) {
      const openEnd = block.indexOf('>', mStart);
      if (openEnd >= 0) {
        const inner = this.extractByTagDepth(block, openEnd + 1, 'div');
        if (inner.length > 0) return inner;
      }
    }
    // 兜底：postmessage_PID 的 <td> 内容
    return this.extractPostMessageTd(block, pid);
  }

  // 从 start 位置起，按 tag 深度计数截取容器内部内容（<tag 加一，</tag 减一，归零即结束）
  private extractByTagDepth(block: string, start: number, tag: string): string {
    const open = '<' + tag;
    const close = '</' + tag;
    let i = start;
    let depth = 1;
    const len = block.length;
    let end = -1;
    while (i < len) {
      const lt = block.indexOf('<', i);
      if (lt < 0) break;
      const gt = block.indexOf('>', lt);
      if (gt < 0) break;
      const token = block.substring(lt, gt + 1).toLowerCase();
      const afterOpen = token.length > open.length ? token[open.length] : '';
      const afterClose = token.length > close.length ? token[close.length] : '';
      if (token.startsWith(close) && (afterClose === '' || afterClose === ' ' || afterClose === '>')) {
        depth--;
        if (depth === 0) { end = lt; break; }
      } else if (token.startsWith(open) && (afterOpen === '' || afterOpen === ' ' || afterOpen === '>')) {
        depth++;
      }
      i = gt + 1;
    }
    return end > 0 ? block.substring(start, end) : '';
  }

  // 兜底：postmessage_PID 的 <td> 内容（td 深度计数）
  private extractPostMessageTd(block: string, pid: number): string {
    const marker = `id="postmessage_${pid}"`;
    const startIdx = block.indexOf(marker);
    if (startIdx < 0) return '';
    const openEnd = block.indexOf('>', startIdx);
    if (openEnd < 0) return '';
    return this.extractByTagDepth(block, openEnd + 1, 'td');
  }

  private parseImages(block: string): ImageAttachment[] {
    const images: ImageAttachment[] = [];
    const seenAid = new Set<number>();
    // 真实 Discuz 楼层里两类图片：
    //  (a) 内联 <img src="data/attachment/..."> —— 真图在 src；
    //  (b) 图片附件 <dl class="tattl attm"> 内的 <img src="static/image/common/none.gif"
    //      file="./data/attachment/forum/..." zoomfile="..."> —— 真图在 file=/zoomfile=，src 只是占位 none.gif。
    // 故逐个 <img> 分别取 src/file/zoomfile，优先用 file/zoomfile（非 none.gif），再退回 src。
    const imgRegex = /<img[^>]*>/gi;
    let imgMatch: RegExpExecArray | null;
    while ((imgMatch = imgRegex.exec(block)) !== null) {
      const tag = imgMatch[0];
      const srcM = tag.match(/(?:^|\s)src="([^"]*)"/i);
      const fileM = tag.match(/(?:^|\s)file="([^"]*)"/i);
      const zoomM = tag.match(/(?:^|\s)zoomfile="([^"]*)"/i);
      const aidM = tag.match(/id="aimg_(\d+)"/i);
      // 选真实图片地址；none.gif 占位一律忽略
      let url = '';
      if (fileM && fileM[1].length > 0 && fileM[1].indexOf('none.gif') < 0) url = fileM[1];
      else if (zoomM && zoomM[1].length > 0 && zoomM[1].indexOf('none.gif') < 0) url = zoomM[1];
      else if (srcM && srcM[1].length > 0 && srcM[1].indexOf('none.gif') < 0) url = srcM[1];
      if (url.length === 0) continue;
      // 过滤头像、表情、以及 Discuz UI 装饰图（勋章/星级/在线状态等，路径均在 static/image/ 下）。
      // 签到帖等场景：楼层切分（按 <div id="post_X">）会把"今日签到排行榜"表格连同 21 个用户的
      // 作者信息栏一并圈进一楼 block，其中含 star_level*.gif、medal/*.gif、userinfo.gif 等几十张
      // static/image/common 装饰图；旧过滤只挡 avatar/smiley → 这些相对路径图被 Image 组件加载失败，
      // 在一楼正文下方渲染成一大片空白占位框（用户看到的"签到帖一楼一大片空白"真凶）。
      // 用户上传的真实帖子图在 data/attachment/ 或 forum.php?mod=attachment，绝不含 static/image，不受影响。
      if (url.indexOf('avatar') >= 0 || url.indexOf('smiley') >= 0 || url.indexOf('smilies') >= 0
        || url.indexOf('static/image') >= 0 || url.indexOf('none.gif') >= 0) continue;
      // 相对路径补 BASE_URL（楼层内图片地址多为 ./data/attachment/... 或 data/attachment/...）
      if (!url.startsWith('http')) {
        url = RuisiConstants.BASE_URL + '/' + url.replace(/^\.?\//, '');
      }
      const img = new ImageAttachment();
      img.url = url;
      img.thumbUrl = url;
      if (aidM) { img.aid = parseInt(aidM[1]); seenAid.add(img.aid); }
      const nameMatch = url.match(/([^/]+)$/);
      if (nameMatch) img.filename = nameMatch[1];
      images.push(img);
    }
    return images;
  }

  // 纯文件附件（非图片）：Discuz 桌面版把附件包在 <dl class="tattl">（纯文件）或
  // <dl class="tattl attm">（图片附件）里，两者都含一个下载链接
  // <a href="forum.php?mod=attachment&aid=...">文件名.pdf</a>。
  // 图片式附件（dl.tattl.attm，含 <img file="data/attachment/...">）已由 parseImages 处理，
  // 此处只捞纯文件（如 PDF/文档），避免重复显示。下载走浏览器（openLink），与 Flutter launchUrl 一致。
  private parseFileAttachments(block: string): RuisiFileAttachment[] {
    const files: RuisiFileAttachment[] = [];
    const seen = new Set<string>();
    // 匹配所有附件块（tattl / tattl attm 都含 "tattl"）
    const dlRegex = /<dl[^>]*class="[^"]*tattl[^"]*"[^>]*>([\s\S]*?)<\/dl>/gi;
    let dl: RegExpExecArray | null;
    while ((dl = dlRegex.exec(block)) !== null) {
      const whole = dl[0];
      const inner = dl[1];
      // 图片附件：class 含 "tattl attm" 且内部有 <img file="data/attachment/..."> → 已由 parseImages 处理，跳过
      const isImageAttach = /class="[^"]*tattl\s+attm[^"]*"/i.test(whole)
        && /<img[^>]*file="[^"]*data\/attachment[^"]*"/i.test(inner);
      if (isImageAttach) continue;
      // 纯文件：取下载链接
      const aMatch = inner.match(/<a[^>]*href="([^"]*mod=attachment[^"]*)"[^>]*>([\s\S]*?)<\/a>/i);
      if (!aMatch) continue;
      let href = aMatch[1].replace(/&amp;/g, '&');
      const name = this.stripTags(aMatch[2]).trim();
      if (name.length === 0) continue;
      if (!href.startsWith('http')) href = RuisiConstants.BASE_URL + '/' + href.replace(/^\.?\//, '');
      if (seen.has(href)) continue;
      seen.add(href);
      const f = new RuisiFileAttachment();
      f.url = href;
      f.fileName = name;
      files.push(f);
    }
    return files;
  }

  private parseVote(html: string): VoteData | null {
    if (html.indexOf('poll') < 0 && html.indexOf('投票') < 0) return null;
    const vote = new VoteData();
    
    // 提取投票问题
    const qMatch = html.match(/<th[^>]*class="[^"]*pollt[^"]*"[^>]*>([^<]+)<\/th>/i) ||
      html.match(/<div[^>]*class="[^"]*pollq[^"]*"[^>]*>([^<]+)<\/div>/i);
    if (qMatch) vote.question = qMatch[1].trim();

    // 提取选项
    const optRegex = /<li[^>]*class="[^"]*pollopt[^"]*"[^>]*>[\s\S]*?<input[^>]*value="(\d+)"[^>]*>[\s\S]*?<label[^>]*>([^<]+)<\/label>/gi;
    let optMatch: RegExpExecArray | null;
    while ((optMatch = optRegex.exec(html)) !== null) {
      const opt = new VoteOption();
      opt.id = parseInt(optMatch[1]);
      opt.text = this.stripTags(optMatch[2]).trim();
      vote.options.push(opt);
    }

    // 如果没匹配到选项，尝试更宽松的匹配
    if (vote.options.length === 0) {
      const optRegex2 = /<input[^>]*type="(?:radio|checkbox)"[^>]*value="(\d+)"[^>]*>[\s]*<label[^>]*>([^<]*)<\/label>/gi;
      while ((optMatch = optRegex2.exec(html)) !== null) {
        const opt = new VoteOption();
        opt.id = parseInt(optMatch[1]);
        opt.text = optMatch[2].trim();
        vote.options.push(opt);
      }
    }

    // 提取投票结果
    const resultRegex = /<li[^>]*>[\s\S]*?<em[^>]*>(\d+)<\/em>\s*\((\d+)%\)[\s\S]*?<label[^>]*>([^<]+)<\/label>/gi;
    let rMatch: RegExpExecArray | null;
    while ((rMatch = resultRegex.exec(html)) !== null) {
      const item = new VoteResultItem();
      item.voteCount = parseInt(rMatch[1]);
      item.percent = parseInt(rMatch[2]);
      item.optionText = this.stripTags(rMatch[3]).trim();
      vote.results.push(item);
    }

    // 检查是否已投票
    vote.status.hasVoted = html.indexOf('voteresult') >= 0 || vote.results.length > 0;
    vote.status.canVote = !vote.status.hasVoted && vote.options.length > 0;
    vote.isExpired = html.indexOf('pollend') >= 0 || html.indexOf('已结束') >= 0;

    return vote.options.length > 0 ? vote : null;
  }

  // ==================== 最新帖子/热帖 ====================

  async getNewThreads(page: number = 1): Promise<Topic[]> {
    return this.getGuideList('newthread', page);
  }

  async getNewReplies(page: number = 1): Promise<Topic[]> {
    return this.getGuideList('new', page);
  }

  async getHotThreads(page: number = 1): Promise<Topic[]> {
    return this.getGuideList('hot', page);
  }

  /**
   * 拉取指定用户的主题/回帖列表（home.php?mod=space&do=thread）。
   * @param uid   目标用户（0=当前登录用户）
   * @param page  页码
   * @param view  'me' 他的主题；'reply' 他的回帖
   * @param type  'thread' / 'reply'
   */
  async getMyThreads(uid: number, page: number = 1, view: string = 'me', type: string = 'thread'): Promise<TopicListResult> {
    const empty: TopicListResult = new TopicListResult();
    if (uid === 0) return empty;
    const url = this.baseUrl(`home.php?mod=space&uid=${uid}&do=thread&view=${view}&type=${type}&page=${page}&mobile=2`);
    try {
      const resp = await this.http.get(url);
      if (!resp.isOk || resp.body.length === 0) return empty;
      return this.parseTopicList(resp.body);
    } catch (e) {
      hilog.error(0xFF00, 'RuisiApiService', 'getMyThreads error: ' + JSON.stringify(e));
      return empty;
    }
  }

  /** 我的收藏：桌面版模板 #favorite_ul > li（对齐安卓 &mobile=no），含标题/时间/favId */
  async getMyFavorites(page: number = 1): Promise<Topic[]> {
    const url = this.baseUrl(`home.php?mod=space&do=favorite&type=thread&page=${page}&mobile=no`);
    try {
      const resp = await this.http.get(url);
      if (!resp.isOk || resp.body.length === 0) return [];
      const result = this.parseFavorites(resp.body);
      return result;
    } catch (e) {
      hilog.error(0xFF00, 'RuisiApiService', 'getMyFavorites error: ' + JSON.stringify(e));
      return [];
    }
  }

  private parseFavorites(html: string): Topic[] {
    const topics: Topic[] = [];
    // 桌面版收藏结构：#favorite_ul > li，每个 li 含 <a>标题</a> + <span class="xg1">时间</span> + <input value="favId">
    const ulMatch = html.match(/<ul[^>]*id="favorite_ul"[^>]*>([\s\S]*?)<\/ul>/i);
    if (!ulMatch) return [];

    const liRegex = /<li[^>]*>([\s\S]*?)<\/li>/gi;
    let m: RegExpExecArray | null;
    while ((m = liRegex.exec(ulMatch[1])) !== null) {
      const block = m[1];
      // tid 从 viewthread 链接提取
      const tidMatch = block.match(/forum\.php\?mod=viewthread(?:&amp;|&)tid=(\d+)/i);
      if (!tidMatch) continue;
      const topic = new Topic();
      topic.tid = parseInt(tidMatch[1]);

      // 标题
      const titleMatch = block.match(/<a[^>]*href="[^"]*viewthread[^"]*"[^>]*>([\s\S]*?)<\/a>/i);
      if (titleMatch) topic.title = this.stripTags(titleMatch[1]).trim();

      // 收藏时间：<span class="xg1"><span title="2026-7-16 00:21">...</span></span>
      // 取内层 span 的 title 属性得到精确时间
      const timeMatch = block.match(/<span[^>]*title="([\d\-]+ [\d:]+)"/i);
      if (timeMatch) topic.postTime = timeMatch[1].trim();

      // favId：<input ... class="pc" value="199248" ...>
      const favMatch = block.match(/<input[^>]*value="(\d+)"[^>]*vid="/i);
      if (favMatch) topic.favId = parseInt(favMatch[1]);

      topics.push(topic);
    }
    return topics;
  }

  private async getGuideList(view: string, page: number): Promise<Topic[]> {
    const url = this.baseUrl(`forum.php?mod=guide&view=${view}&page=${page}`);
    try {
      // 用桌面 UA，让服务器返回桌面 #threadlist 模板（td.num 含回复/浏览），对齐 Flutter
      const resp = await this.http.get(url, { 'User-Agent': RUISI_DESKTOP_UA });
      if (!resp.isOk || resp.body.length === 0) return [];
      const result = this.parseTopicList(resp.body).topics;
      return result;
    } catch (e) {
      hilog.error(0xFF00, 'RuisiApiService', 'getGuideList error: ' + JSON.stringify(e));
      return [];
    }
  }

  private parseGuideList(html: string): Topic[] {
    const topics: Topic[] = [];
    const topicRegex = /<li[^>]*>[\s\S]*?<a[^>]*href="forum\.php\?mod=viewthread&tid=(\d+)[^"]*"[^>]*>([^<]+)<\/a>[\s\S]*?<\/li>/gi;
    let tMatch: RegExpExecArray | null;
    while ((tMatch = topicRegex.exec(html)) !== null) {
      const topic = new Topic();
      topic.tid = parseInt(tMatch[1]);
      topic.title = this.stripTags(tMatch[2]).trim();
      const block = tMatch[0];
      const authorMatch = block.match(/<a[^>]*href="home\.php\?mod=space(?:&amp;|&)uid=(\d+)[^"]*"[^>]*>([^<]+)<\/a>/i);
      if (authorMatch) {
        topic.authorId = parseInt(authorMatch[1]);
        topic.author = authorMatch[2].trim();
      }
      const replyMatch = block.match(/<em[^>]*>(\d+)<\/em>/i);
      if (replyMatch) topic.replies = parseInt(replyMatch[1]);
      const timeMatch = block.match(/(\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2})/);
      if (timeMatch) topic.postTime = timeMatch[1].trim();
      topics.push(topic);
    }

    // 桌面版 guide 格式
    if (topics.length === 0) {
      const trRegex = /<tr[^>]*class="[^"]*bm_c[^"]*"[^>]*>[\s\S]*?<\/tr>/gi;
      let trMatch: RegExpExecArray | null;
      while ((trMatch = trRegex.exec(html)) !== null) {
        const block = trMatch[0];
        const tidMatch = block.match(/tid=(\d+)/);
        if (!tidMatch) continue;
        const topic = new Topic();
        topic.tid = parseInt(tidMatch[1]);
        const titleMatch = block.match(/<a[^>]*>([^<]+)<\/a>/i);
        if (titleMatch) topic.title = this.stripTags(titleMatch[1]).trim();
        const authorMatch = block.match(/<a[^>]*href="home\.php\?mod=space(?:&amp;|&)uid=(\d+)[^"]*"[^>]*>([^<]+)<\/a>/i);
        if (authorMatch) {
          topic.authorId = parseInt(authorMatch[1]);
          topic.author = authorMatch[2].trim();
        }
        const replyMatch = block.match(/<td[^>]*>(\d+)<\/td>/);
        if (replyMatch) topic.replies = parseInt(replyMatch[1]);
        topics.push(topic);
      }
    }

    return topics;
  }

  // ==================== 搜索 ====================

  // 桌面版 UA：用于重新拉取桌面搜索结果页（含作者/回复数/板块/阅读量/时间等完整信息）。
  // 移动版 UA + mobile=2 只会拿到 div.threadlist（仅标题，对齐官方 Android/iOS），
  // 本 App 要在列表项展示更丰富的字段，故用桌面 UA 重拉一次桌面版。
  private static readonly DESKTOP_UA =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

  async search(keyword: string, page: number = 1): Promise<SearchResult[]> {
    // Discuz 搜索流程：
    // 1) 第 1 页 POST search.php?mod=forum&mobile=2（参数 srchtxt=关键词），
    //    302 重定向里会带上 searchid（服务端强制 mobile=2，无法用桌面版 POST 直接拿到）。
    // 2) 用 searchid + 桌面 UA 重新 GET 桌面版结果页（不带 mobile=2），得到含作者/回复数/板块的完整结构。
    // 3) 极端情况下桌面版拉不到，则兜底解析移动版（仅标题 + 链接，对齐官方 Android/iOS）。
    try {
      if (page <= 1) {
        this.lastKeyword = keyword;
        const url = this.baseUrl('search.php?mod=forum&mobile=2');
        const data: Record<string, string> = {
          'searchsubmit': 'yes',
          'srchtxt': keyword,
        };
        const resp = await this.http.postFollowRedirect(url, data, {
          'Referer': this.baseUrl('forum.php'),
        });
        if (!resp.isOk || resp.body.length === 0) return [];
        // 从（移动版）响应里取 searchid，供桌面版重拉与翻页使用
        const sid = resp.body.match(/searchid=(\d+)/);
        if (sid) this.lastSearchId = sid[1];
        // 优先：桌面版（完整字段）
        const desktop = await this.fetchDesktopSearch(this.lastKeyword, this.lastSearchId, 1);
        if (desktop.length > 0) return desktop;
        // 兜底：移动版（仅标题）
        return this.parseMobileSearchResults(resp.body);
      } else {
        const desktop = await this.fetchDesktopSearch(this.lastKeyword, this.lastSearchId, page);
        if (desktop.length > 0) return desktop;
        // 翻页兜底：移动版
        const url = this.baseUrl(
          `search.php?mod=forum&searchid=${this.lastSearchId}` +
          `&orderby=lastpost&ascdesc=desc&searchsubmit=yes&kw=${encodeURIComponent(this.lastKeyword)}` +
          `&page=${page}&mobile=2`
        );
        const r2 = await this.http.get(url);
        return r2.isOk ? this.parseMobileSearchResults(r2.body) : [];
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'search failed: ' + JSON.stringify(e));
      return [];
    }
  }

  // 用桌面 UA 拉取桌面版搜索结果页（含作者/回复数/板块/阅读量/时间等完整信息）
  private async fetchDesktopSearch(keyword: string, searchid: string, page: number): Promise<SearchResult[]> {
    if (!searchid) return [];
    const url = this.baseUrl(
      `search.php?mod=forum&searchid=${searchid}` +
      `&orderby=lastpost&ascdesc=desc&searchsubmit=yes&kw=${encodeURIComponent(keyword)}` +
      `&page=${page}`
    );
    try {
      const resp = await this.http.get(url, { 'User-Agent': RuisiApiService.DESKTOP_UA });
      if (!resp.isOk || resp.body.length === 0) return [];
      const titleMatch = resp.body.match(/<title>([^<]*)<\/title>/i);

      return this.parseSearchResults(resp.body);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'fetchDesktopSearch failed: ' + JSON.stringify(e));
      return [];
    }
  }

  // 兜底：解析移动版搜索结果（div.threadlist > li > a），仅标题 + tid。
  // 对齐官方 Android（SearchActivity: div.threadlist li a）与 iOS（SearchViewController: body/div[1]/ul/li a）。
  private parseMobileSearchResults(html: string): SearchResult[] {
    html = html.replace(/&amp;/g, '&');
    const results: SearchResult[] = [];
    const seen = new Set<number>();
    const liRegex = /<li[^>]*>([\s\S]*?)<\/li>/gi;
    let liMatch: RegExpExecArray | null;
    while ((liMatch = liRegex.exec(html)) !== null) {
      const block = liMatch[1];
      const aMatch = block.match(/<a[^>]*href="[^"]*mod=viewthread&tid=(\d+)[^"]*"[^>]*>([\s\S]*?)<\/a>/i);
      if (!aMatch) continue;
      const tid = parseInt(aMatch[1]);
      if (!tid || seen.has(tid)) continue;
      seen.add(tid);
      const r = new SearchResult();
      r.tid = tid;
      r.title = this.stripTags(aMatch[2]).trim();
      if (r.title.length > 0) results.push(r);
    }
    return results;
  }

  private parseSearchResults(html: string): SearchResult[] {
    // 对齐官方 Flutter ruisi_flutter：搜索结果用【桌面版】结构解析（不带 mobile=2）。
    // 真实 HTML 结构（Discuz X3.2 search/thread.htm）：
    //   <div id="threadlist"><ul>
    //     <li class="pbw" id="1188318">                      ← tid 来自 li.id
    //       <h3 class="xs3"><a href="...viewthread&tid=1188318&highlight=...">标题</a></h3>
    //       <p class="xg1">0 个回复 - 0 次查看</p>           ← 统计
    //       <p>内容摘要...</p>
    //       <p><span>2026-5-25 14:15</span> - <span><a href="space-uid-314082.html">作者</a></span> - <span><a href="forum-110-1.html" class="xi1">板块</a></span></p>
    //     </li>
    // 桌面版 href 也可能用 &amp; 实体转义，统一还原成 & 再解析（幂等、无害）。
    html = html.replace(/&amp;/g, '&');
    const results: SearchResult[] = [];
    const seen = new Set<number>();

    const liRegex = /<li[^>]*class="[^"]*pbw[^"]*"[^>]*id="(\d+)"[^>]*>([\s\S]*?)<\/li>/gi;
    let liMatch: RegExpExecArray | null;
    while ((liMatch = liRegex.exec(html)) !== null) {
      let tid = parseInt(liMatch[1]);
      const block = liMatch[2];
      if (!tid) {
        const tm = block.match(/mod=viewthread&tid=(\d+)/i);
        if (tm) tid = parseInt(tm[1]);
      }
      if (!tid || seen.has(tid)) continue;
      seen.add(tid);
      const r = new SearchResult();
      r.tid = tid;

      // 标题：h3.xs3 > a(viewthread&tid)
      const titleMatch = block.match(/<h3[^>]*>[\s\S]*?<a[^>]*href="[^"]*mod=viewthread&tid=\d+[^"]*"[^>]*>([\s\S]*?)<\/a>/i);
      r.title = titleMatch ? this.stripTags(titleMatch[1]).trim() : '';

      // 统计（复用通用的 xg1「N 个回复 - M 次查看」提取逻辑）
      const stats = this.extractStatsFromBlock(block);
      r.replies = stats.replies;
      r.views = stats.views;

      // 作者：<a href="space-uid-NUM.html">NAME</a>（桌面版搜索用相对链接，不是 mod=space&uid=）
      const authorMatch = block.match(/<a[^>]*href="[^"]*space-uid-(\d+)\.html"[^>]*>([\s\S]*?)<\/a>/i);
      if (authorMatch) {
        r.authorId = parseInt(authorMatch[1]);
        r.author = this.stripTags(authorMatch[2]).trim();
      }

      // 板块：<a href="forum-NUM-1.html" class="xi1">NAME</a>
      const forumMatch = block.match(/<a[^>]*href="[^"]*forum-(\d+)-1\.html"[^>]*>([\s\S]*?)<\/a>/i);
      if (forumMatch) {
        r.fid = parseInt(forumMatch[1]);
        r.forumName = this.stripTags(forumMatch[2]).trim();
      }

      // 时间：<span>YYYY-M-D HH:MM</span>
      const timeMatch = block.match(/<span>([\d-]+\s*[\d:]*?)<\/span>/);
      if (timeMatch) r.postTime = timeMatch[1].trim();

      // 摘要：取不含 class 且不含 <span> 的纯文本 <p>（跳过 xg1 统计段与含元信息的段）
      const pAll = block.match(/<p[^>]*>([\s\S]*?)<\/p>/gi) || [];
      for (let i = 0; i < pAll.length; i++) {
        const p = pAll[i];
        if (/class="xg1"/i.test(p)) continue;
        if (/<span/i.test(p)) continue;
        const ex = this.stripTags(p.replace(/<p[^>]*>|<\/p>/gi, '')).trim();
        if (ex.length > 0) { r.excerpt = ex; break; }
      }

      results.push(r);
    }

    return results;
  }

  // ==================== 回复 ====================

  async reply(tid: number, fid: number, content: string, attachmentAids?: string[]): Promise<ReplyResult> {
    const formhash = this.http.getFormhash();
    const url = this.baseUrl(
      `forum.php?mod=post&action=reply&fid=${fid}&tid=${tid}&extra=&replysubmit=yes&inajax=1&handlekey=fastpost`
    );
    const data: Record<string, string> = {
      'formhash': formhash,
      'message': content,
      'usesig': '1',
      'posttime': String(Math.floor(Date.now() / 1000)),
    };
    // 关联已上传的图片附件（Discuz 用 attachnew[aid]= 引用）
    if (attachmentAids) {
      for (const aid of attachmentAids) {
        data[`attachnew[${aid}]`] = '';
      }
    }

    try {
      const resp = await this.http.post(url, data, {
        'Referer': this.baseUrl(`forum.php?mod=viewthread&tid=${tid}`),
        'X-Requested-With': 'XMLHttpRequest',
      });
      if (resp.isOk && resp.body.length > 0) {
        const body = resp.body;
        if (body.indexOf('succeedhandle') >= 0 || body.indexOf('成功') >= 0) {
          const r = new ReplyResult();
          r.success = true;
          r.message = '回复成功';
          return r;
        }
        if (body.indexOf('两次发表间隔') >= 0) {
          const match = body.match(/(\d+)\s*秒/);
          const r = new ReplyResult();
          r.message = `请等待${match ? match[1] : '几'}秒后再回复`;
          return r;
        }
        const errMatch = body.match(/<p[^>]*>([^<]+)<\/p>/i);
        const r = new ReplyResult();
        r.message = errMatch ? errMatch[1] : '回复失败';
        return r;
      }
      const r = new ReplyResult();
      r.message = '网络错误';
      return r;
    } catch (e) {
      const r = new ReplyResult();
      r.message = '回复失败: ' + String(e);
      return r;
    }
  }

  // ==================== 发帖 ====================

  async getNewPostPageMeta(fid: number): Promise<PostPageMeta> {
    const meta = new PostPageMeta();
    meta.fid = fid;
    const url = this.baseUrl(`forum.php?mod=post&action=newthread&fid=${fid}&mobile=2`);
    try {
      const resp = await this.http.get(url);
      if (!resp.isOk || resp.body.length === 0) return meta;
      // 提取 formhash
      const fhMatch = resp.body.match(/name="formhash"\s+value="([a-f0-9]+)"/i) ||
        resp.body.match(/formhash=([a-f0-9]+)/i);
      if (fhMatch) {
        meta.formhash = fhMatch[1];
        this.http.setFormhash(fhMatch[1]);
      }
      // 提取帖子类型选项（标签页 / 主题分类），保留 id 用于提交 typeid
      const typeRegex = /<option[^>]*value="(\d+)"[^>]*>([^<]+)<\/option>/gi;
      let tMatch: RegExpExecArray | null;
      while ((tMatch = typeRegex.exec(resp.body)) !== null) {
        const id = parseInt(tMatch[1]);
        const name = tMatch[2].trim();
        if (id > 0 && name.length > 0) {
          const opt = new ForumTypeOption();
          opt.id = id;
          opt.name = name;
          meta.typeOptions.push(opt);
        }
      }
      // 提取上传凭证：Discuz 在 newthread 页内嵌 uploadformdata:{uid:"...", hash:"..."}
      // 不能简单正则 hash=/uid=（会误抓 formhash 或页面里其他 uid 链接，iOS/Android 均从该块解析）
      const ufIdx = resp.body.indexOf('uploadformdata:');
      if (ufIdx >= 0) {
        const block = resp.body.substring(ufIdx, ufIdx + 300);
        const uMatch = block.match(/uid\s*[:=]\s*["']?\s*(\d+)\s*["']?/);
        const hMatch = block.match(/hash\s*[:=]\s*["']?\s*([a-f0-9]+)\s*["']?/i);
        if (uMatch) meta.uploadUid = uMatch[1];
        if (hMatch) meta.uploadHash = hMatch[1];
      }
      // 验证码 hash
      const scMatch = resp.body.match(/seccodehash['"]?\s*[:=]\s*['"]([a-zA-Z0-9_%]+)['"]/i);
      if (scMatch) meta.seccodeHash = decodeURIComponent(scMatch[1]);
      meta.isImageUploadEnabled = resp.body.indexOf('swfupload') >= 0 || resp.body.indexOf('imageupload') >= 0;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'getNewPostPageMeta failed: ' + JSON.stringify(e));
    }
    return meta;
  }

  async newThread(
    fid: number,
    subject: string,
    content: string,
    typeId?: number,
    formhash?: string,
    attachmentAids?: string[]
  ): Promise<NewPostResult> {
    const fh = formhash || this.http.getFormhash();
    const url = this.baseUrl(
      `forum.php?mod=post&action=newthread&fid=${fid}&extra=&topicsubmit=yes&inajax=1`
    );
    const data: Record<string, string> = {
      'formhash': fh,
      'subject': subject,
      'message': content,
      'usesig': '1',
      'allownoticeauthor': '1',
      'posttime': String(Math.floor(Date.now() / 1000)),
      'wysiwyg': '0',
    };
    if (typeId !== undefined && typeId > 0) data['typeid'] = String(typeId);
    // 关联已上传的图片附件
    if (attachmentAids) {
      for (const aid of attachmentAids) {
        data[`attachnew[${aid}]`] = '';
      }
    }

    try {
      const resp = await this.http.post(url, data, {
        'Referer': this.baseUrl(`forum.php?mod=post&action=newthread&fid=${fid}`),
        'X-Requested-With': 'XMLHttpRequest',
      });
      if (resp.isOk && resp.body.length > 0) {
        const body = resp.body;
        if (body.indexOf('succeedhandle') >= 0 || body.indexOf('成功') >= 0) {
          const tidMatch = body.match(/tid=(\d+)/) || body.match(/succeedhandle_newthread\([^,]+,\s*(\d+)/);
          const r = new NewPostResult();
          r.success = true;
          r.message = '发帖成功';
          r.tid = tidMatch ? parseInt(tidMatch[1]) : 0;
          return r;
        }
        const errMatch = body.match(/<p[^>]*>([^<]+)<\/p>/i) || body.match(/errmsg[^>]*>([^<]+)/i);
        const r2 = new NewPostResult();
        r2.message = errMatch ? errMatch[1] : '发帖失败';
        return r2;
      }
      const r3 = new NewPostResult();
      r3.message = '网络错误';
      return r3;
    } catch (e) {
      const r4 = new NewPostResult();
      r4.message = '发帖失败: ' + String(e);
      return r4;
    }
  }

  // ==================== 收藏 ====================

  async favorite(tid: number): Promise<FavoriteResult> {
    const formhash = this.http.getFormhash();
    const url = this.baseUrl(`home.php?mod=spacecp&ac=favorite&type=thread&id=${tid}&inajax=1`);
    const data: Record<string, string> = {
      'formhash': formhash,
      'favsubmit': 'true',
      'description': '',
    };
    try {
      const resp = await this.http.post(url, data, {
        'Referer': this.baseUrl(`forum.php?mod=viewthread&tid=${tid}`),
      });
      if (resp.isOk && resp.body.length > 0) {
        if (resp.body.indexOf('收藏成功') >= 0 || resp.body.indexOf('succeedhandle') >= 0) {
          const r = new FavoriteResult();
          r.success = true;
          r.message = '收藏成功';
          return r;
        }
        if (resp.body.indexOf('已收藏') >= 0) {
          const r = new FavoriteResult();
          r.success = true;
          r.message = '已收藏';
          return r;
        }
      }
      const r2 = new FavoriteResult();
      r2.message = '收藏失败';
      return r2;
    } catch (e) {
      const r3 = new FavoriteResult();
      r3.message = '收藏失败';
      return r3;
    }
  }

  /** 取消收藏：通过 tid 删除（Discuz 支持 op=delete&id=TID 直接删） */
  async unfavorite(tid: number): Promise<FavoriteResult> {
    const formhash = this.http.getFormhash();
    const url = this.baseUrl(`home.php?mod=spacecp&ac=favorite&op=delete&type=thread&id=${tid}&inajax=1`);
    const data: Record<string, string> = {
      'formhash': formhash,
      'deletesubmit': 'true',
    };
    try {
      const resp = await this.http.post(url, data, {
        'Referer': this.baseUrl(`forum.php?mod=viewthread&tid=${tid}`),
      });
      if (resp.isOk && resp.body.length > 0) {
        if (resp.body.indexOf('成功') >= 0 || resp.body.indexOf('succeedhandle') >= 0) {
          const r = new FavoriteResult();
          r.success = true;
          r.message = '已取消收藏';
          return r;
        }
      }
      const r2 = new FavoriteResult();
      r2.message = '取消收藏失败';
      return r2;
    } catch (e) {
      const r3 = new FavoriteResult();
      r3.message = '取消收藏失败';
      return r3;
    }
  }

  /** 取消收藏：通过 favId 删除（对齐安卓 op=delete&favid=XXX&type=all） */
  async unfavoriteByFavId(favId: number): Promise<FavoriteResult> {
    const formhash = this.http.getFormhash();
    const url = this.baseUrl(`home.php?mod=spacecp&ac=favorite&op=delete&favid=${favId}&type=all&inajax=1&mobile=2`);
    const data: Record<string, string> = {
      'formhash': formhash,
      'deletesubmit': 'true',
      'handlekey': `a_delete_${favId}`,
    };
    try {
      const resp = await this.http.post(url, data);
      if (resp.isOk && resp.body.length > 0) {
        if (resp.body.indexOf('操作成功') >= 0 || resp.body.indexOf('成功') >= 0) {
          const r = new FavoriteResult();
          r.success = true;
          r.message = '已取消收藏';
          return r;
        }
      }
      const r2 = new FavoriteResult();
      r2.message = '取消收藏失败';
      return r2;
    } catch (e) {
      const r3 = new FavoriteResult();
      r3.message = '取消收藏失败';
      return r3;
    }
  }

  // ==================== 举报 ====================

  /**
   * 获取举报表单（真实协议，已实抓确认）。
   * GET misc.php?mod=report&rtype={rtype}&rid={rid}&tid={tid}&fid={fid}&inajax=1&handlekey=report
   * 解析：
   *  - formhash（隐藏域 name="formhash"）
   *  - 举报理由（JS：var reasons = ['...']，睿思仅一个确认项，非分类下拉）
   * @param rtype 'post' 举报某楼 | 'thread' 举报整帖
   * @param rid   帖子/楼层 id（post→pid，thread→tid）
   * @param tid   帖子 id
   * @param fid   版块 id
   */
  async getReportForm(rtype: string, rid: number, tid: number, fid: number): Promise<ReportForm> {
    const result = new ReportForm();
    const url = this.baseUrl(
      `misc.php?mod=report&rtype=${rtype}&rid=${rid}&tid=${tid}&fid=${fid}&inajax=1&handlekey=report`
    );
    try {
      const resp = await this.http.get(url);
      if (!resp.isOk || resp.body.length === 0) return result;
      const body = resp.body;
      // formhash 隐藏域
      const fhMatch = body.match(/name=["']formhash["'][^>]*value=["']([a-f0-9]+)["']/i);
      if (fhMatch) {
        result.formhash = fhMatch[1];
        this.http.setFormhash(fhMatch[1]);
      }
      // 举报理由：JS 数组 var reasons = ['...']（睿思当前仅一项确认文案）
      const rjMatch = body.match(/var\s+reasons\s*=\s*\[(.*?)\]/s);
      if (rjMatch) {
        const arr = rjMatch[1];
        const itemRe = /'([^']*)'|"([^"]*)"/g;
        let im: RegExpExecArray | null;
        while ((im = itemRe.exec(arr)) !== null) {
          const t = (im[1] || im[2] || '').trim();
          if (t.length > 0) result.reasons.push(t);
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'getReportForm failed: ' + JSON.stringify(e));
    }
    return result;
  }

  /**
   * 提交举报（真实协议，已实抓确认）。
   * POST misc.php?mod=report，表单字段与网页完全一致：
   *   formhash / referer / reportsubmit=true / rtype / rid / fid / url='' /
   *   inajax=1 / handlekey=report / report_select=<确认项文案> / message=<描述>
   * @param rtype    'post' | 'thread'
   * @param rid      帖子/楼层 id
   * @param tid      帖子 id
   * @param fid      版块 id
   * @param reason   举报理由值（report_select，来自 getReportForm 的 reasons[0]）
   * @param message  自由描述（对应网页 textarea name=message）
   * @param formhash 建议传 getReportForm 返回的新鲜值
   */
  async submitReport(
    rtype: string,
    rid: number,
    tid: number,
    fid: number,
    reason: string,
    message: string,
    formhash?: string
  ): Promise<ReportResult> {
    const fh = formhash && formhash.length > 0 ? formhash : this.http.getFormhash();
    const url = this.baseUrl('misc.php?mod=report');
    const data: Record<string, string> = {
      'formhash': fh,
      'referer': this.baseUrl(`forum.php?mod=viewthread&tid=${tid}`),
      'reportsubmit': 'true',
      'rtype': rtype,
      'rid': String(rid),
      'fid': String(fid),
      'url': '',
      'inajax': '1',
      'handlekey': 'report',
      'report_select': reason && reason.length > 0 ? reason : '',
      'message': message && message.length > 0 ? message : '',
    };
    const result = new ReportResult();
    try {
      const resp = await this.http.post(url, data, {
        'Referer': this.baseUrl(`forum.php?mod=viewthread&tid=${tid}`),
        'X-Requested-With': 'XMLHttpRequest',
      });
      if (resp.isOk && resp.body.length > 0) {
        const body = resp.body;
        if (body.indexOf('举报成功') >= 0 || body.indexOf('succeedhandle') >= 0) {
          result.success = true;
          result.message = '举报已提交，感谢反馈';
          return result;
        }
        const errMatch = body.match(/errorhandle_report\('([^']*)'/i)
          || body.match(/<p[^>]*>([^<]+)<\/p>/i);
        result.message = errMatch ? errMatch[1].trim() : '举报失败';
        return result;
      }
      result.message = '网络错误';
      return result;
    } catch (e) {
      result.message = '举报失败: ' + String(e);
      return result;
    }
  }

  // ==================== 签到 ====================

  async sign(qiandao: string = 'kx'): Promise<SignResult> {
    const result = new SignResult();
    try {
      // 0) 确保登录态有效（cookie 过期则自动续登；无凭证则提示先登录）
      const loggedIn = await this.checkAndAutoLogin();
      if (!loggedIn) {
        result.success = false;
        result.message = '请先登录睿思';
        return result;
      }

      // 1) GET 签到页：刷新 formhash，并判断是否已经登录
      //    注意：dsu_paulsign 插件没有移动端模板，且本 App 进论坛时会种下 mobile cookie，
      //    导致签到被当移动端返回"无手机页面"。对齐 iOS 官方客户端，强制 mobile=no 走桌面端。
      let formhash = this.http.getFormhash();
      const pageUrl = this.baseUrl('plugin.php?id=dsu_paulsign:sign&mobile=no');
      const pageResp = await this.http.get(pageUrl);
      if (pageResp.isOk && pageResp.body.length > 0) {
        // 未登录：签到页出现登录入口
        if (pageResp.body.indexOf('member.php?mod=logging') >= 0 && pageResp.body.indexOf('登录') >= 0) {
          result.success = false;
          result.message = '请先登录睿思';
          return result;
        }
        // 动态提取最新 formhash（避免写死/过期）
        const fhMatch = pageResp.body.match(/formhash=([a-f0-9]{6,})/i)
          || pageResp.body.match(/name="formhash"[^>]*value="([a-f0-9]+)"/i)
          || pageResp.body.match(/<input[^>]*name="formhash"[^>]*value="([^"]*)"/i);
        if (fhMatch && fhMatch[1].length > 0) {
          formhash = fhMatch[1];
          this.http.setFormhash(formhash);
        }
      }
      if (!formhash || formhash.length === 0) {
        result.success = false;
        result.message = '签到失败：无法获取 formhash';
        return result;
      }

      // 2) POST 签到。字段集对齐已验证可用的 Flutter 官方客户端（traintime_pda）：
      //    qdxq / qdmode=3 / operation / infloat + 自动注入的 formhash
      //    关键：qdmode=3 表示"不填写"模式，服务端不校验今日想说(todaysay)；
      //          之前用 qdmode=1 会把 todaysay 当必填，留空就报"未输入今日想说"。
      //    不要发送 todaysay / fastreplay / 签到页隐藏域(fastion 等)，否则会被判非法提交。
      const url = this.baseUrl('plugin.php?id=dsu_paulsign:sign&operation=qiandao&infloat=1&inajax=1&mobile=no');
      const data: Record<string, string> = {
        'formhash': formhash,
        'qdxq': qiandao,
        'qdmode': '3',
      };
      const resp = await this.http.post(url, data, { 'Referer': pageUrl });
      if (resp.isOk && resp.body.length > 0) {
        const body = resp.body;
        const isSuccess = body.indexOf('签到成功') >= 0 || body.indexOf('succeedhandle') >= 0
          || body.indexOf('恭喜') >= 0;
        const isAlready = body.indexOf('今日已签到') >= 0 || body.indexOf('已经签到') >= 0
          || body.indexOf('已经签到过') >= 0 || body.indexOf('已经签到过了') >= 0
          || body.indexOf('您今天已经签到过了') >= 0 || body.indexOf('签到时间还未开始') >= 0;
        if (isSuccess || isAlready) {
          result.success = isSuccess;
          // 提示语只给「签到动作结果」，天数不在这里取——避免额外阻塞请求拖慢签到。
          // 天数由调用方另行异步 getSignStats() 拉取并单独提示（见 RuisiUserPage.doSign）。
          result.message = isAlready ? '今日已签到' : '签到成功';
          if (isSuccess) {
            const rewardMatch = body.match(/奖励[：:]?\s*([^<\n]+)/);
            if (rewardMatch) result.reward = rewardMatch[1].trim();
          }
        } else if (body.indexOf('未加入允许签到') >= 0 || body.indexOf('用户组') >= 0) {
          result.success = false;
          result.message = '当前用户组不支持签到';
        } else {
          const errMatch = body.match(/<p[^>]*>([^<]+)<\/p>/i)
            || body.match(/class="c">([^<]+)</i)
            || body.match(/errmsg[^>]*>([^<]+)/i);
          result.message = errMatch ? errMatch[1].trim() : '签到失败';
        }
      } else {
        result.message = '签到失败：无响应';
      }
    } catch (e) {
      result.message = '签到失败: ' + String(e);
    }
    return result;
  }

  /**
   * 单独拉取签到统计（累计 / 本月天数），与签到动作解耦，不阻塞签到提示。
   * 从签到页 HTML 取「您累计已签到 N 天」「您本月已累计签到 N 天」
   * （对标官方 Android SignActivity / iOS SignViewController：统计行在签到页 .mn p 中）。
   * 正则用 [^\d]* 跳过标签/空格，兼容「<strong>123</strong>天」这类结构。
   */
  async getSignStats(): Promise<SignStats> {
    const stats: SignStats = { totalDays: 0, monthDays: 0 };
    try {
      const resp = await this.http.get(this.baseUrl('plugin.php?id=dsu_paulsign:sign&mobile=no'));

      if (resp.isOk && resp.body.length > 0) {
        const tm = resp.body.match(/您累计已签到[^\d]*(\d+)/);
        if (tm) stats.totalDays = parseInt(tm[1]);
        const mm = resp.body.match(/您本月已累计签到[^\d]*(\d+)/);
        if (mm) stats.monthDays = parseInt(mm[1]);
      }
    } catch (e) {}

    return stats;
  }

  // ==================== 消息通知 ====================

  async getReplyNotifications(page: number = 1): Promise<ReplyNotification[]> {
    const url = this.baseUrl(`home.php?mod=space&do=notice&view=reply&page=${page}&mobile=2`);
    try {
      const resp = await this.http.get(url);
      if (!resp.isOk || resp.body.length === 0) return [];
      return this.parseReplyNotifications(resp.body);
    } catch (e) {
      return [];
    }
  }

  private parseReplyNotifications(html: string): ReplyNotification[] {
    const notifications: ReplyNotification[] = [];
    const notifRegex = /<li[^>]*class="[^"]*note_[^"]*"[^>]*>[\s\S]*?<\/li>/gi;
    let nMatch: RegExpExecArray | null;
    while ((nMatch = notifRegex.exec(html)) !== null) {
      const notif = new ReplyNotification();
      const block = nMatch[0];
      const tidMatch = block.match(/tid=(\d+)/);
      if (tidMatch) notif.tid = parseInt(tidMatch[1]);
      const pidMatch = block.match(/pid=(\d+)/);
      if (pidMatch) notif.pid = parseInt(pidMatch[1]);
      const titleMatch = block.match(/<a[^>]*>([^<]+)<\/a>/i);
      if (titleMatch) notif.title = titleMatch[1].trim();
      const authorMatch = block.match(/<a[^>]*href="home\.php\?mod=space(?:&amp;|&)uid=(\d+)[^"]*"[^>]*>([^<]+)<\/a>/i);
      if (authorMatch) {
        notif.authorId = parseInt(authorMatch[1]);
        notif.author = authorMatch[2].trim();
      }
      const timeMatch = block.match(/(\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2})/) ||
        block.match(/<span[^>]*class="[^"]*time[^"]*"[^>]*>([^<]+)<\/span>/i);
      if (timeMatch) notif.time = timeMatch[1].trim();
      const contentMatch = block.match(/<p[^>]*>([\s\S]*?)<\/p>/i);
      if (contentMatch) notif.content = this.stripTags(contentMatch[1]).trim();
      notif.isNew = block.indexOf('new') >= 0;
      notifications.push(notif);
    }
    return notifications;
  }

  async getAtNotifications(page: number = 1): Promise<AtNotification[]> {
    const url = this.baseUrl(`home.php?mod=space&do=notice&view=at&page=${page}&mobile=2`);
    try {
      const resp = await this.http.get(url);
      if (!resp.isOk || resp.body.length === 0) return [];
      return this.parseAtNotifications(resp.body);
    } catch (e) {
      return [];
    }
  }

  private parseAtNotifications(html: string): AtNotification[] {
    const notifications: AtNotification[] = [];
    // 与回复通知一致：仅限定 class="note_" 的通知项，避免把导航/页脚等页面 li 全部抓进来
    const notifRegex = /<li[^>]*class="[^"]*note_[^"]*"[^>]*>[\s\S]*?<\/li>/gi;
    let nMatch: RegExpExecArray | null;
    while ((nMatch = notifRegex.exec(html)) !== null) {
      const notif = new AtNotification();
      const block = nMatch[0];
      const tidMatch = block.match(/tid=(\d+)/);
      if (tidMatch) notif.tid = parseInt(tidMatch[1]);
      const pidMatch = block.match(/pid=(\d+)/);
      if (pidMatch) notif.pid = parseInt(pidMatch[1]);
      const titleMatch = block.match(/<a[^>]*>([^<]+)<\/a>/i);
      if (titleMatch) notif.title = titleMatch[1].trim();
      const authorMatch = block.match(/<a[^>]*href="home\.php\?mod=space(?:&amp;|&)uid=(\d+)[^"]*"[^>]*>([^<]+)<\/a>/i);
      if (authorMatch) {
        notif.authorId = parseInt(authorMatch[1]);
        notif.author = authorMatch[2].trim();
      }
      const timeMatch = block.match(/(\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2})/);
      if (timeMatch) notif.time = timeMatch[1].trim();
      notif.isNew = block.indexOf('new') >= 0;
      // 跳过没有 tid 的垃圾项（导航/系统链接等）
      if (notif.tid === 0 && notif.title.length === 0) continue;
      notifications.push(notif);
    }
    return notifications;
  }

  // ==================== 私信（短消息） ====================
  // 对齐 Android FrageMessage(index=1, do=pm) / iOS MessageViewController(pos=1, messagePm)

  async getPmList(page: number = 1): Promise<PmConversation[]> {
    const url = this.baseUrl(`home.php?mod=space&do=pm&mobile=2&page=${page}`);
    try {
      const resp = await this.http.get(url);
      if (!resp.isOk || resp.body.length === 0) return [];
      return this.parsePmList(resp.body);
    } catch (e) {
      return [];
    }
  }

  private parsePmList(html: string): PmConversation[] {
    const list: PmConversation[] = [];
    // 仅取 .pmbox 区域内的 li（对齐 Android: .pmbox ul li）
    const pmbox = html.match(/<div[^>]*class="[^"]*pmbox[^"]*"[^>]*>([\s\S]*?)<\/div>/i);
    const region = pmbox ? pmbox[1] : html;
    const liRegex = /<li[^>]*>([\s\S]*?)<\/li>/gi;
    let m: RegExpExecArray | null;
    while ((m = liRegex.exec(region)) !== null) {
      const block = m[0];
      const item = new PmConversation();
      // 会话链接里带 touid
      const tuidM = block.match(/touid=(\d+)/i);
      if (tuidM) item.tuid = parseInt(tuidM[1]);
      if (item.tuid === 0) continue;
      // 用户名
      const nameM = block.match(/class="[^"]*name[^"]*"[^>]*>([^<]+)</i);
      if (nameM) item.username = nameM[1].trim();
      // 时间（.cl.grey .time）
      const timeM = block.match(/class="[^"]*time[^"]*"[^>]*>([^<]+)</i);
      if (timeM) item.time = timeM[1].trim();
      // 头像
      const imgM = block.match(/<img[^>]*src="([^"]+)"[^>]*>/i);
      if (imgM) item.avatar = imgM[1];
      // 内容：去掉时间后的 .cl.grey 文本
      const greyM = block.match(/<(div|p|span)[^>]*class="[^"]*cl[^"]*grey[^"]*"[^>]*>([\s\S]*?)<\/\1>/i);
      if (greyM) {
        let c = greyM[2];
        if (timeM) c = c.replace(timeM[0], ''); // 去掉时间那一段
        item.lastMessage = this.stripTags(c).replace(/\s+/g, ' ').trim();
      }
      // 未读：存在 .num 红点
      item.unread = /class="[^"]*num[^"]*"/i.test(block);
      list.push(item);
    }
    return list;
  }

  /**
   * 拉取与某人的私信对话详情。
   * 对齐 Android ChatActivity / iOS ChatViewController：解析 .msgbox .cl，
   * friend_msg=左侧(对方)，否则右侧(自己)；提取 #pmform 的 action 作为发送地址。
   * @returns messages 按时间正序；replyUrl 为发送接口（为空时用默认地址）
   */
  async getChatDetail(tuid: number, page: number = 1): Promise<ChatDetailResult> {
    const url = this.baseUrl(`home.php?mod=space&do=pm&subop=view&touid=${tuid}&mobile=2&page=${page}`);
    const result = new ChatDetailResult();
    try {
      const resp = await this.http.get(url);
      if (!resp.isOk || resp.body.length === 0) return result;
      const body = resp.body;
      // 发送地址
      const formM = body.match(/<form[^>]*id="pmform"[^>]*action="([^"]+)"[^>]*>/i) ||
        body.match(/<form[^>]*action="([^"]+)"[^>]*id="pmform"[^>]*>/i);
      if (formM) result.replyUrl = formM[1];
      // 没有消息
      if (body.includes('当前没有相应的短消息')) return result;
      // 逐条 .cl（消息左右气泡）：li/dl 配对，避免嵌套标签提前闭合
      const clRegex = /<(li|dl)[^>]*class="[^"]*\bcl\b[^"]*"[^>]*>([\s\S]*?)<\/\1>/gi;
      let m: RegExpExecArray | null;
      while ((m = clRegex.exec(body)) !== null) {
        const cls = (m[0].match(/class="([^"]*)"/i) || [, ''])[1];
        const block = m[0];
        const msg = new ChatMessage();
        msg.isMe = !/friend_msg/i.test(cls);
        // 内容 .dialog_t
        const dlgM = block.match(/<[^>]*class="[^"]*dialog_t[^"]*"[^>]*>([\s\S]*?)<\/[a-z]+>/i);
        if (dlgM) msg.content = this.stripTags(dlgM[1]).replace(/\s+/g, ' ').trim();
        // 时间 .date
        const dateM = block.match(/<[^>]*class="[^"]*date[^"]*"[^>]*>([^<]+)</i);
        if (dateM) msg.time = dateM[1].trim();
        // 对方头像 .avat img
        if (!msg.isMe) {
          const imgM = block.match(/<[^>]*class="[^"]*avat[^"]*"[^>]*>[\s\S]*?<img[^>]*src="([^"]+)"[^>]*>/i);
          if (imgM) msg.avatar = imgM[1];
        }
        if (msg.content.length > 0) result.messages.push(msg);
      }
      return result;
    } catch (e) {
      return result;
    }
  }

  /**
   * 发送私信。对齐 Android ChatActivity.sendClick：POST replyUrl，参数 touid + message。
   * 成功判定：响应含「操作成功」；限流：含「两次发送短消息太快」。
   */
  async sendPm(tuid: number, message: string, replyUrl: string = ''): Promise<ChatResult> {
    const r = new ChatResult();
    const url = replyUrl.length > 0
      ? this.baseUrl(replyUrl)
      : this.baseUrl(`home.php?mod=spacecp&ac=pm&op=send&pmid=${tuid}&daterange=0&pmsubmit=yes&mobile=2`);
    const formhash = this.http.getFormhash();
    const data: Record<string, string> = {
      'touid': String(tuid),
      'message': message,
      'formhash': formhash,
    };
    try {
      const resp = await this.http.post(url, data, {
        'Referer': this.baseUrl(`home.php?mod=space&do=pm&subop=view&touid=${tuid}&mobile=2`),
      });
      if (resp.isOk && resp.body.length > 0) {
        const body = resp.body;
        if (body.indexOf('操作成功') >= 0 || body.indexOf('成功') >= 0) {
          r.success = true;
          r.message = '发送成功';
          return r;
        }
        if (body.indexOf('两次发送短消息太快') >= 0) {
          r.message = '发送太快，请稍候再发';
          return r;
        }
        const errM = body.match(/<p[^>]*>([^<]+)<\/p>/i);
        r.message = errM ? errM[1] : '发送失败';
        return r;
      }
      r.message = '网络错误';
      return r;
    } catch (e) {
      r.message = '发送失败: ' + String(e);
      return r;
    }
  }

  /**
   * 添加好友。对齐 Android AddFriendDialog / iOS UserDetailViewController.doAddFriend：
   * POST home.php?mod=spacecp&ac=friend&op=add&uid=X&inajax=1&mobile=2，
   * 参数 addsubmit/handlekey=friend_X/note/gid/addsubmit_btn。
   * 成功判定：响应含「好友请求已」或「正在等待验证」；已是好友：含「你们已成为好友」。
   */
  async addFriend(uid: number, note: string = ''): Promise<FriendResult> {
    const r = new FriendResult();
    const url = this.baseUrl(`home.php?mod=spacecp&ac=friend&op=add&uid=${uid}&inajax=1&mobile=2`);
    const formhash = this.http.getFormhash();
    const data: Record<string, string> = {
      'addsubmit': 'true',
      'handlekey': `friend_${uid}`,
      'note': note,
      'gid': '1',
      'addsubmit_btn': 'true',
      'formhash': formhash,
    };
    try {
      const resp = await this.http.post(url, data, {
        'Referer': url,
      });
      if (resp.isOk && resp.body.length > 0) {
        const body = resp.body;
        if (body.indexOf('好友请求已') >= 0 || body.indexOf('正在等待验证') >= 0) {
          r.success = true;
          r.message = '好友请求已经发送了，正在等待对方验证';
          return r;
        }
        if (body.indexOf('你们已成为好友') >= 0) {
          r.success = true;
          r.message = '你们已经是好友了，不用再添加啦';
          return r;
        }
        const cdata = body.match(/<root><!\[CDATA\[([\s\S]*?)\]\]><\/root>/i) ||
          body.match(/<p[^>]*>([^<]+)<\/p>/i);
        r.message = cdata ? cdata[1].replace(/\s+/g, ' ').trim() : '添加失败，请稍后再试';
        return r;
      }
      r.message = '网络错误';
      return r;
    } catch (e) {
      r.message = '添加失败: ' + String(e);
      return r;
    }
  }

  // ==================== 用户信息 ====================

  async getUserInfo(uid: number): Promise<UserInfo | null> {
    const url = this.baseUrl(`home.php?mod=space&uid=${uid}&do=profile&mobile=2`);
    try {
      const resp = await this.http.get(url);
      if (!resp.isOk || resp.body.length === 0) return null;
      return this.parseUserInfo(resp.body, uid);
    } catch (e) {
      return null;
    }
  }

  /**
   * 拉取当前登录用户的金币数量。
   * 金币是 Discuz 的扩展积分（独立于总积分），需单独请求：
   *   home.php?mod=spacecp&ac=credit&showcredit=1&inajax=1&mobile=2
   * 响应包裹在 <root><![CDATA[ ... ]]></root> 中，统计项形如
   *   <li>金币 <span>1000</span></li>
   * 对标 iOS NewPostSettingViewController（loadMyMoney）：遍历 li，取含「金币」那项的 span 数值。
   */
  async getCoins(): Promise<number> {
    const url = this.baseUrl('home.php?mod=spacecp&ac=credit&showcredit=1&inajax=1&mobile=2');
    try {
      const resp = await this.http.get(url);
      if (!resp.isOk || resp.body.length === 0) return 0;
      let body = resp.body;
      const cdata = body.match(/<!\[CDATA\[([\s\S]*?)\]\]>/i);
      if (cdata) body = cdata[1];
      const liMatches = body.match(/<li[^>]*>([\s\S]*?)<\/li>/gi);
      if (liMatches) {
        for (const item of liMatches) {
          const label = item.replace(/<[^>]+>/g, '').trim();
          if (label.includes('金币')) {
            const spanM = item.match(/<span[^>]*>([\d,]+)<\/span>/i);
            const num = (spanM ? spanM[1] : label).match(/\d+/);
            if (num) return parseInt(num[0]);
          }
        }
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  private parseUserInfo(html: string, uid: number): UserInfo {
    const info = new UserInfo();
    info.uid = uid;

    // 用户名
    // 桌面版有 <h1 class="mbn"><a>用户名</a>；移动版(mobile=2)常匹配不到，会退回 <title>，
    // 而 title 形如「用户名的个人资料 - 西电睿思 - Powered by Discuz!」，整串会被当成用户名（尾巴一大串）。
    // 故从 title 提取时必须清理：先切掉「 - 」之后的站点后缀，再去掉「的个人资料/空间/主页」等尾缀。
    const h1Match = html.match(/<h1[^>]*class="[^"]*mbn[^"]*"[^>]*>[\s\S]*?<a[^>]*>([^<]+)<\/a>/i);
    if (h1Match) {
      info.username = this.stripTags(h1Match[1]).trim();
    } else {
      const titleMatch = html.match(/<title>([^<]+)<\/title>/i);
      if (titleMatch) {
        let name = this.stripTags(titleMatch[1]).trim();
        const dashIdx = name.indexOf(' - ');
        if (dashIdx > 0) name = name.substring(0, dashIdx).trim();
        name = name.replace(/的(个人资料|空间|主页|资料|档案)$/, '').trim();
        info.username = name;
      }
    }

    // 头像
    const avatarMatch = html.match(/<img[^>]*src="([^"]*avatar[^"]*)"/i) ||
      html.match(/<img[^>]*src="([^"]*uc_server[^"]*)"/i);
    if (avatarMatch) info.avatar = avatarMatch[1];

    // 用户组
    const groupMatch = html.match(/<p[^>]*class="[^"]*pg[^"]*"[^>]*>([^<]+)<\/p>/i);
    if (groupMatch) info.groupTitle = groupMatch[1].trim();

    // 统计项（积分 / 旧积分 / 金币 / 主题 / 帖子 等）
    // 不依赖具体的 <li>/<span> 标签结构，直接在整个 .user_box 块（兜底整页）里按
    // 「标签文字 + 相邻数字」做关联抓取，兼容「标签在前/数字在后」两种顺序，
    // 且先剔除「旧积分」再匹配「积分」，避免被「旧积分」的数值干扰。
    // 这样看他人主页也显示对方的值（而非当前登录用户自己的）。
    this.parseStats(html, info);

    // 注册日期
    const joinMatch = html.match(/注册[：]*<span[^>]*>([^<]+)<\/span>/i) || html.match(/注册时间[：]*([^<\n]+)/i);
    if (joinMatch) info.joinDate = joinMatch[1].trim();

    // 最后访问
    const visitMatch = html.match(/上次访问[：]*<span[^>]*>([^<]+)<\/span>/i);
    if (visitMatch) info.lastVisit = visitMatch[1].trim();

    // 签名
    const sigMatch = html.match(/<div[^>]*class="[^"]*sign[^"]*"[^>]*>([\s\S]*?)<\/div>/i);
    if (sigMatch) info.signature = this.stripTags(sigMatch[1]).trim();

    return info;
  }

  /**
   * 从个人页 HTML 中提取统计项（积分 / 旧积分 / 金币 / 主题 / 帖子）。
   * 主解析逐条处理 <li>（对齐安卓/iOS 的 .user_box ul li：value 在 <span> 内、key 为剩余文字），
   * 兼容「数字在前 / 标签在前」两种顺序、以及 b/em/纯文本等写法。
   * 若某字段仍为 0，再在其所在标签块（li/dd/p/div）内单独兜底抓取，
   * 防止个别模板把「积分」放在 <li> 之外的角落。
   */
  private parseStats(html: string, info: UserInfo): void {
    // 优先在 .user_box 统计块内查找，找不到则退回整页
    const blockM = html.match(/class="[^"]*user_box[^"]*"[\s\S]*?<\/div>\s*<\/div>/i);
    const scope = blockM ? blockM[0] : html;

    // 1) 主解析：逐条 <li>
    const liMatches = scope.match(/<li[^>]*>[\s\S]*?<\/li>/gi);
    if (liMatches) {
      for (const item of liMatches) {
        const text = item.replace(/<[^>]+>/g, '');
        const numM = text.match(/[\d,]+/);
        if (!numM) continue;
        const num = parseInt(numM[0].replace(/,/g, ''));
        const key = text.replace(/[\d,\s]+/g, '').trim();
        if (key.includes('金币')) {
          info.coins = num;
        } else if (key.includes('旧积分')) {
          info.oldCredits = num;
        } else if (key.includes('积分')) {
          info.credits = num;
        } else if (key.includes('主题')) {
          info.threads = num;
        } else if (key.includes('帖子')) {
          info.posts = num;
        }
      }
    }

    // 2) 兜底：某字段仍为 0 时，在其所在标签块内单独抓取数字
    if (info.credits === 0) {
      const m = this.grabInBlock(scope.replace(/旧积分/g, ''), '积分');
      if (m > 0) info.credits = m;
    }
    if (info.oldCredits === 0) {
      const m = this.grabInBlock(scope, '旧积分');
      if (m > 0) info.oldCredits = m;
    }
    if (info.coins === 0) {
      const m = this.grabInBlock(scope, '金币');
      if (m > 0) info.coins = m;
    }
  }

  /** 在 scope 中找到包含 label 的标签块（li/dd/p/div），返回块内首个数字。 */
  private grabInBlock(scope: string, label: string): number {
    const safe = label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const reBlock = new RegExp('<(?:li|dd|p|div)[^>]*>[\\s\\S]*?' + safe + '[\\s\\S]*?<\\/(?:li|dd|p|div)>', 'i');
    const reOpen = new RegExp('<(?:li|dd|p|div)[^>]*>[\\s\\S]*?' + safe, 'i');
    const block = scope.match(reBlock) || scope.match(reOpen);
    const region = block ? block[0] : scope;
    const m = region.match(/[\d,]+/);
    return m ? parseInt(m[0].replace(/,/g, '')) : 0;
  }

  // ==================== 图片上传 ====================

  /**
   * 上传图片附件（Discuz swfupload 接口）。
   * 参考 Flutter ruisi_api.uploadImage：先拿发帖页的 uploadUid/uploadHash，
   * 以 multipart/form-data 提交 Filedata，服务端返回竖线分隔串：
   *   DISCUZUPLOAD|...|0|aid|...|serverPath|...   （parts[2]==0 表示成功）
   * 最终附件地址 = BASE_URL/data/attachment/forum/serverPath
   * @param fid 板块 id（用于获取上传凭证）
   * @param imageData 图片字节
   * @param filename 文件名
   * @param mimeType 图片 MIME
   */
  async uploadImage(
    fid: number,
    imageData: Uint8Array,
    filename: string,
    mimeType: string = 'image/jpg'
  ): Promise<UploadResult> {
    // 硬超时：网络异常（如 WiFi/蜂窝切换导致在途请求挂死）时，避免界面无限转圈
    const TIMEOUT_MS = 25000;
    const timeoutResult = new Promise<UploadResult>((resolve) => {
      setTimeout(() => {
        const r = new UploadResult();
        r.message = '上传超时，请检查网络后重试';
        resolve(r);
      }, TIMEOUT_MS);
    });
    return Promise.race([this.uploadImageInner(fid, imageData, filename, mimeType), timeoutResult]);
  }

  private async uploadImageInner(
    fid: number,
    imageData: Uint8Array,
    filename: string,
    mimeType: string
  ): Promise<UploadResult> {
    const meta = await this.getNewPostPageMeta(fid);
    if (!meta.uploadUid || !meta.uploadHash) {
      const r0 = new UploadResult();
      r0.message = '无法获取上传凭证（该板块可能不支持上传图片）';
      return r0;
    }

    const url = this.baseUrl(
      `misc.php?mod=swfupload&operation=upload&type=image&inajax=yes&infloat=yes&simple=2&mobile=2`
    );
    const boundary = '----RuisiUploadBoundary' + Date.now().toString();
    // 与安卓参考实现保持一致：jpeg 用 image/jpg（非 image/jpeg），避免服务端按 mimetype 拒收
    const mime = filename.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpg';
    const encoder = new util.TextEncoder();
    const before = encoder.encode(
      `--${boundary}\r\n` +
      `Content-Disposition: form-data; name="uid"\r\n\r\n${meta.uploadUid}\r\n` +
      `--${boundary}\r\n` +
      `Content-Disposition: form-data; name="hash"\r\n\r\n${meta.uploadHash}\r\n` +
      `--${boundary}\r\n` +
      `Content-Disposition: form-data; name="Filedata"; filename="${filename}"\r\n` +
      `Content-Type: ${mime}\r\n\r\n`
    );
    const after = encoder.encode(`\r\n--${boundary}--\r\n`);

    const totalLen = before.length + imageData.length + after.length;
    const allBytes = new Uint8Array(totalLen);
    allBytes.set(before, 0);
    allBytes.set(imageData, before.length);
    allBytes.set(after, before.length + imageData.length);

    try {
      // 用 rcp 发送：原生 http 对 ≥2MB 响应体直接丢弃，导致永远读不到服务端回包
      const resp = await this.http.postRawRcp(url, allBytes, {
        'Content-Type': `multipart/form-data; boundary=${boundary}`,
        'Referer': this.baseUrl(`forum.php?mod=post&action=newthread&fid=${fid}`),
        // 帮助 Discuz 识别为 AJAX 上传，返回 DISCUZUPLOAD 小串而非整页 HTML
        'X-Requested-With': 'XMLHttpRequest',
      });
      if (resp.isOk && resp.body.length > 0) {
        // 成功标记可能嵌在整页 HTML 里（Discuz infloat 浮窗模板），用 indexOf 找，不要求开头
        const idx = resp.body.indexOf('DISCUZUPLOAD');
        if (idx >= 0) {
          const parts = resp.body.substring(idx).split('|');
          // 成功：DISCUZUPLOAD|...|0|aid|...|serverPath|...
          if (parts.length > 5 && parts[2] === '0') {
            const aid = parts[3];
            const serverPath = parts[5];
            const r = new UploadResult();
            r.success = true;
            r.aid = aid;
            r.url = RuisiConstants.BASE_URL + '/data/attachment/forum/' + serverPath;
            r.message = '上传成功';
            return r;
          }
          // parts[2] 为错误码（参考安卓 uploadImageErrors 表）
          const code = parts.length > 2 ? parts[2] : '?';
          const errMap: Record<string, string> = {
            '-1': '内部服务器错误', '1': '不支持的扩展名', '2': '附件过大(服务器限制)',
            '3': '附件过大(用户组限制)', '4': '不支持的扩展名', '5': '附件类型限制',
            '6': '今日上传额度已满', '7': '请选择图片文件', '8': '附件无法保存',
            '9': '没有合法的文件被上传', '10': '非法操作', '11': '今日附件过大',
          };
          const r2 = new UploadResult();
          r2.message = '上传失败(' + code + '): ' + (errMap[code] || '服务端拒绝');
          return r2;
        }
        const r2b = new UploadResult();
        r2b.message = '上传失败(响应无 DISCUZUPLOAD 标记)';
        return r2b;
      }
      const r3 = new UploadResult();
      r3.message = '上传失败：服务端无响应';
      return r3;
    } catch (e) {
      const r4 = new UploadResult();
      r4.message = '上传失败: ' + String(e);
      return r4;
    }
  }

  // ==================== 论坛内置表情（Discuz smiley） ====================

  /**
   * 拉取论坛内置表情列表（api/mobile/index.php?version=4&module=smiley）。
   * 返回扁平化的 Smiley[]，每个含短码 {:分类_编号:} 与图片完整地址。
   */
  async getSmilies(): Promise<Smiley[]> {
    const url = this.baseUrl('api/mobile/index.php?version=4&module=smiley');
    try {
      const resp = await this.http.get(url);
      if (!resp.isOk || resp.body.length === 0) return [];
      return RuisiApiService.parseSmilies(resp.body);
    } catch (e) {
      hilog.error(DOMAIN, TAG, `getSmilies failed: ${String(e)}`);
      return [];
    }
  }

  private static parseSmilies(body: string): Smiley[] {
    const result: Smiley[] = [];
    try {
      const json: Object = JSON.parse(body);
      const vars: Object | undefined = (json as Record<string, Object>)['Variables'];
      if (!vars) return result;
      const smilies: Array<Array<Object>> | undefined =
        (vars as Record<string, Object>)['smilies'] as Array<Array<Object>>;
      if (!smilies) return result;
      for (const group of smilies) {
        for (const item of group) {
          const obj = item as Record<string, string>;
          const image: string = obj['image'] ?? '';
          if (image.length === 0) continue;
          const codeRe: string = obj['code'] ?? '';
          const m = codeRe.match(/\{:\d+_\d+:\}/);
          const smiley = new Smiley();
          smiley.code = m ? m[0] : `{:${image}:}`;
          smiley.url = RuisiConstants.BASE_URL + '/static/image/smiley/' + image;
          smiley.category = image.indexOf('/') >= 0 ? image.substring(0, image.indexOf('/')) : 'default';
          result.push(smiley);
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `parseSmilies failed: ${String(e)}`);
    }
    return result;
  }

  // ==================== HTML 工具方法 ====================

  stripTags(html: string): string {
    return html.replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
      .replace(/&#039;/g, "'").trim();
  }

  cleanContent(html: string): string {
    let result = html;
    // 注意：不再移除 <div class="quote"> HTML 块。
    // 旧逻辑为避免"引用回复"的重复内容删掉了 quote div，但签到帖等的核心内容
    // （如"我在...完成签到,获得随机奖励...")就在 <div class="quote"><blockquote> 里，删掉会导致丢失。
    // 安卓/iOS 不删 quote 块，我们也对齐。
    // 桌面版 API 返回的是 HTML 而非 bbcode，以下 [quote] 匹配基本是死代码，保留防身。
    // 移除脚本/样式
    result = result.replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '');
    result = result.replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '');
    // Discuz bbcode 标签
    result = result.replace(/\[color=[^\]]*\]/gi, '').replace(/\[\/color\]/gi, '');
    result = result.replace(/\[size=[^\]]*\]/gi, '').replace(/\[\/size\]/gi, '');
    result = result.replace(/\[b\]/gi, '').replace(/\[\/b\]/gi, '');
    result = result.replace(/\[i\]/gi, '').replace(/\[\/i\]/gi, '');
    result = result.replace(/\[u\]/gi, '').replace(/\[\/u\]/gi, '');
    result = result.replace(/\[img=?[^\]]*\][\s\S]*?\[\/img\]/gi, '[图片]');
    result = result.replace(/\[url=[^\]]*\]([^\]]*)\[\/url\]/gi, '$1');
    // Quote 块 → [[quote]] 标记（必须在块级换行前转换，否则 </div> 已被替换为 \n）
    // 同时剥掉 quote 内部的 <a> 标签只留文字——quote 里不需要链接，纯文本即可
    result = result.replace(/<div[^>]*class="[^"]*quote[^"]*"[^>]*>\s*<blockquote>([\s\S]*?)<\/blockquote>\s*<\/div>/gi,
      (m: string, inner: string) => {
        const plain = inner.replace(/<a[^>]*>([\s\S]*?)<\/a>/gi, (_: string, txt: string) => txt);
        return `[[quote]]${plain}[[/quote]]`;
      });
    // 先把所有 <img>（表情 + 真实帖子图）转成标记，再处理链接——否则 Discuz 帖子图外层的
    // <a href="forum.php?mod=attachment..."> 会把图片"吞进链接文本"，导致图片被当成链接文字渲染而丢失。
    // 论坛内置表情 <img class="...smilie..."> → [[smile:URL]]
    result = result.replace(/<img[^>]*class="[^"]*smilie[^"]*"[^>]*src="([^"]+)"[^>]*>/gi, (m: string, src: string) => {
      const u = src.startsWith('http') ? src : (RuisiConstants.BASE_URL + '/' + src.replace(/^\//, ''));
      return `[[smile:${u}]]`;
    });
    result = result.replace(/<img[^>]*src="([^"]*smiley[^"]*)"[^>]*>/gi, (m: string, src: string) => {
      const u = src.startsWith('http') ? src : (RuisiConstants.BASE_URL + '/' + src.replace(/^\//, ''));
      return `[[smile:${u}]]`;
    });
    // 真实帖子图（data/attachment/... 或 forum.php?mod=attachment）：转成内联标记 [[img:URL]]，保留正文原始位置。
    // 过滤头像/表情/系统装饰图（avatar/smiley/static/image/none.gif），与 parseImages 同口径。
    result = result.replace(/<img[^>]*>/gi, (m: string) => {
      const srcM = m.match(/(?:^|\s)src="([^"]*)"/i);
      const fileM = m.match(/(?:^|\s)file="([^"]*)"/i);
      const zoomM = m.match(/(?:^|\s)zoomfile="([^"]*)"/i);
      let url = '';
      if (fileM && fileM[1].length > 0 && fileM[1].indexOf('none.gif') < 0) url = fileM[1];
      else if (zoomM && zoomM[1].length > 0 && zoomM[1].indexOf('none.gif') < 0) url = zoomM[1];
      else if (srcM && srcM[1].length > 0 && srcM[1].indexOf('none.gif') < 0) url = srcM[1];
      if (url.length === 0) return '';
      if (url.indexOf('avatar') >= 0 || url.indexOf('smiley') >= 0 || url.indexOf('smilies') >= 0
        || url.indexOf('static/image') >= 0 || url.indexOf('none.gif') >= 0) return '';
      if (!url.startsWith('http')) {
        url = RuisiConstants.BASE_URL + '/' + url.replace(/^\.?\//, '');
      }
      return `[[img:${url}]]`;
    });
    // 链接 <a href="..."> → [[link:URL]]text[[/link]] 标记（对齐安卓蓝色可点击）。
    // 若链接里只包了一张图/表情（Discuz 帖子图外层的 <a>），直接输出该标记、不当链接，
    // 否则图片会被吞进链接文本导致丢失。
    result = result.replace(/<a[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/gi,
      (m: string, href: string, text: string) => {
        const url = href.replace(/&amp;/g, '&');
        const t = text.trim();
        if (/^\[\[img:[^\]]+\]\]$/.test(t) || /^\[\[smile:[^\]]+\]\]$/.test(t)) {
          return t;
        }
        return `[[link:${url}]]${t}[[/link]]`;
      });
    // 表格 → 纯文本摘要（在块级换行前处理，避免 strip 标签后坍塌成不可见或大块空白）
    // 签到帖等插件会把"今日签到排行榜"以 <table> 插入一楼，App 端 Text 不渲染 HTML 表格，
    // 原先 </td></th> 无分隔、</tr> 只换行，剥完标签后要么字全粘在一起，要么只剩空行成"空白"。
    // 这里把每个表格转成可读文本：单元格用空格分隔、行用换行，最后整体包成文本块。
    result = result.replace(/<table[^>]*>([\s\S]*?)<\/table>/gi, (m: string, inner: string) => {
      const plain = inner
        .replace(/<\/td>/gi, ' ')
        .replace(/<\/th>/gi, ' ')
        .replace(/<\/tr>/gi, '\n')
        .replace(/<br\s*\/?>/gi, '\n')
        .replace(/<[^>]+>/g, '')
        .replace(/&nbsp;/g, ' ')
        .replace(/[ \t]{2,}/g, ' ')
        .replace(/\n{3,}/g, '\n\n')
        .trim();
      return plain.length > 0 ? `\n[表格]\n${plain}\n` : '';
    });
    // 块级元素换行，便于纯文本阅读（Text 不渲染 HTML）
    result = result.replace(/<\/p>/gi, '\n').replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/div>/gi, '\n').replace(/<\/tr>/gi, '\n').replace(/<\/li>/gi, '\n');
    // 清除剩余所有标签，转纯文本
    result = result.replace(/<[^>]+>/g, '');
    // HTML 实体还原
    result = result.replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'").replace(/&#039;/g, "'");
    // 去掉多余空行：块级标签换行后往往会留下连续空行，压缩成单行换行，避免正文中出现大片空白/行距过大
    result = result.replace(/\n{2,}/g, '\n');
    return result.trim();
  }
}
