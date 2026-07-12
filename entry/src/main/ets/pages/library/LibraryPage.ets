import { ToastUtil } from '../../utils/ToastUtil';
﻿import { AccentColors } from '../../utils/AccentColors';
// LibraryPage.ets — 图书馆页面
import { ThemeColors } from '../../utils/ThemeColors';
import { HttpUtil, HttpResponse } from '../../utils/HttpUtil';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { CasLoginService } from '../../services/CasLoginService';
import { LibspSessionService, LibspSession } from '../../services/LibspSessionService';
import { SegmentTab } from '../../components/SegmentTab';
import web_webview from '@ohos.web.webview';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { scanCore, scanBarcode } from '@kit.ScanKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import Want from '@ohos.app.ability.Want';

interface BookLocation {
  locationName: string;
  barCode: string;
  searchCode: string;
  campus: string;
  processType: string;  // "在架" or others
  itemId: string;
}

interface BorrowHistoryReq {
  page: number;
  rows: number;
  searchType: number;
  searchContent: string;
  sortType: number;
  startDate: string | null;
  endDate: string | null;
}

// 新系统续借请求体（与 Flutter 一致：POST /find/lendbook/reNew，body 为 { loanIds: [loanId] }）
interface LibspRenewReq {
  loanIds: number[];
}

interface EBookItem {
  itemId: string;
  packageId: string;
  packageName: string;  // 数据库名称
  collectionName: string;
  dbVender: string;     // 数据库提供商
  url: string;          // 电子书链接
  elecResourceUrl: string;
}

interface MarcField {
  key: string;
  description: string;  // 标签，如 "题名/责任者"
  fieldVal: string;     // 内容（可能含 HTML，需剥标签）
}

interface HoldingItem {
  itemId: string;
  callNo: string;       // 索书号
  barcode: string;      // 条码号
  locationName: string; // 馆藏地（如 南馆社科图书流通库）
  shelfPos: string;     // 架位（urlName，如 南馆四楼B401 19架B面5列1-3层）
  inDate: string;       // 入藏时间
  processType: string;  // 书刊状态（在架/借出）
  dueDate: string;      // 借出时的应还日期（接口有则返回，否则为空）
  circAttr: string;     // 借阅属性
  propNo: string;       // 财产号
  positionUrl: string;  // 架位图
}

interface HoldingStatus {
  status: string;   // 归一化状态：借出 / 在架 / 其它
  dueDate: string;  // 借出时的应还日期，无则空串
}

interface BookDetailCache {
  marcFields: MarcField[];
  holdings: HoldingItem[];
  totalCount: number;
  availableCount: number;
}

interface BookItem {
  bookName: string;
  author: string;
  publisher: string;
  publishYear: string;
  isbn: string;
  docNumber: string;    // 编排号码
  callNos: string;      // 索书号
  groupCode: string;    // 书籍编号
  subject: string;
  items: BookLocation[];
  eitems: EBookItem[];  // 电子书资源
  marcFields: MarcField[];   // 书目信息（getDetail.bean2List，动态字段）
  holdings: HoldingItem[];    // 馆藏副本（groupitems）
  totalCount: number;   // 馆藏总数
  availableCount: number; // 可借数
  imageUrl: string;
  imagePixelMap: image.PixelMap | null;
}

interface BorrowItem {
  title: string;
  author: string;
  publisher: string;
  publishYear: string;   // 出版年（接口有）
  isbn: string;
  barcode: string;
  propNo: string;        // 财产号（接口有）
  yearVol: string;       // 年卷期（接口有）
  loanDate: string;
  normReturnDate: string;
  lendDay: number;       // 接口不返回剩余天数，置 0 仅供内部摘要；卡片不再显示"剩余天数"徽标
  imageUrl: string;
  imagePixelMap: image.PixelMap | null;
  locationName: string;
  loanId: number;        // 续借主键（libsp loanId）
  callNo: string;            // 索书号
  phyLibName: string;        // 分馆（phyLibName / curLibName）
  renewTimes: number;        // 已续借次数
  surplusRenewTimes: number; // 剩余可续次数
  loanType: string;          // 借阅类型码
  isRequested: string;       // 是否被预约（"是"/"否"）
}

interface HistoryItem {
  title: string;
  author: string;
  publisher: string;
  publishYear: string;
  isbn: string;
  barcode: string;
  propNo: string;
  loanDate: string;
  returnDate: string;     // 实还日期
  normReturnDate: string; // 应还日期
  locationName: string;
  imageUrl: string;
  imagePixelMap: image.PixelMap | null;
  recordId: string;
}

interface SearchHistoryItem {
  w: string; // 关键词
  f: string; // 搜索字段（keyWord/title/author/isbn/barcode/callNo）
}

@Component
export struct LibraryPage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  pageInfo: NavPathStack = new NavPathStack();

  @Builder buildWhiteTitle(t: string) {
    Row() {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.close'))
          .height(22)
          .fillColor(ThemeColors.textPrimary)
          .draggable(false)
      }
      .height(40).width(40)
      .onClick(() => { this.pageInfo.pop(); })
      Text(t)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(AccentColors.textContrast)
        .layoutWeight(1)
    }
    .width('100%')
    .height(52 + this.statusBarHeight)
    .padding({ left: 12, right: 16, top: this.statusBarHeight })
  }

  @State searchWord: string = '';
  @State searchField: string = 'keyWord';
  @State searchPage: number = 0;
  @State hasMore: boolean = false;
  @State books: BookItem[] = [];
  @State borrowList: BorrowItem[] = [];
  @State historyList: HistoryItem[] = [];
  @State borrowSubTab: number = 0;   // 0=当前借阅 1=借阅历史
  @State historyLoaded: boolean = false;
  @State errorMsg: string = '';
  // findxidian(libsp) 新系统借阅历史会话（JWT 认证，由 LibspSessionService 统一托管）
  @State showLibLogin: boolean = false;
  // WebView 登录时取数目标：当前借阅(loanList) 或 借阅历史(loanHistoryList)
  private libLoginMode: string = 'history';
  private libLoginWeb: web_webview.WebviewController = new web_webview.WebviewController();
  private libLoginTimeoutId: number = -1;
  private libFetchTimer: number = -1;   // 取数轮询注入定时器（SPA 就绪前多次重试）
  @State historyShow: boolean = false;
  // 扫码借书
  @State scanBarcode: string = '';        // 扫到的条码
  @State scanMsg: string = '';            // 结果消息
  private scanMsgTimer: number = -1;
  @State scanBusy: boolean = false;       // 扫描进行中
  @State scanPending: boolean = false;    // 等待 libsp 登录完成后自动扫
  // 扫码转借
  @State transferMsg: string = '';         // 转借结果
  private transferMsgTimer: number = -1;
  @State transferBusy: boolean = false;
  @State transferPending: boolean = false;
  @State transferShowDialog: boolean = false;
  @State transferInput: string = '';

  // 显示结果提示，3 秒后自动消失
  private showScanMsg(msg: string): void {
    if (this.scanMsgTimer >= 0) { clearTimeout(this.scanMsgTimer); }
    this.scanMsg = msg;
    this.scanMsgTimer = setTimeout(() => { this.showScanMsg(''); }, 3000);
  }
  private showTransferMsg(msg: string): void {
    if (this.transferMsgTimer >= 0) { clearTimeout(this.transferMsgTimer); }
    this.transferMsg = msg;
    this.transferMsgTimer = setTimeout(() => { this.showTransferMsg(''); }, 3000);
  }

  private handleTransferScan(): void {
    this.showTransferMsg('');
    this.transferShowDialog = false;
    const s: LibspSession | null = LibspSessionService.getSession();
    if (!s) {
      this.transferPending = true;
      this.transferBusy = true;
      this.startLibLogin();
      return;
    }
    this.startScanAndTransfer(s);
  }

  private handleTransferInput(): void {
    this.showTransferMsg('');
    if (this.transferInput.trim().length === 0) {
      return;
    }
    const s: LibspSession | null = LibspSessionService.getSession();
    if (!s) {
      this.transferPending = true;
      this.transferBusy = true;
      this.startLibLogin();
      return;
    }
    this.doTransfer(s, this.transferInput.trim());
    this.transferInput = '';
    this.transferShowDialog = false;
  }

  private async startScanAndTransfer(session: LibspSession): Promise<void> {
    this.transferBusy = true;
    try {
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.ALL],
        enableMultiMode: false,
        enableAlbum: true
      };
      const result: scanBarcode.ScanResult = await scanBarcode.startScanForResult(
        getContext(this), options
      );
      await this.doTransfer(session, result.originalValue);
    } catch (_e) {
      this.showTransferMsg(''); // 用户取消
    } finally {
      this.transferBusy = false;
    }
  }

  private async doTransfer(session: LibspSession, code: string): Promise<void> {
    this.showTransferMsg('转借中…');
    try {
      const body: Record<string, string> = { 'barcode': code };
      const resp = await LibspSessionService.postJson('/find/credit/scanSubtenancy', body, session);
      const data: Record<string, Object> = JSON.parse(resp.body) as Record<string, Object>;
      if (data['success'] === true) {
        this.showTransferMsg('转借成功！');
        this.loadBorrowList();
      } else {
        this.showTransferMsg((data['message'] as string) || '转借失败');
      }
    } catch (e) {
      this.showTransferMsg('请求失败: ' + e);
    }
  }

  private handleScanClick(): void {
    this.showScanMsg('');
    const s: LibspSession | null = LibspSessionService.getSession();
    if (!s) {
      this.scanPending = true;
      this.scanBusy = true;
      this.startLibLogin();
      return;
    }
    this.startScanAndLend(s);
  }

  private async startScanAndLend(session: LibspSession): Promise<void> {
    this.scanBusy = true;
    this.scanBarcode = '';
    try {
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.ALL],
        enableMultiMode: false,
        enableAlbum: true
      };
      const result: scanBarcode.ScanResult = await scanBarcode.startScanForResult(
        getContext(this), options
      );
      this.scanBarcode = result.originalValue;
      this.showScanMsg('借阅中…');
      const body: Record<string, string> = { 'barcode': this.scanBarcode };
      const resp = await LibspSessionService.postJson('/find/lendbook/phoneLend', body, session);
      const data: Record<string, Object> = JSON.parse(resp.body) as Record<string, Object>;
      if (data['success'] === true) {
        this.showScanMsg('借阅成功！');
        this.loadBorrowList();
      } else {
        this.showScanMsg((data['message'] as string) || '借阅失败');
      }
    } catch (e) {
      if (!this.scanBarcode) {
        this.showScanMsg(''); // 用户取消扫码，不报错
      } else {
        this.showScanMsg('请求失败: ' + e);
      }
    } finally {
      this.scanBusy = false;
    }
  }
  @State historyAlpha: number = 0;
  @State historyScale: number = 0.96;
  @State currentTab: number = 0;
  @State detailTab: number = 0;  // 详情页分栏：0=基本信息 1=馆藏副本
  @State borrowSearchWord: string = '';
  @State isSearching: boolean = false;
  @State selectedBook: BookItem | null = null;
  @State bookMaskOpacity: number = 0;
  @State bookSheetOffset: number = 100;
  // 借阅详情弹窗状态（当前借阅 / 借阅历史 共用一套遮罩动画）
  @State detailBorrow: BorrowItem | null = null;
  @State detailHistory: HistoryItem | null = null;
  @State searchHistory: SearchHistoryItem[] = [];
  @State searchFocused: boolean = false;
  private searchInputController: TextInputController = new TextInputController();
  private borrowSearchInputController: TextInputController = new TextInputController();
  private bookDetailCache: Map<string, BookDetailCache> = new Map();
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;

  private http = HttpUtil.getInstance();

  aboutToAppear(): void {
    this.loadBorrowList();
    this.loadSearchHistory();
  }

  closeBookDetail(): void {
    animateTo({ duration: 200, curve: Curve.EaseIn }, () => {
      this.bookMaskOpacity = 0;
      this.bookSheetOffset = 100;
    });
    setTimeout(() => { this.selectedBook = null; }, 200);
  }

  // 借阅详情弹窗（当前借阅 / 借阅历史 共用）
  openBorrowDetail(b: BorrowItem): void {
    this.detailBorrow = b;
    this.detailHistory = null;
    animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.bookMaskOpacity = 1;
      this.bookSheetOffset = 0;
    });
  }

  openHistoryDetail(h: HistoryItem): void {
    this.detailHistory = h;
    this.detailBorrow = null;
    animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.bookMaskOpacity = 1;
      this.bookSheetOffset = 0;
    });
  }

  closeDetail(): void {
    animateTo({ duration: 200, curve: Curve.EaseIn }, () => {
      this.bookMaskOpacity = 0;
      this.bookSheetOffset = 100;
    });
    setTimeout(() => {
      this.detailBorrow = null;
      this.detailHistory = null;
    }, 200);
  }

  // 新系统（libsp）统一检索结果 → BookItem。
  // 检索接口 /find/unify/search 的 searchResult 单条字段：
  //   recordId / title / author / publisher / isbn / publishYear / callNo(可数组)
  //   physicalCount(馆藏总数) / groupPhysicalCount / onShelfCountI(在架) / canBrrowCountI(可借)
  //   chiSubjectClass(主题分类，可数组) / subjectWord
  // 馆藏明细(items)与电子书(eitems)不在此接口返回，详情页如需展示再行补接口。
  private makeBookItem(raw: Record<string, Object>): BookItem {
    const recordId: string = String(raw['recordId'] ?? '');
    const callNoRaw: Object = raw['callNo'];
    let callNos: string = '';
    if (typeof callNoRaw === 'string') {
      callNos = callNoRaw;
    } else if (Array.isArray(callNoRaw)) {
      callNos = (callNoRaw as Object[]).map((c: Object) => String(c)).join(', ');
    }
    const subjRaw: Object = raw['chiSubjectClass'];
    let subject: string = '';
    if (typeof subjRaw === 'string') {
      subject = subjRaw;
    } else if (Array.isArray(subjRaw)) {
      subject = (subjRaw as Object[]).map((c: Object) => String(c)).join(', ');
    }
    if (subject.length === 0) {
      subject = String(raw['subjectWord'] ?? '');
    }
    const total: number = Number(raw['groupPhysicalCount'] ?? raw['physicalCount'] ?? 0);
    const avail: number = Number(raw['canBrrowCountI'] ?? raw['onShelfCountI'] ?? 0);
    return {
      bookName: String(raw['title'] ?? ''),
      author: String(raw['author'] ?? ''),
      publisher: String(raw['publisher'] ?? ''),
      publishYear: String(raw['publishYear'] ?? ''),
      isbn: String(raw['isbn'] ?? ''),
      docNumber: recordId,
      callNos: callNos,
      groupCode: recordId,
      subject: subject,
      items: [],
      eitems: [],
      marcFields: [],
      holdings: [],
      totalCount: total,
      availableCount: avail,
      imageUrl: '',
      imagePixelMap: null
    };
  }

  // 剥除 HTML 标签与常见实体，仅保留纯文本（fieldVal 中可能含 <a> 链接）
  private stripHtml(s: string): string {
    let out: string = '';
    let inside: boolean = false;
    for (let i: number = 0; i < s.length; i++) {
      const c: string = s[i];
      if (c === '<') { inside = true; continue; }
      if (c === '>') { inside = false; continue; }
      if (!inside) { out += c; }
    }
    out = out.split('&amp;').join('&').split('&nbsp;').join(' ').split('&lt;').join('<')
      .split('&gt;').join('>').split('&quot;').join('"').split('&#39;').join("'");
    return out;
  }

  // 用搜索结果已有字段构造"简版"基本信息，点书瞬间先秒出骨架，待 getDetail 回来再补全
  private buildBookSkeleton(book: BookItem): MarcField[] {
    const fields: MarcField[] = [];
    if (book.bookName.length > 0) {
      fields.push({ key: 'cnb01', description: '题名/责任者', fieldVal: book.bookName + (book.author.length > 0 ? ' / ' + book.author : '') });
    }
    if (book.publisher.length > 0 || book.publishYear.length > 0) {
      const parts: string[] = [];
      if (book.publisher.length > 0) { parts.push(book.publisher); }
      if (book.publishYear.length > 0) { parts.push(book.publishYear); }
      fields.push({ key: 'cnb03', description: '出版发行项', fieldVal: parts.join(', ') });
    }
    if (book.isbn.length > 0) {
      fields.push({ key: 'cnb04', description: 'ISBN及定价', fieldVal: book.isbn });
    }
    if (book.callNos.length > 0) {
      fields.push({ key: 'cnb05', description: '索书号', fieldVal: book.callNos });
    }
    if (book.subject.length > 0) {
      fields.push({ key: 'cnb67', description: '中图法分类号', fieldVal: book.subject });
    }
    return fields;
  }

  // 点书后加载书目详情（getDetail）与馆藏副本（groupitems），回填 selectedBook 触发刷新。
  // 优化：两接口并行请求（顺序 await 会叠加耗时≈1s，并行后≈单接口耗时）；
  //       命中本地缓存则同步秒出；竞态守卫避免快速切书错填。
  private async loadBookDetail(recordId: string): Promise<void> {
    const rid: number = parseInt(recordId) || 0;
    if (rid <= 0) return;
    const ridKey: string = String(rid);

    // 1) 缓存命中 → 同步回填，秒出
    const cached: BookDetailCache | undefined = this.bookDetailCache.get(ridKey);
    if (cached !== undefined && this.selectedBook !== null && this.selectedBook.docNumber === recordId) {
      const upd: BookItem = this.cloneBookItem(this.selectedBook);
      upd.marcFields = cached.marcFields;
      upd.holdings = cached.holdings;
      upd.totalCount = cached.totalCount;
      upd.availableCount = cached.availableCount;
      this.selectedBook = upd;
      return;
    }

    // 1.5) 缓存未命中：用搜索结果已有字段构造简版基本信息，立即秒出骨架（网络回来再补全）
    if (this.selectedBook !== null && this.selectedBook.docNumber === recordId) {
      const sk: BookItem = this.cloneBookItem(this.selectedBook);
      sk.marcFields = this.buildBookSkeleton(sk);
      this.selectedBook = sk;
    }

    const libHeaders: Record<string, string> = { 'Referer': 'https://findxidian.libsp.cn/', 'groupCode': '200755' };
    try {
      // 2) 两接口并行请求
      const dPromise: Promise<HttpResponse> = this.http.get(
        'https://findxidian.libsp.cn/find/searchResultDetail/getDetail?recordId=' + rid,
        libHeaders, true
      );
      const gPromise: Promise<HttpResponse> = this.http.postRaw(
        'https://findxidian.libsp.cn/find/physical/groupitems',
        '{"recordId":' + rid + ',"page":1,"rows":50}',
        'application/json',
        libHeaders, true
      );
      const responses: HttpResponse[] = await Promise.all([dPromise, gPromise]);
      const dResp: HttpResponse = responses[0];
      const gResp: HttpResponse = responses[1];

      let marcFields: MarcField[] = [];
      if (dResp.statusCode === 200) {
        try {
          const raw: Record<string, Object> = dResp.json<Record<string, Object>>();
          const data: Record<string, Object> = (raw['data'] as Record<string, Object>) || {};
          const bean2List: Object[] = (data['bean2List'] as Object[]) || [];
          for (let i: number = 0; i < bean2List.length; i++) {
            const item: Record<string, Object> = bean2List[i] as Record<string, Object>;
            const desc: string = String(item['description'] ?? '');
            const val: string = this.stripHtml(String(item['fieldVal'] ?? ''));
            if (val.trim().length > 0) {
              marcFields.push({ key: String(item['key'] ?? ''), description: desc, fieldVal: val });
            }
          }
        } catch (e) { /* 书目信息解析失败不影响馆藏 */ }
      }

      let holdings: HoldingItem[] = [];
      if (gResp.statusCode === 200) {
        try {
          const raw: Record<string, Object> = gResp.json<Record<string, Object>>();
          // 兼容两种返回格式：① data 直接是数组；② data 是 {totalCount,list:[...]} 字典
          const dataObj: Object = raw['data'] as Object;
          let list: Object[] = [];
          if (Array.isArray(dataObj)) {
            list = dataObj as Object[];
          } else {
            const dMap: Record<string, Object> = dataObj as Record<string, Object>;
            list = (dMap['list'] as Object[]) || [];
          }
          // [诊断] 把馆藏副本关键字段打出来，确认“借出-应还日期”已被正确拆分
          hilog.info(0xFF00, 'LibDiag', 'recordId=%{public}s holdings=%{public}d',
            recordId, list.length);
          for (let i: number = 0; i < list.length; i++) {
            const h: Record<string, Object> = list[i] as Record<string, Object>;
            const parsed = this.parseHoldingStatus(String(h['processType'] ?? ''));
            hilog.info(0xFF00, 'LibDiag', 'HOLD[%{public}d/%{public}d] status=%{public}s due=%{public}s shelf=%{public}s',
              i, list.length, parsed.status, parsed.dueDate, String(h['urlName'] ?? ''));
            holdings.push({
              itemId: String(h['itemId'] ?? ''),
              callNo: String(h['callNo'] ?? ''),
              barcode: String(h['barcode'] ?? ''),
              locationName: String(h['locationName'] ?? ''),
              shelfPos: String(h['urlName'] ?? ''),
              inDate: String(h['inDate'] ?? ''),
              processType: parsed.status,
              dueDate: parsed.dueDate,
              circAttr: String(h['circAttr'] ?? ''),
              propNo: String(h['propNo'] ?? ''),
              positionUrl: String(h['positionUrl'] ?? '')
            });
          }
        } catch (e) { /* 馆藏解析失败不影响书目 */ }
      }

      // 3) 回填（竞态守卫：仅当仍停在当前这本书才写回）
      if (this.selectedBook !== null && this.selectedBook.docNumber === recordId) {
        const updated: BookItem = this.cloneBookItem(this.selectedBook);
        if (marcFields.length > 0) {
          updated.marcFields = marcFields;   // 否则保留点书瞬间已显示的简版骨架
        }
        if (holdings.length > 0) {
          updated.holdings = holdings;
          updated.totalCount = holdings.length;
          let avail: number = 0;
          for (let i: number = 0; i < holdings.length; i++) {
            if (holdings[i].processType === '在架') { avail++; }
          }
          updated.availableCount = avail;
        }
        this.selectedBook = updated;
        // 仅完整数据写缓存（避免缓存残缺）
        if (marcFields.length > 0 && holdings.length > 0) {
          this.bookDetailCache.set(ridKey, {
            marcFields: updated.marcFields,
            holdings: updated.holdings,
            totalCount: updated.totalCount,
            availableCount: updated.availableCount
          });
        }
      }
    } catch (e) {
      // 整体失败静默
    }
  }

  private makeBorrowItem(raw: Record<string, string>): BorrowItem {
    // 注意：西电 loanList 接口不返回 lendDay/剩余天数（原网站是前端用应还日期−今天算的）。
    // 按用户要求不自行计算，lendDay 置 0（仅供内部摘要，卡片不显示该徽标）。
    return {
      title: raw['title'] || '',
      author: raw['author'] || '',
      publisher: raw['publisher'] || '',
      publishYear: raw['publishYear'] || '',
      isbn: raw['isbn'] || raw['isbn13'] || raw['isbn10'] || '',
      barcode: raw['barcode'] || '',
      propNo: raw['propNo'] || '',
      yearVol: raw['yearVol'] || '',
      loanDate: raw['loanDate'] || '',
      normReturnDate: raw['normReturnDate'] || '',
      lendDay: this.computeLendDay(raw['normReturnDate'] || ''),
      imageUrl: raw['imageUrl'] || '',
      imagePixelMap: null,
      locationName: raw['locationName'] || '',
      loanId: parseInt(raw['loanId'] || '0'),
      callNo: raw['callNo'] || '',
      phyLibName: raw['phyLibName'] || raw['curLibName'] || '',
      renewTimes: parseInt(raw['renewTimes'] || '0'),
      surplusRenewTimes: parseInt(raw['surplusRenewTimes'] || '0'),
      loanType: raw['loanType'] || '',
      isRequested: raw['isRequested'] || ''
    };
  }

  private makeHistoryItem(raw: Record<string, string>): HistoryItem {
    return {
      title: raw['title'] || '',
      author: raw['author'] || '',
      publisher: raw['publisher'] || '',
      publishYear: raw['publishYear'] || '',
      isbn: raw['isbn'] || '',
      barcode: raw['barcode'] || '',
      propNo: raw['propNo'] || '',
      loanDate: raw['loanDate'] || '',
      returnDate: raw['returnDate'] || '',
      normReturnDate: raw['normReturnDate'] || '',
      locationName: raw['locationName'] || '',
      imageUrl: '',
      imagePixelMap: null,
      recordId: raw['recordId'] !== undefined && raw['recordId'] !== null ? String(raw['recordId']) : ''
    };
  }

  // 生成式"封面"：网页的封面本就是基于书名自绘的占位图（非真实书封）。
  // 这里用书名哈希出确定性双色渐变 + 书名文字，做到"每本书都有稳定、风格统一的封面"，零网络依赖。
  private coverColors(title: string): [string, string] {
    const hue: number = this.hashHue(title.length > 0 ? title : 'book');
    return [this.hslToHex(hue, 52, 48), this.hslToHex((hue + 26) % 360, 46, 33)];
  }

  private hashHue(s: string): number {
    let h: number = 0;
    for (let i = 0; i < s.length; i++) {
      h = (h * 31 + s.charCodeAt(i)) >>> 0;
    }
    return h % 360;
  }

  private hslToHex(h: number, s: number, l: number): string {
    const sn: number = s / 100;
    const ln: number = l / 100;
    const c: number = (1 - Math.abs(2 * ln - 1)) * sn;
    const x: number = c * (1 - Math.abs(((h / 60) % 2) - 1));
    const m: number = ln - c / 2;
    let r: number = 0;
    let g: number = 0;
    let b: number = 0;
    if (h < 60) { r = c; g = x; }
    else if (h < 120) { r = x; g = c; }
    else if (h < 180) { g = c; b = x; }
    else if (h < 240) { g = x; b = c; }
    else if (h < 300) { r = x; b = c; }
    else { r = c; b = x; }
    const toHex = (v: number): string => {
      const n: number = Math.round((v + m) * 255);
      return n.toString(16).padStart(2, '0');
    };
    return '#' + toHex(r) + toHex(g) + toHex(b);
  }

  @Builder
  private historyCard(h: HistoryItem) {
    Column() {
      Row() {
        // 左：封面占位（基于书名自绘渐变，与网页风格一致）
        if (h.imagePixelMap) {
          Image(h.imagePixelMap).width(64).height(90).objectFit(ImageFit.Cover)
            .borderRadius(6)
            .border({ width: 0.5, color: this.themeIsDark ? '#3A3A3A' : '#DDDDDD' })
        } else {
          Column() {
            Text(h.title).fontSize(9).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
              .maxLines(3).textAlign(TextAlign.Center)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%').padding({ left: 4, right: 4 })
          }.width(64).height(90).borderRadius(6)
          .linearGradient({ angle: 135, colors: [[this.coverColors(h.title)[0], 0], [this.coverColors(h.title)[1], 1]] })
          .border({ width: 0.5, color: this.themeIsDark ? '#3A3A3A' : '#DDDDDD' })
        }
        // 右：紧凑信息
        Column() {
          Text(h.title).fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor(ThemeColors.textPrimary)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (h.author.length > 0) {
            Text(h.author).fontSize(12).fontColor('#888888')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 3 })
          }
          // 借书日期 / 应还日期 / 实际还书日期
          Row({ space: 10 }) {
            Column() {
              Text('借书日期').fontSize(10).fontColor('#999999')
              Text(this.fmtDateShort(h.loanDate)).fontSize(12)
                .fontColor(ThemeColors.textPrimary).margin({ top: 2 })
            }.alignItems(HorizontalAlign.Start)
            Column() {
              Text('应还日期').fontSize(10).fontColor('#999999')
              Text(this.fmtDateShort(h.normReturnDate)).fontSize(12)
                .fontColor('#E65100').margin({ top: 2 })
            }.alignItems(HorizontalAlign.Start)
            Column() {
              Text('实际还书').fontSize(10).fontColor('#999999')
              Text(this.fmtDateShort(h.returnDate)).fontSize(12)
                .fontColor('#2E7D32').margin({ top: 2 })
            }.alignItems(HorizontalAlign.Start)
          }.width('100%').margin({ top: 8 })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start).margin({ left: 12 })
        // 详细按钮（右侧竖排）
        Button('详细', { type: ButtonType.Capsule })
          .fontSize(13).height(32)
          .backgroundColor(this.themeIsDark ? '#333333' : '#EEEEEE')
          .fontColor(ThemeColors.textPrimary)
          .onClick(() => { this.openHistoryDetail(h); })
      }.width('100%')
    }.width('100%').padding(14)
    .backgroundColor(ThemeColors.bgCard).borderRadius(12)
    .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
  }

  private buildFormBody(...pairs: string[]): string {
    const parts: string[] = [];
    for (let i = 0; i < pairs.length; i += 2) {
      parts.push(encodeURIComponent(pairs[i]) + '=' + encodeURIComponent(pairs[i + 1] || ''));
    }
    return parts.join('&');
  }

  // 续借：新系统 /find/lendbook/reNew，body 为 { loanIds: [loanId] }（与 Flutter 一致）。
  // 需 libsp JWT 会话；若无则提示先刷新当前借阅（刷新即走 WebView 登录取数）。
  private async renewBook(borrow: BorrowItem): Promise<void> {
    const session: LibspSession | null = LibspSessionService.getSession();
    if (!session) {
      this.errorMsg = '请先下拉刷新当前借阅';
      setTimeout(() => { if (this.errorMsg === '请先下拉刷新当前借阅') this.errorMsg = ''; }, 3000);
      return;
    }
    try {
      const body: LibspRenewReq = { loanIds: [borrow.loanId] };
      const resp: HttpResponse = await LibspSessionService.postJson(
        '/find/lendbook/reNew',
        body,
        session
      );
      if (resp.statusCode === 200) {
        const raw: Record<string, Object> = resp.json<Record<string, Object>>();
        console.info('[HiXD-LibRenew] resp=' + JSON.stringify(raw));
        const data: Record<string, Object> = (raw['data'] as Record<string, Object>) || {};
        const msg: string = this.extractRenewMsg(raw, data);
        // 先刷新列表（应还日期/续借次数会变），再展示续借结果
        await this.loadBorrowList();
        this.errorMsg = msg;
      } else {
        this.errorMsg = '续借失败 (HTTP ' + resp.statusCode + ')';
      }
    } catch (e) {
      this.errorMsg = '续借请求失败';
    }
    setTimeout(() => { this.errorMsg = ''; }, 3000);
  }

  // 从续借响应中提取可读提示：兼容 result/msg 为字符串或对象两种情况（避免显示 [object Object]）
  private extractRenewMsg(raw: Record<string, Object>, data: Record<string, Object>): string {
    const candidates: Object[] = [data['result'], raw['msg'], raw['message'], data['msg'], data['message']];
    for (const c of candidates) {
      if (c === undefined || c === null) {
        continue;
      }
      if (typeof c === 'string') {
        return c as string;
      }
      if (typeof c === 'object') {
        const o: Record<string, Object> = c as Record<string, Object>;
        const m: Object = o['msg'] ?? o['message'] ?? o['resultMsg'] ?? o['info'];
        if (typeof m === 'string') {
          return m as string;
        }
        try {
          return JSON.stringify(c);
        } catch (e) {
          return '续借已提交';
        }
      }
      return String(c);
    }
    return '续借已提交';
  }

  private fmtDateShort(raw: string): string {
    // "2024-09-03" / "2024/9/3" → "2024-09-03"（保留年份）
    const m: RegExpMatchArray | null = raw.match(/^(\d{4})[\/-](\d{1,2})[\/-](\d{1,2})/);
    if (m) {
      const mm: string = m[2].length === 1 ? '0' + m[2] : m[2];
      const dd: string = m[3].length === 1 ? '0' + m[3] : m[3];
      return m[1] + '-' + mm + '-' + dd;
    }
    return raw.substring(0, 10);
  }

  // 馆藏副本中「借出」副本的应还日期：接口字段名不确定，逐个候选取第一个非空值。
  // 馆藏副本的 status 来自接口 processType。借出的副本接口把应还日期直接拼进字符串：
  //   在架 → "在架"；借出 → "借出-应还日期:2026-09-10"
  // 拆成干净的「状态」(借出/在架/其它) 与「应还日期」两部分，供 UI 分两行渲染。
  private parseHoldingStatus(raw: string): HoldingStatus {
    if (raw === undefined || raw === null || raw.length === 0) {
      return { status: '', dueDate: '' };
    }
    if (raw.startsWith('借出')) {
      const m: RegExpMatchArray | null = raw.match(/应还日期[:：]\s*(\S+)/);
      return { status: '借出', dueDate: m ? m[1] : '' };
    }
    return { status: raw, dueDate: '' };
  }

  // 今天（YYYY-MM-DD）
  private todayKey(): string {
    const d: Date = new Date();
    const m: string = (d.getMonth() + 1).toString().padStart(2, '0');
    const day: string = d.getDate().toString().padStart(2, '0');
    return d.getFullYear() + '-' + m + '-' + day;
  }

  // 计算剩余天数：应还日期 − 今天（<0 逾期，=0 今日到期，>0 剩余天数）。
  // 西电 loanList 接口不返回剩余天数，需前端自行按应还日期算（与原网站一致）。
  private computeLendDay(normReturnDate: string): number {
    const today: string = this.todayKey();
    const mt: RegExpMatchArray | null = today.match(/^(\d{4})-(\d{2})-(\d{2})/);
    const mr: RegExpMatchArray | null = normReturnDate.match(/^(\d{4})[\/-](\d{1,2})[\/-](\d{1,2})/);
    if (!mt || !mr) {
      return 0;
    }
    const t: number = new Date(Number(mt[1]), Number(mt[2]) - 1, Number(mt[3])).getTime();
    const r: number = new Date(Number(mr[1]), Number(mr[2]) - 1, Number(mr[3])).getTime();
    return Math.round((r - t) / 86400000);
  }

  private fmtLendDay(day: number): string {
    if (day < 0) {
      return '已逾期 ' + Math.abs(day) + ' 天';
    }
    if (day === 0) {
      return '今日到期';
    }
    return '剩余 ' + day + ' 天';
  }

  private lendDayColor(day: number): string {
    if (day < 0) {
      return '#E53935';
    }
    if (day <= 3) {
      return '#FF9800';
    }
    return '#4CAF50';
  }

  // 借阅类型码 → 可读标签（未知码回退原值）
  private fmtLoanType(t: string): string {
    if (t === '0') return '普通外借';
    if (t === '1') return '短期外借';
    if (t === '2') return '馆际互借';
    return t;
  }

  // 拉起 findxidian WebView（CAS SSO 种子）→ 页面加载完成后由 onPageEnd 注入 fetch，
  // 取数结果经 console.log('LIBHIST:...') 由 .onConsole 捕获，解析后关闭浮层。
  // 参考 MainPage xgxt 范式：WebView 内 fetch 同源、cookie 自动带（withCredentials）。
  private async startLibLogin(): Promise<void> {
    try {
      await CasLoginService.getInstance().syncCasCookieOnly();
    } catch (e) {
      // SSO 种子失败不致命，WebView 内可手动登录
    }
    this.showLibLogin = true;
    this.historyLoaded = false;
    this.errorMsg = '';
    this.clearLibLoginTimeout();
    // 超时兜底：CAS 网关/网络异常时避免无限停在网上
    this.libLoginTimeoutId = setTimeout(() => {
      if (this.showLibLogin) {
        this.stopLibFetchLoop();
        this.showLibLogin = false;
        this.errorMsg = '图书馆借阅信息获取超时，请点“重新登录”重试';
        this.historyLoaded = true;
      }
    }, 40000) as number;
  }

  private clearLibLoginTimeout(): void {
    if (this.libLoginTimeoutId >= 0) {
      clearTimeout(this.libLoginTimeoutId);
      this.libLoginTimeoutId = -1;
    }
  }

  // 关闭登录浮层（✕ 按钮 / 返回键复用）
  private stopLibLoginPoll(): void {
    this.clearLibLoginTimeout();
    this.stopLibFetchLoop();
    this.showLibLogin = false;
  }

  // 启动取数轮询：SPA 需时间初始化并把 JWT 写入 sessionStorage/cookie，
  // 故每 1.5s 注入一次 fetch，直到 JWT 就绪并取数成功（或超时/手动关闭）。
  private startLibFetchLoop(): void {
    this.stopLibFetchLoop();
    this.libFetchTimer = setInterval(() => {
      this.injectLibFetch();
    }, 1500) as number;
  }

  private stopLibFetchLoop(): void {
    if (this.libFetchTimer >= 0) {
      clearInterval(this.libFetchTimer);
      this.libFetchTimer = -1;
    }
  }

  // WebView 内注入 fetch 取借阅历史（同源 + cookie 自动带，复刻 SPA 请求头）。
  // 脚本由 LibspSessionService.buildInjectJs 生成：先回传 LIBSESSION 供持久化，
  // 再 fetch 借阅历史，结果经 console.log('LIBHIST:<json>') 由 .onConsole 捕获。
  // WebView 内注入 fetch 取数：按 libLoginMode 选择当前借阅(loanList) 或 借阅历史(loanHistoryList)。
  // 脚本由 LibspSessionService.buildInjectJs 生成：先回传 LIBSESSION 供持久化，再 fetch 目标接口，
  // 结果经 console.log('<MARKER>:<json>') 由 .onConsole 捕获（MARKER: LIBBORROW / LIBHIST）。
  private injectLibFetch(): void {
    const body: BorrowHistoryReq = { page: 1, rows: this.libLoginMode === 'borrow' ? 999 : 50, searchType: 1, searchContent: this.borrowSearchWord, sortType: 0, startDate: null, endDate: null };
    let js: string;
    if (this.libLoginMode === 'borrow') {
      js = LibspSessionService.buildInjectJs('/find/loanInfo/loanList', body, 'LIBBORROW');
    } else {
      js = LibspSessionService.buildInjectJs('/find/loanInfo/loanHistoryList', body, 'LIBHIST');
    }
    try {
      this.libLoginWeb.runJavaScript(js);
    } catch (e) {
      // WebView 仍在跳转途中，忽略；onPageEnd 会再次触发
    }
  }

  // .onConsole 捕获到取数成功
  private onLibHistReceived(jsonStr: string): void {
    this.clearLibLoginTimeout();
    this.stopLibFetchLoop();
    this.parseAndShowHistory(jsonStr);
    this.showLibLogin = false;
    // 列表先以生成式占位图渲染，随后后台批量拉取真实封面（公开接口，不阻塞）
    this.fetchHistoryCovers(this.historyList);
  }

  // 解析并展示借阅历史 JSON（DATA: 之后的原始响应体）
  private parseAndShowHistory(jsonStr: string): void {
    try {
      const raw: Record<string, object> = JSON.parse(jsonStr);
      const data: Record<string, object> = (raw['data'] as Record<string, object>) || {};
      const rawList: Record<string, string>[] = (data['searchResult'] as Record<string, string>[]) || [];
      const result: HistoryItem[] = [];
      for (let i = 0; i < rawList.length; i++) {
        result.push(this.makeHistoryItem(rawList[i]));
      }
      this.historyList = result;
      this.historyLoaded = true;
      this.errorMsg = '';
    } catch (e) {
      this.errorMsg = '借阅历史解析失败，请下拉重试';
      this.historyLoaded = true;
    }
  }

  // .onConsole 捕获到当前借阅取数成功
  private onLibBorrowReceived(jsonStr: string): void {
    this.clearLibLoginTimeout();
    this.stopLibFetchLoop();
    this.parseAndShowBorrow(jsonStr);
    this.showLibLogin = false;
    this.fetchBorrowCovers(this.borrowList);
  }

  // 解析并展示当前借阅 JSON（DATA: 之后的原始响应体），结构同借阅历史：data.searchResult
  private parseAndShowBorrow(jsonStr: string): void {
    try {
      const raw: Record<string, object> = JSON.parse(jsonStr);
      const data: Record<string, object> = (raw['data'] as Record<string, object>) || {};
      const rawList: Record<string, string>[] = (data['searchResult'] as Record<string, string>[]) || [];
      // [诊断] 打印首条原始字段，确认 loanList 真实返回哪些 key/value（重点看 lendDay / renewTimes / loanType / itemLibName / loanDeskName 等是否存在）
      if (rawList.length > 0) {
        console.info('[HiXD-LibDiag] loanList[0] keys=' + JSON.stringify(Object.keys(rawList[0])));
        console.info('[HiXD-LibDiag] loanList[0] raw=' + JSON.stringify(rawList[0]));
      }
      const result: BorrowItem[] = [];
      for (let i = 0; i < rawList.length; i++) {
        result.push(this.makeBorrowItem(rawList[i]));
      }
      this.borrowList = result;
      // 保存借阅概况给主页卡片用（逾期 = 应还日期已过今天；接口无剩余天数字段，故按应还日期判断）
      let overdue = 0;
      const todayStr: string = this.todayKey();
      for (const b of result) {
        const nr: string = this.fmtDateShort(b.normReturnDate);
        if (nr.length >= 10 && nr < todayStr) overdue++;
      }
      PreferenceUtil.putString('lib_summary', result.length + '|' + overdue);
      this.errorMsg = '';
    } catch (e) {
      this.errorMsg = '当前借阅解析失败，请下拉重试';
    }
  }

  // libsp WebView 登录浮层（当前借阅 / 借阅历史 / 扫码 共用）：背后静默完成 CAS SSO + 取数，
  // 被不透明加载覆盖层完全遮住，不显示给用户。取数结果经 onConsole 回传 LIBHIST / LIBBORROW。
  @Builder
  libLoginOverlay() {
    Stack() {
      Web({ src: 'https://findxidian.libsp.cn/#/personalCenter', controller: this.libLoginWeb })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .onPageEnd((event) => {
          // SPA 需时间初始化并把 JWT 写入 sessionStorage/cookie，故轮询注入直到就绪
          if (event && event.url && event.url.indexOf('findxidian.libsp.cn') >= 0) {
            this.startLibFetchLoop();
          }
        })
        .onConsole((event): boolean => {
          if (event && event.message) {
            const msg: string = event.message.getMessage();
            const parsed = LibspSessionService.parseConsole(msg);
            if (parsed.kind === 'session' && parsed.payload) {
              try {
                const s: LibspSession = JSON.parse(parsed.payload) as LibspSession;
                if (s.jwt && s.jwtHeader) {
                  LibspSessionService.saveSession(s);
                  if (this.scanPending) {
                    this.scanPending = false;
                    this.stopLibLoginPoll();
                    this.startScanAndLend(s);
                  }
                  if (this.transferPending) {
                    this.transferPending = false;
                    this.stopLibLoginPoll();
                    this.startScanAndTransfer(s);
                  }
                }
              } catch (_e) { /* ignore */ }
              return true;
            }
            if (msg.indexOf('LIBHIST:') === 0) {
              this.onLibHistReceived(msg.substring(8));
              return true;
            }
            if (msg.indexOf('LIBBORROW:') === 0) {
              this.onLibBorrowReceived(msg.substring(11));
              return true;
            }
            if (msg.indexOf('LIBERR:') === 0) {
              this.stopLibFetchLoop();
              this.errorMsg = '借阅信息获取失败，请点“重新登录”重试';
              this.historyLoaded = true;
              this.showLibLogin = false;
              this.clearLibLoginTimeout();
              return true;
            }
          }
          return false;
        })
        .width('100%').height('100%')
      // 鸿蒙加载动画覆盖层（不透明，仅在内容区，完全遮住 WebView，不影响上方头部）
      Column() {
        LoadingProgress().width(48).height(48).color(this.accentColor)
        Text('正在加载借阅信息...').fontSize(14)
          .fontColor(ThemeColors.textPrimary).margin({ top: 14 })
        Text('取消').fontSize(13)
          .fontColor(this.themeIsDark ? '#9E9E9E' : '#888888')
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .margin({ top: 22 })
          .onClick(() => { this.stopLibLoginPoll(); })
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor(ThemeColors.bgPage)
    }.width('100%').layoutWeight(1)
  }

  private async loadBorrowHistory(): Promise<void> {
    this.historyLoaded = false;
    try {
      const session: LibspSession | null = LibspSessionService.getSession();
      if (!session) {
        // 无缓存会话：走 WebView 登录（CAS SSO 自动登录后由注入脚本取数 + 回存会话）
        this.errorMsg = '';
        this.historyLoaded = true;
        this.libLoginMode = 'history';
        this.startLibLogin();
        return;
      }
      // 有缓存会话：直连接口（JWT 双保险），无需再弹 WebView —— 修掉"每次进页都重登"
      const req: BorrowHistoryReq = { page: 1, rows: 50, searchType: 1, searchContent: this.borrowSearchWord, sortType: 0, startDate: null, endDate: null };
      const resp = await LibspSessionService.postJson(
        '/find/loanInfo/loanHistoryList',
        req,
        session
      );
      if (resp.statusCode !== 200) {
        throw new Error('HTTP ' + resp.statusCode);
      }
      this.parseAndShowHistory(resp.body);
      this.fetchHistoryCovers(this.historyList);
    } catch (e) {
      // 会话可能失效，清除缓存并自动重新拉起 WebView 登录（避免卡在错误页）
      await LibspSessionService.clearSession();
      this.errorMsg = '';
      this.historyLoaded = true;
      this.libLoginMode = 'history';
      this.startLibLogin();
    }
  }

  private async fetchBorrowCovers(borrows: BorrowItem[]): Promise<void> {
    for (let i: number = 0; i < borrows.length; i += 5) {
      const batch: BorrowItem[] = borrows.slice(i, i + 5);
      const tasks: Promise<string>[] = batch.map((b: BorrowItem) =>
        this.fetchBookCover(b.title, b.isbn, b.barcode)
      );
      const urls: string[] = await Promise.all(tasks);
      const pmTasks: Promise<image.PixelMap | null>[] = urls.map((u: string) => this.fetchCoverPixelMap(u));
      const pms: (image.PixelMap | null)[] = await Promise.all(pmTasks);
      for (let j: number = 0; j < batch.length; j++) {
        batch[j].imageUrl = urls[j];
        batch[j].imagePixelMap = pms[j];
      }
    }
    // 新建对象数组触发 ForEach 重渲染
    const updated: BorrowItem[] = [];
    for (let k: number = 0; k < borrows.length; k++) {
      const b: BorrowItem = borrows[k];
      updated.push({
        title: b.title, author: b.author, publisher: b.publisher, publishYear: b.publishYear,
        isbn: b.isbn, barcode: b.barcode, propNo: b.propNo, yearVol: b.yearVol,
        loanDate: b.loanDate, normReturnDate: b.normReturnDate,
        lendDay: b.lendDay, imageUrl: b.imageUrl, imagePixelMap: b.imagePixelMap, locationName: b.locationName,
        loanId: b.loanId, callNo: b.callNo, phyLibName: b.phyLibName,
        renewTimes: b.renewTimes, surplusRenewTimes: b.surplusRenewTimes,
        loanType: b.loanType, isRequested: b.isRequested
      });
    }
    this.borrowList = updated;
  }

  // 借阅历史封面：复用 fetchBookCover（公开接口，不需登录态），批量获取后重建数组触发重渲染。
  // 与 fetchBorrowCovers 同构，沿用 barcode 作为 docNumber 入参（借阅列表已验证可用）。
  private async fetchHistoryCovers(history: HistoryItem[]): Promise<void> {
    if (history.length === 0) return;
    for (let i: number = 0; i < history.length; i += 5) {
      const batch: HistoryItem[] = history.slice(i, i + 5);
      const tasks: Promise<string>[] = batch.map((h: HistoryItem) =>
        // 用历史接口自带的 recordId（图书内部记录ID），而非条码；ISBN 去连字符以匹配封面源
        this.fetchBookCover(h.title, h.isbn.replace(/-/g, ''), h.recordId)
      );
      const urls: string[] = await Promise.all(tasks);
      const pmTasks: Promise<image.PixelMap | null>[] = urls.map((u: string) => this.fetchCoverPixelMap(u));
      const pms: (image.PixelMap | null)[] = await Promise.all(pmTasks);
      for (let j: number = 0; j < batch.length; j++) {
        batch[j].imageUrl = urls[j];
        batch[j].imagePixelMap = pms[j];
      }
    }
    // 重建数组触发 ForEach 重渲染
    const updated: HistoryItem[] = [];
    for (let k: number = 0; k < this.historyList.length; k++) {
      const h: HistoryItem = this.historyList[k];
      updated.push({
        title: h.title, author: h.author, publisher: h.publisher,
        publishYear: h.publishYear, isbn: h.isbn, barcode: h.barcode,
        propNo: h.propNo, loanDate: h.loanDate, returnDate: h.returnDate,
        normReturnDate: h.normReturnDate, locationName: h.locationName,
        imageUrl: h.imageUrl, imagePixelMap: h.imagePixelMap, recordId: h.recordId
      });
    }
    this.historyList = updated;
  }

  // 当前借阅：新系统 /find/loanInfo/loanList（与 Flutter 一致）。
  // 有 libsp JWT 会话则直连接口；无会话则拉起 WebView(CAS SSO) 登录，
  // 登录完成后注入脚本取数并经 LIBBORROW 回传（见 onConsole / onLibBorrowReceived）。
  async loadBorrowList(): Promise<void> {
    const session: LibspSession | null = LibspSessionService.getSession();
    if (!session) {
      this.libLoginMode = 'borrow';
      this.startLibLogin();
      return;
    }
    try {
      const req: BorrowHistoryReq = { page: 1, rows: 999, searchType: 1, searchContent: this.borrowSearchWord, sortType: 0, startDate: null, endDate: null };
      const resp = await LibspSessionService.postJson('/find/loanInfo/loanList', req, session);
      if (resp.statusCode !== 200) {
        throw new Error('HTTP ' + resp.statusCode);
      }
      this.parseAndShowBorrow(resp.body);
      this.fetchBorrowCovers(this.borrowList);
    } catch (e) {
      await LibspSessionService.clearSession();
      this.libLoginMode = 'borrow';
      this.startLibLogin();
    }
  }

  private async fetchBookCover(title: string, isbn: string, docNumber: string): Promise<string> {
    try {
      const resp: HttpResponse = await this.http.postRaw(
        'https://findxidian.libsp.cn/find/unify/getPItemAndOnShelfCountAndDuxiuImageUrl',
        JSON.stringify({ title: title, isbn: isbn, recordId: parseInt(docNumber) || 0 }),
        'application/json',
        { 'Referer': 'https://findxidian.libsp.cn/', 'groupCode': '200755' },
        true // skipCookies: 封面API不需要保存响应cookie
      );
      if (resp.statusCode === 200) {
        const raw: Record<string, Object> = resp.json<Record<string, Object>>();
        const data: Record<string, Object> = (raw['data'] as Record<string, Object>) || {};
        const url = String(data['duxiuImageUrl'] ?? '');
        console.info('[HiXD-Lib] cover result len=' + url.length + ' isbn=' + isbn + ' doc=' + docNumber + ' url=' + url);
        return url;
      }
    } catch (e) {
      // 封面获取失败不影响主流程
    }
    return '';
  }

  // 把封面 URL 下载为 PixelMap：绕过 Image 组件直连图床失败（明文 http 拦截 / 图床需 Referer 而 Image 不带）。
  // 复用 HttpUtil.getArrayBuffer 带 Referer 拉字节，再转 PixelMap 显示。
  private async fetchCoverPixelMap(url: string): Promise<image.PixelMap | null> {
    if (!url || url.length === 0) return null;
    try {
      const buf: ArrayBuffer = await HttpUtil.getInstance().getArrayBuffer(
        url,
        { 'Referer': 'https://findxidian.libsp.cn/' }
      );
      if (!buf || buf.byteLength === 0) return null;
      const src: image.ImageSource = image.createImageSource(buf);
      const pm: image.PixelMap = await src.createPixelMap();
      return pm;
    } catch (e) {
      console.error('[HiXD-Lib] cover pixelmap failed: ' + (e as Error)?.message);
      return null;
    }
  }

  private cloneBookItem(b: BookItem): BookItem {
    return {
      bookName: b.bookName, author: b.author, publisher: b.publisher,
      publishYear: b.publishYear, isbn: b.isbn, docNumber: b.docNumber,
      callNos: b.callNos, groupCode: b.groupCode, subject: b.subject,
      items: b.items, eitems: b.eitems, marcFields: b.marcFields, holdings: b.holdings,
      totalCount: b.totalCount, availableCount: b.availableCount,
      imageUrl: b.imageUrl, imagePixelMap: b.imagePixelMap
    };
  }

  private async fetchAllCovers(newBooks: BookItem[]): Promise<void> {
    for (let i: number = 0; i < newBooks.length; i += 5) {
      const batch: BookItem[] = newBooks.slice(i, i + 5);
      const tasks: Promise<string>[] = batch.map((b: BookItem) =>
        this.fetchBookCover(b.bookName, b.isbn, b.docNumber)
      );
      const urls: string[] = await Promise.all(tasks);
      const pmTasks: Promise<image.PixelMap | null>[] = urls.map((u: string) => this.fetchCoverPixelMap(u));
      const pms: (image.PixelMap | null)[] = await Promise.all(pmTasks);
      for (let j: number = 0; j < batch.length; j++) {
        batch[j].imageUrl = urls[j];
        batch[j].imagePixelMap = pms[j];
      }
    }
    // 基于当前 this.books 重建数组，触发 ForEach 重渲染（保留所有页的数据）
    const updated: BookItem[] = [];
    for (let k: number = 0; k < this.books.length; k++) {
      updated.push(this.cloneBookItem(this.books[k]));
    }
    this.books = updated;
  }

  // 馆藏资源检索：统一迁移到 libsp 新系统 /find/unify/search（公开接口，仅需 groupCode 头，无需 JWT）。
  // 请求体字段与网站 SPA 保持一致；searchField 复用原 Select 取值(keyWord/title/author/isbn/barcode/callNo)。
  async searchBooks(page?: number): Promise<void> {
    if (!this.searchWord.trim()) return;
    const p: number = page ?? 1;
    if (p === 1) { this.books = []; this.searchPage = 1; }
    this.isSearching = true;
    try {
      const rows: number = 10;
      // ArkTS 禁止未声明类型的对象字面量(arkts-no-untyped-obj-literals)，
      // 且请求体字段混有数组/null，故直接拼 JSON 字符串；关键词用 JSON.stringify 做转义。
      const kw: string = JSON.stringify(this.searchWord.trim());
      const body: string = '{'
        + '"docCode":[null],'
        + '"litCode":[],'
        + '"searchFieldContent":' + kw + ','
        + '"searchField":"' + this.searchField + '",'
        + '"matchMode":"2",'
        + '"resourceType":[],'
        + '"subject":[],'
        + '"discode1":[],'
        + '"publisher":[],'
        + '"libCode":[],'
        + '"locationId":[],'
        + '"eCollectionIds":[],'
        + '"neweCollectionIds":[],'
        + '"curLocationId":[],'
        + '"campusId":[],'
        + '"kindNo":[],'
        + '"collectionName":[],'
        + '"author":[],'
        + '"langCode":[],'
        + '"countryCode":[],'
        + '"publishBegin":null,'
        + '"publishEnd":null,'
        + '"coreInclude":[],'
        + '"ddType":[],'
        + '"verifyStatus":[],'
        + '"group":[],'
        + '"sortField":"relevance",'
        + '"sortClause":"asc",'
        + '"page":' + p + ','
        + '"rows":' + rows + ','
        + '"onlyOnShelf":null,'
        + '"searchItems":null,'
        + '"newCoreInclude":[],'
        + '"customSub":[],'
        + '"customSub0":[],'
        + '"indexSearch":1'
        + '}';
      const resp = await this.http.postRaw(
        'https://findxidian.libsp.cn/find/unify/search',
        body,
        'application/json',
        {
          'Referer': 'https://findxidian.libsp.cn/',
          'groupCode': '200755',
          'x-lang': 'CHI',
          'content-language': 'zh_CN',
          'mappingPath': ''
        }
      );
      if (resp.statusCode !== 200) {
        throw new Error('HTTP ' + resp.statusCode);
      }
      const raw: Record<string, object> = resp.json<Record<string, object>>();
      const data: Record<string, Object> = (raw['data'] as Record<string, Object>) || {};
      const rawList: Record<string, Object>[] = (data['searchResult'] as Record<string, Object>[]) || [];
      const newBooks: BookItem[] = [];
      for (let i = 0; i < rawList.length; i++) {
        newBooks.push(this.makeBookItem(rawList[i]));
      }
      if (p === 1) {
        this.books = newBooks;
      } else {
        const merged: BookItem[] = [];
        for (let j = 0; j < this.books.length; j++) { merged.push(this.books[j]); }
        for (let k = 0; k < newBooks.length; k++) { merged.push(newBooks[k]); }
        this.books = merged;
      }
      this.searchPage = p;
      this.hasMore = rawList.length >= rows;
      this.fetchAllCovers(newBooks);
      if (p === 1) { this.addSearchHistory(this.searchWord, this.searchField); }
    } catch (e) {
      if (p === 1) { this.books = []; }
      this.errorMsg = '搜索失败，请检查网络后重试';
    } finally { this.isSearching = false; }
  }

  private getSearchFieldIndex(): number {
    if (this.searchField === 'title') return 1;
    if (this.searchField === 'author') return 2;
    if (this.searchField === 'isbn') return 3;
    if (this.searchField === 'barcode') return 4;
    if (this.searchField === 'callNo') return 5;
    return 0;
  }

  private indexToField(idx: number): string {
    const fields: string[] = ['keyWord', 'title', 'author', 'isbn', 'barcode', 'callNo'];
    return idx >= 0 && idx < fields.length ? fields[idx] : 'keyWord';
  }

  private fieldLabel(): string {
    if (this.searchField === 'title') return '书名';
    if (this.searchField === 'author') return '作者';
    if (this.searchField === 'isbn') return 'ISBN';
    if (this.searchField === 'barcode') return '条码';
    if (this.searchField === 'callNo') return '索书号';
    return '关键词';
  }

  private fieldLabelOf(f: string): string {
    if (f === 'title') return '书名';
    if (f === 'author') return '作者';
    if (f === 'isbn') return 'ISBN';
    if (f === 'barcode') return '条码';
    if (f === 'callNo') return '索书号';
    return '关键词';
  }

  private readonly HISTORY_KEY: string = 'library_search_history';
  private readonly HISTORY_MAX: number = 10;

  private loadSearchHistory(): void {
    const raw: string = PreferenceUtil.getString(this.HISTORY_KEY, '[]');
    try {
      const parsed: ESObject = JSON.parse(raw);
      const out: SearchHistoryItem[] = [];
      if (Array.isArray(parsed)) {
        const arr = parsed as SearchHistoryItem[];
        for (let i = 0; i < arr.length; i++) {
          const it = arr[i];
          if (it && typeof it.w === 'string' && it.w.length > 0) {
            out.push({ w: it.w, f: typeof it.f === 'string' ? it.f : 'keyWord' });
          }
        }
      }
      this.searchHistory = out;
    } catch (e) {
      this.searchHistory = [];
    }
  }

  private saveSearchHistory(): void {
    PreferenceUtil.putString(this.HISTORY_KEY, JSON.stringify(this.searchHistory)).catch(() => {});
  }

  // 新搜索成功后记录：去重 + 置顶 + 限长
  private addSearchHistory(word: string, field: string): void {
    const w = word.trim();
    if (!w) return;
    const lower = w.toLowerCase();
    const filtered: SearchHistoryItem[] = this.searchHistory.filter((it) => it.w.toLowerCase() !== lower);
    filtered.unshift({ w: w, f: field });
    if (filtered.length > this.HISTORY_MAX) {
      filtered.splice(this.HISTORY_MAX, filtered.length - this.HISTORY_MAX);
    }
    this.searchHistory = filtered;
    this.saveSearchHistory();
  }

  private clearSearchHistory(): void {
    this.searchHistory = [];
    this.saveSearchHistory();
  }

  // 浮层动画显隐：用 animateTo 显式驱动透明度+缩放，规避 @Builder 内 transition 隐式转场不触发的问题
  private showHistory(): void {
    if (this.searchHistory.length === 0) { return; }
    this.historyAlpha = 0;
    this.historyScale = 0.96;
    this.historyShow = true;
    animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.historyAlpha = 1;
      this.historyScale = 1;
    });
  }

  private hideHistory(): void {
    if (!this.historyShow) { return; }
    // 收起键盘 + 清焦点，确保任何隐藏路径（点结果区/空白/空状态/失焦）键盘一并消失
    this.searchInputController.stopEditing();
    this.searchFocused = false;
    animateTo({ duration: 150, curve: Curve.EaseIn, onFinish: () => {
      this.historyShow = false;
    } }, () => {
      this.historyAlpha = 0;
      this.historyScale = 0.96;
    });
  }

  // 点击历史标签：回填字段+关键词并立即搜索
  private applyHistory(item: SearchHistoryItem): void {
    this.searchField = item.f;
    this.searchWord = item.w;
    this.searchInputController.stopEditing();
    this.searchFocused = false;
    this.hideHistory();
    this.searchBooks();
  }

  // 统一搜索入口：收起键盘与历史面板后执行搜索（馆藏资源 / 书库检索）
  private doSearch(): void {
    this.searchInputController.stopEditing();
    this.searchFocused = false;
    this.hideHistory();
    this.searchBooks();
  }

  // 我的借阅检索入口：按当前子标签（当前借阅 / 借阅历史）做服务端关键字检索
  private doBorrowSearch(): void {
    this.borrowSearchInputController.stopEditing();
    this.searchFocused = false;
    this.hideHistory();
    if (this.borrowSubTab === 0) {
      this.loadBorrowList();
    } else {
      this.loadBorrowHistory();
    }
  }

  // 搜索历史浮层：紧贴搜索框下方，靠 onBlur 收起（不铺全屏拦截点击）
  @Builder historyPanel() {
    Column() {
      Row() {
        Text('搜索历史').fontSize(13).fontColor(ThemeColors.textSecondary)
        Blank()
        if (this.searchHistory.length > 0) {
          Text('清空')
            .fontSize(12)
            .fontColor(this.accentColor)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .onClick(() => { this.clearSearchHistory(); })
        }
      }.width('100%').padding({ left: 16, right: 16, top: 10, bottom: 6 })

      Divider().width('100%').color(ThemeColors.border).margin({ left: 16, right: 16 })

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
        ForEach(this.searchHistory, (item: SearchHistoryItem) => {
          Text(item.w)
            .fontSize(13).fontColor(ThemeColors.textPrimary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(ThemeColors.bgInput)
            .borderRadius(14)
            .constraintSize({ maxWidth: 220 })
            .margin({ right: 8, bottom: 8 })
            .onClick(() => { this.applyHistory(item); })
        }, (item: SearchHistoryItem, idx?: number) => `hist_${idx}_${item.w}`)
      }.width('100%').padding({ left: 16, right: 16, top: 4, bottom: 10 })
    }
    .width('100%')
    .position({ x: 0, y: 100 })
    .backgroundColor(ThemeColors.bgCard)
    .borderRadius(12)
    .border({ width: 1, color: ThemeColors.border })
    .shadow({ radius: 18, color: '#0000002E', offsetY: 8 })
    .zIndex(100)
    .opacity(this.historyAlpha)
    .scale({ x: this.historyScale, y: this.historyScale })
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
      SegmentTab({
        tabs: ['馆藏资源', '我的借阅'],
        currentIndex: $currentTab,
        accentColor: this.accentColor,
        onTabChange: (idx: number) => {
          if (idx === 1) {
            if (this.borrowSubTab === 0) {
              this.loadBorrowList();
            } else {
              this.loadBorrowHistory();
            }
          }
        }
      }) {
        // ===== 馆藏资源（书库检索）=====
        Column() {
          // 书库检索框（馆藏地 + 关键词）
          Row({ space: 6 }) {
            Select([{ value: '关键词' }, { value: '书名' }, { value: '作者' },
              { value: 'ISBN' }, { value: '条码' }, { value: '索书号' }])
              .selected(this.getSearchFieldIndex())
              .value(this.fieldLabel())
              .onSelect((idx: number) => { this.searchField = this.indexToField(idx); })
              .width(100)
            TextInput({
              placeholder: '搜索图书...',
              text: this.searchWord,
              controller: this.searchInputController
            })
              .layoutWeight(1).height(40).borderRadius(20).backgroundColor(ThemeColors.bgInput).padding({ left: 16, right: 16 })
              .onChange((v: string) => { this.searchWord = v; })
              .onSubmit(() => { this.doSearch(); })
              .onFocus(() => { this.searchFocused = true; this.showHistory(); })
              .onBlur(() => { this.searchFocused = false; this.hideHistory(); })
            Button('搜索').height(40).borderRadius(20).backgroundColor('#8E24AA').fontColor('#FFFFFF')
              .onClick(() => { this.doSearch(); })
          }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 })

        if (this.isSearching && this.books.length === 0) {
          // 首次搜索：全屏加载
          Column() {
            LoadingProgress().width(40).height(40).color(this.accentColor)
            Text('搜索中...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.hideHistory();
          })
        } else if (this.books.length > 0) {
          // 有数据：显示列表（翻页时列表保留，底部追加 loading）
          List({ space: 4 }) {
            ForEach(this.books, (book: BookItem, idx?: number) => {
              ListItem() {
                Row() {
                  if (book.imagePixelMap) {
                    Image(book.imagePixelMap).width(48).height(68)
                      .objectFit(ImageFit.Cover).borderRadius(4)
                  } else if (book.imageUrl && book.imageUrl.length > 0) {
                    Image(book.imageUrl).width(48).height(68)
                      .objectFit(ImageFit.Cover).borderRadius(4)
                  } else {
                    Column() {
                      Text('📖').fontSize(20)
                    }.width(48).height(68).borderRadius(4)
                    .backgroundColor(this.themeIsDark ? '#252525' : '#F5F5F5')
                    .justifyContent(FlexAlign.Center)
                    .border({ width: 0.5, color: this.themeIsDark ? '#3A3A3A' : '#DDDDDD' })
                  }
                  Column() {
                    Text(book.bookName).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(book.author).fontSize(12).fontColor('#888888').margin({ top: 3 })
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Row() {
                      Text(book.publisher).fontSize(11).fontColor('#AAAAAA')
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                      Text(`可借 ${book.availableCount}`).fontSize(11)
                        .fontColor(book.availableCount > 0 ? '#4CAF50' : '#E53935')
                      Text(`  馆藏 ${book.totalCount}`).fontSize(11).fontColor('#AAAAAA')
                    }.width('100%').margin({ top: 4 })
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start).margin({ left: 12 })
                }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .borderRadius(12).backgroundColor(ThemeColors.bgCard)
                .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
                .margin({ left: 14, right: 14, bottom: 8 })
                .onClick(() => {
                  // 点书先强制收起搜索框键盘与历史浮层（书籍项不可获焦，不会触发 onBlur）
                  this.searchInputController.stopEditing();
                  this.searchFocused = false;
                  this.hideHistory();
                  this.selectedBook = book;
                  this.detailTab = 0;  // 每本新书默认停在基本信息
                  this.loadBookDetail(book.docNumber);
                  animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
                    this.bookMaskOpacity = 1;
                    this.bookSheetOffset = 0;
                  });
                })
              }.padding({ left: 12, right: 12 })
            }, (book: BookItem, idx?: number) => `book_${idx}_${book.imageUrl.length > 0 ? '1' : '0'}`)

            if (this.isSearching) {
              ListItem() {
                Row() {
                  LoadingProgress().width(20).height(20).color(this.accentColor)
                  Text('加载中...').fontSize(13).fontColor(ThemeColors.textSecondary).margin({ left: 8 })
                }.width('100%').height(48).justifyContent(FlexAlign.Center)
              }.padding({ left: 12, right: 12 })
            } else if (!this.hasMore && this.searchPage > 0) {
              ListItem() {
                Text('— 已经到底了 —').fontSize(12).fontColor('#BBBBBB')
                  .width('100%').height(40).textAlign(TextAlign.Center)
              }.padding({ left: 12, right: 12 })
            }
          }.layoutWeight(1)
          .onReachEnd(() => {
            if (this.hasMore && !this.isSearching) {
              this.searchBooks(this.searchPage + 1);
            }
          })
          .onScroll(() => {
            // 滚动结果列表时收起搜索框键盘与历史浮层
            if (this.searchFocused) {
              this.searchInputController.stopEditing();
              this.hideHistory();
            }
          })
          .onClick(() => {
            this.hideHistory();
          })
        } else {
          Column() {
            Text('📚').fontSize(48)
            Text(this.searchPage > 0 ? '未找到相关图书' : '搜索图书试试吧')
              .fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.hideHistory();
          })
        }
        }.width('100%').height('100%')  // 结束 馆藏资源 child0
        // ===== 我的借阅 =====
        Column() {
          // 借阅检索框（按当前子标签做服务端关键字检索）
          Row({ space: 6 }) {
            TextInput({ placeholder: '搜索借阅记录...', text: this.borrowSearchWord, controller: this.borrowSearchInputController })
              .layoutWeight(1).height(40).borderRadius(20).backgroundColor(ThemeColors.bgInput).padding({ left: 16, right: 16 })
              .onChange((v: string) => { this.borrowSearchWord = v; })
              .onSubmit(() => { this.doBorrowSearch(); })
            Button('搜索').height(40).borderRadius(20).backgroundColor('#8E24AA').fontColor('#FFFFFF')
              .onClick(() => { this.doBorrowSearch(); })
          }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 })

          // 子 tab：当前借阅 / 借阅历史
          Row() {
            Text('当前借阅').fontSize(14)
              .fontWeight(this.borrowSubTab === 0 ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.borrowSubTab === 0 ? '#8E24AA' : '#999999')
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .onClick(() => { this.borrowSubTab = 0; })
            Text('借阅历史').fontSize(14)
              .fontWeight(this.borrowSubTab === 1 ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.borrowSubTab === 1 ? '#8E24AA' : '#999999')
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .onClick(() => {
                this.borrowSubTab = 1;
                this.loadBorrowHistory();
              })
          }.width('100%').backgroundColor(ThemeColors.bgCard)
        if (this.borrowSubTab === 0) {
          // 操作栏：扫码借书 / 一键转借（正常布局流，置于列表上方，不悬浮遮挡）
          // 包成白色圆角卡片（带阴影+左右留边距），与上方子标签行在浅灰页面背景上形成清晰间隔
          Row({ space: 12 }).width('100%')
            .margin({ top: 14, left: 14, right: 14 })
            .padding({ left: 8, right: 8, top: 8, bottom: 8 })
            .backgroundColor(ThemeColors.bgCard)
            .borderRadius(12)
            .shadow({ radius: 2, color: '#00000008', offsetY: 1 }) {
            Button('扫码借书', { type: ButtonType.Normal })
              .fontSize(14).fontWeight(FontWeight.Medium)
              .fontColor('#388E3C')
              .backgroundColor(this.themeIsDark ? '#16331C' : '#E8F5E9')
              .height(42).borderRadius(21).layoutWeight(1)
              .onClick(() => { this.handleScanClick(); })
            Button('一键转借', { type: ButtonType.Normal })
              .fontSize(14).fontWeight(FontWeight.Medium)
              .fontColor('#E91E63')
              .backgroundColor(this.themeIsDark ? '#331A28' : '#FCE4EC')
              .height(42).borderRadius(21).layoutWeight(1)
              .onClick(() => { this.transferShowDialog = true; })
          }
          if (this.showLibLogin) {
            // 当前借阅登录取数：复用 libsp WebView 登录浮层（与借阅历史同一套）
            this.libLoginOverlay()
          } else {
          // 扫码结果反馈
          if (this.scanMsg.length > 0) {
            Text(this.scanMsg)
              .fontSize(13)
              .fontColor(this.scanMsg === '借阅成功！' ? '#FFFFFF' : '#FFFFFF')
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .backgroundColor(this.scanMsg === '借阅成功！' ? '#4CAF50' : '#FF7043')
              .borderRadius(8).width('100%')
              .margin({ left: 14, right: 14, bottom: 4 })
          }

          // 转借结果反馈
          if (this.transferMsg.length > 0) {
            Text(this.transferMsg)
              .fontSize(13).fontColor('#FFFFFF')
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .backgroundColor(this.transferMsg === '转借成功！' ? '#4CAF50' : '#FF7043')
              .borderRadius(8).width('100%')
              .margin({ left: 14, right: 14, bottom: 4 })
          }

          if (this.borrowList.length > 0) {
          Column() {
            if (this.errorMsg.length > 0) {
              Text(this.errorMsg).fontSize(13).fontColor('#FFFFFF')
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .backgroundColor(this.errorMsg.includes('成功') ? '#4CAF50' : '#FF7043')
                .borderRadius(8).width('100%')
                .margin({ left: 14, right: 14, bottom: 4 })
            }
            List({ space: 10 }) {
            ForEach(this.borrowList, (borrow: BorrowItem, idx?: number) => {
              ListItem() {
                Column() {
                  Row() {
                    // 封面
                    if (borrow.imagePixelMap) {
                      Image(borrow.imagePixelMap).width(64).height(90)
                        .objectFit(ImageFit.Cover).borderRadius(6)
                    } else if (borrow.imageUrl && borrow.imageUrl.length > 0) {
                      Image(borrow.imageUrl).width(64).height(90)
                        .objectFit(ImageFit.Cover).borderRadius(6)
                    } else {
                      Column() {
                        Text(borrow.title).fontSize(9).maxLines(3)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .textAlign(TextAlign.Center)
                          .padding({ left: 4, right: 4 })
                          .fontColor(this.themeIsDark ? '#888888' : '#AAAAAA')
                      }.width(64).height(90).borderRadius(6)
                      .backgroundColor(this.themeIsDark ? '#252525' : '#F5F5F5')
                      .justifyContent(FlexAlign.Center)
                      .border({ width: 0.5, color: this.themeIsDark ? '#3A3A3A' : '#DDDDDD' })
                    }
                    // 右侧信息
                    Column() {
                      // 书名 · 作者
                      Text(borrow.title)
                        .fontSize(15).fontWeight(FontWeight.Medium)
                        .fontColor(ThemeColors.textPrimary)
                        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                      if (borrow.author.length > 0) {
                        Text(borrow.author).fontSize(12).fontColor('#888888')
                          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                          .margin({ top: 3 })
                      }
                      // 借书日期 / 应还日期 / 剩余天数
                      Row({ space: 10 }) {
                        Column() {
                          Text('借书日期').fontSize(10).fontColor('#999999')
                          Text(this.fmtDateShort(borrow.loanDate)).fontSize(12)
                            .fontColor(ThemeColors.textPrimary).margin({ top: 2 })
                        }.alignItems(HorizontalAlign.Start)
                        Column() {
                          Text('应还日期').fontSize(10).fontColor('#999999')
                          Text(this.fmtDateShort(borrow.normReturnDate)).fontSize(12)
                            .fontColor('#E65100').margin({ top: 2 })
                        }.alignItems(HorizontalAlign.Start)
                        Column() {
                          Text('剩余天数').fontSize(10).fontColor('#999999')
                          Text(this.fmtLendDay(borrow.lendDay)).fontSize(12)
                            .fontColor(this.lendDayColor(borrow.lendDay)).margin({ top: 2 })
                        }.alignItems(HorizontalAlign.Start)
                      }.width('100%').margin({ top: 8 })
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start).margin({ left: 12 })
                  }.width('100%')
                  // 底部：续借剩余 + 续借按钮 + 详细按钮
                  Row({ space: 8 }) {
                    Text('续借剩余 ' + borrow.surplusRenewTimes + ' 次')
                      .fontSize(12).fontColor('#666666').layoutWeight(1)
                    if (borrow.surplusRenewTimes > 0) {
                      Button('续借', { type: ButtonType.Capsule })
                        .fontSize(13).height(32)
                        .backgroundColor('#8E24AA').fontColor(Color.White)
                        .onClick(() => { this.renewBook(borrow); })
                    } else {
                      Button('已无可续', { type: ButtonType.Capsule })
                        .fontSize(13).height(32)
                        .backgroundColor('#E0E0E0').fontColor('#9E9E9E')
                        .enabled(false)
                    }
                    Button('详细', { type: ButtonType.Capsule })
                      .fontSize(13).height(32)
                      .backgroundColor(this.themeIsDark ? '#333333' : '#EEEEEE')
                      .fontColor(ThemeColors.textPrimary)
                      .onClick(() => { this.openBorrowDetail(borrow); })
                  }.width('100%').margin({ top: 10 })
                }.width('100%').padding(14)
                .backgroundColor(ThemeColors.bgCard).borderRadius(12)
                .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
              }.padding({ left: 14, right: 14, top: 12, bottom: 12 })
                .margin({ left: 14, right: 14, bottom: 8 })
            }, (borrow: BorrowItem, idx?: number) => `borrow_${idx}_${borrow.imageUrl.length > 0 ? '1' : '0'}`)
          }.layoutWeight(1)
          .onScroll(() => {
            // 滚动借阅列表时同样收起搜索框键盘与历史浮层
            if (this.searchFocused) {
              this.borrowSearchInputController.stopEditing();
              this.hideHistory();
            }
          })
          .onClick(() => {
            this.hideHistory();
          })
          }.layoutWeight(1)
        } else {
          Column() {
            Text('📖').fontSize(48)
            Text('暂无借阅记录').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
            if (this.errorMsg.length > 0) {
              Text(this.errorMsg).fontSize(12).fontColor('#FF7043').margin({ top: 4 })
              Text('  重试').fontSize(12).fontColor(this.accentColor)
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .border({ width: 1, color: this.accentColor, radius: 4 })
                .margin({ top: 8 })
                .onClick(() => { this.errorMsg = ''; this.loadBorrowList(); })
            }
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.hideHistory();
          })
        }
          }  // 结束 当前借阅 子分支(else)
        } else {
          // ===== 借阅历史视图 =====
          // 头部（搜索结果/我的借阅 主标签 + 当前借阅/借阅历史 子标签）始终保留，
          // 仅在本内容区（子标签下方）显示状态：取数时显示鸿蒙加载动画，WebView 在背后静默跑。
          if (this.showLibLogin) {
            this.libLoginOverlay()
          } else if (this.historyList.length > 0) {
            List({ space: 4 }) {
              ForEach(this.historyList, (h: HistoryItem, idx?: number) => {
                ListItem() {
                  this.historyCard(h)
                }.padding({ left: 12, right: 12, top: 8, bottom: 8 })
              })
            }.layoutWeight(1)
            .onScroll(() => {
              if (this.searchFocused) {
                this.borrowSearchInputController.stopEditing();
                this.hideHistory();
              }
            })
          } else {
            Column() {
              Text('📚').fontSize(48)
              Text(this.historyLoaded ? '暂无借阅历史' : '加载中...').fontSize(14)
                .fontColor(ThemeColors.textSecondary).margin({ top: 12 })
              if (this.errorMsg.length > 0) {
                Text(this.errorMsg).fontSize(12).fontColor('#FF7043').margin({ top: 4 })
                Text('  重新登录').fontSize(12).fontColor(this.accentColor)
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                  .border({ width: 1, color: this.accentColor, radius: 4 })
                  .margin({ top: 8 })
                  .onClick(() => { this.errorMsg = ''; this.startLibLogin(); })
              }
            }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
          }
        }
        }.width('100%').height('100%')
      }
      }.width('100%').height('100%').backgroundColor(ThemeColors.bgPage)

        if (this.historyShow && this.currentTab === 0) {
          this.historyPanel()
        }

        if (this.selectedBook !== null) {
          // 背景遮罩
          Column()
            .width('100%').height('100%')
            .backgroundColor('#4D000000')
            .opacity(this.bookMaskOpacity)
            .onClick(() => { this.closeBookDetail(); })
          // 详情卡片
          Column() {
            Column() {
              this.bookDetailBuilder()
            }
            .width('100%').height('100%')
          }
          .width('100%').height('88%')
          .position({ x: 0, y: '12%' })
          .translate({ y: this.bookSheetOffset + '%' })
        }

        // 借阅详情弹窗（当前借阅 / 借阅历史 共用）：占位遮罩 + 底部抽屉
        if (this.detailBorrow !== null || this.detailHistory !== null) {
          Column()
            .width('100%').height('100%')
            .backgroundColor('#4D000000')
            .opacity(this.bookMaskOpacity)
            .onClick(() => { this.closeDetail(); })
          Column() {
            Column() {
              this.borrowDetailBuilder()
            }
            .width('100%').height('100%')
          }
          .width('100%').height('70%')
          .position({ x: 0, y: '30%' })
          .translate({ y: this.bookSheetOffset + '%' })
        }

        // 转借弹窗（输入框 + 右上角扫码 + 确认/取消）
        if (this.transferShowDialog) {
          Column() {
            Column({ space: 16 }) {
              Row() {
                Text('一键转借')
                  .fontSize(17).fontWeight(FontWeight.Medium)
                  .fontColor(ThemeColors.textPrimary).layoutWeight(1)
                Image($r('app.media.ic_public_scan_filled'))
                  .width(28).height(28)
                  .fillColor('#E91E63')
                  .padding(4)
                  .onClick(() => { this.handleTransferScan(); })
              }
              TextInput({ text: this.transferInput, placeholder: '输入条码号或点击右上角扫码' })
                .width('100%').height(44).borderRadius(8)
                .backgroundColor(ThemeColors.bgInput)
                .onChange((v: string) => { this.transferInput = v; })
              Row({ space: 12 }) {
                Button('取消').type(ButtonType.Capsule).fontSize(14)
                  .fontColor(ThemeColors.textSecondary)
                  .backgroundColor(ThemeColors.bgInput).layoutWeight(1)
                  .onClick(() => { this.transferShowDialog = false; this.transferInput = ''; })
                Button('确认').type(ButtonType.Capsule).fontSize(14)
                  .backgroundColor('#E91E63').fontColor(Color.White).layoutWeight(1)
                  .onClick(() => { this.handleTransferInput(); })
              }
            }
            .width('80%').padding(24).borderRadius(16)
            .backgroundColor(ThemeColors.bgCard)
            .onClick(() => {}) // 吞掉卡片内部点击，避免冒泡到遮罩触发关闭
          }
          .width('100%').height('100%')
          .backgroundColor('#4D000000').justifyContent(FlexAlign.Center)
          .zIndex(100)
          .onClick(() => { // 点击遮罩（弹窗外部）关闭弹窗
            this.transferShowDialog = false;
            this.transferInput = '';
          })
        }
      }
    }
    .title({ builder: this.buildWhiteTitle('图书馆'), height: 52 + this.statusBarHeight }, { backgroundColor: this.accentColor })
    .hideBackButton(true).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .backgroundColor(ThemeColors.bgPage)
    .onBackPressed(() => {
      if (this.showLibLogin) {
        this.stopLibLoginPoll();
        return true;
      }
      if (this.selectedBook !== null) {
        this.closeBookDetail();
        return true;
      }
      if (this.detailBorrow !== null || this.detailHistory !== null) {
        this.closeDetail();
        return true;
      }
      if (this.transferShowDialog) {
        this.transferShowDialog = false;
        this.transferInput = '';
        return true;
      }
      return false;
    })
  }
  @Builder
  bookDetailBuilder() {
    Column() {
      // 头部：封面（缩小，不再独占一行）+ 书名/作者 + 关闭（作者紧跟书名，不放封面下方）
      Row({ space: 12 }) {
        // 封面
        if (this.selectedBook?.imagePixelMap) {
          Image(this.selectedBook!.imagePixelMap)
            .width(76).height(106).objectFit(ImageFit.Cover).borderRadius(8).flexShrink(0)
        } else if (this.selectedBook?.imageUrl && (this.selectedBook!.imageUrl.length > 0)) {
          Image(this.selectedBook!.imageUrl)
            .width(76).height(106).objectFit(ImageFit.Cover).borderRadius(8).flexShrink(0)
        } else {
          Column() {
            Text('📖').fontSize(28)
            Text(this.selectedBook!.bookName)
              .fontSize(9).maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
              .padding({ left: 6, right: 6 })
              .fontColor(this.themeIsDark ? '#888888' : '#999999')
          }.width(76).height(106).borderRadius(8)
          .backgroundColor(this.themeIsDark ? '#252525' : '#F5F5F5')
          .justifyContent(FlexAlign.Center)
          .border({ width: 0.5, color: this.themeIsDark ? '#3A3A3A' : '#DDDDDD' })
          .flexShrink(0)
        }
        // 书名 + 作者（作者紧跟书名，不放到封面下方）
        Column() {
          Text(this.selectedBook?.bookName ?? '')
            .fontSize(17).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          if (this.selectedBook?.author && this.selectedBook.author.length > 0) {
            Text(this.selectedBook.author)
              .fontSize(13).fontColor(ThemeColors.textSecondary).margin({ top: 4 }).width('100%')
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        // 关闭
        Row() {
          Text('✕').fontSize(18).fontColor('#999999')
        }
        .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
        .justifyContent(FlexAlign.Center).flexShrink(0)
        .onClick(() => { this.closeBookDetail(); })
      }.width('100%').margin({ bottom: 8 })

      Divider().margin({ top: 4, bottom: 8 }).color('#F0F0F0')

      // 可滚动内容区域
      // 分栏：基本信息 / 馆藏副本（各自独立滚动，避免长摘要把馆藏挤下去）
      Column() {
      SegmentTab({
        tabs: ['基本信息', '馆藏副本'],
        currentIndex: $detailTab,
        accentColor: this.accentColor
      }) {
        // ===== Tab0 基本信息 =====
        Scroll() {
          Column() {
            if (this.selectedBook !== null && this.selectedBook.marcFields.length > 0) {
              Text('📖 基本信息').fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                .margin({ top: 12, bottom: 6 }).width('100%')
              Column() {
                ForEach(this.selectedBook.marcFields, (f: MarcField) => {
                  Row() {
                    Text(f.description).fontSize(12).fontColor(ThemeColors.textSecondary)
                      .width(82).flexShrink(0).align(Alignment.TopStart)
                    Text(f.fieldVal).fontSize(13).fontColor(ThemeColors.textPrimary)
                      .layoutWeight(1).align(Alignment.TopStart)
                  }.width('100%').padding({ top: 5, bottom: 5 }).alignItems(VerticalAlign.Top)
                  Divider().color('#F2F2F2')
                }, (f: MarcField, idx?: number) => `marc_${idx}_${f.key}`)
              }.width('100%')
            } else {
              Text('基本信息加载中…').fontSize(13).fontColor(ThemeColors.textSecondary)
                .width('100%').margin({ top: 16 })
            }
            // 电子书资源列表
            if (this.selectedBook !== null && this.selectedBook.eitems.length > 0) {
              Text('📱 电子书资源').fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                .margin({ top: 14, bottom: 6 }).width('100%')
              ForEach(this.selectedBook.eitems, (eb: EBookItem) => {
                Column() {
                  Row() {
                    Column() {
                      Text(eb.packageName || '电子书').fontSize(13).fontColor(ThemeColors.textPrimary)
                      if (eb.collectionName && eb.collectionName.length > 0) {
                        Text('📦 ' + eb.collectionName).fontSize(11).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
                      }
                      if (eb.dbVender && eb.dbVender.length > 0) {
                        Text('🏛️ ' + eb.dbVender).fontSize(11).fontColor(ThemeColors.textSecondary)
                      }
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    Text('↗').fontSize(18).fontColor('#1976D2')
                  }.width('100%').padding({ top: 8, bottom: 8 })
                  Divider().color('#F0F0F0')
                }
                .width('100%')
                .onClick(() => {
                  if (eb.url && eb.url.length > 0) {
                    this.openEBookUrl(eb.url);
                  } else if (eb.elecResourceUrl && eb.elecResourceUrl.length > 0) {
                    this.openEBookUrl(eb.elecResourceUrl);
                  }
                })
              }, (eb: EBookItem, idx?: number) => `ebook_${idx}`)
            }
          }.width('100%').padding({ bottom: 16 })
        }.width('100%').height('100%')

        // ===== Tab1 馆藏副本 =====
        Scroll() {
          Column() {
            // 馆藏统计（可借 / 馆藏总数）— 置于馆藏副本 Tab 顶部
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
              this.infoTag('📚 可借', `${this.selectedBook?.availableCount ?? 0}`, this.selectedBook !== null && this.selectedBook.availableCount > 0 ? '#4CAF50' : '#E53935')
              this.infoTag('🏢 馆藏', `${this.selectedBook?.totalCount ?? 0}`, '#333333')
            }.width('100%').margin({ top: 12, bottom: 6 })

            if (this.selectedBook !== null && this.selectedBook.holdings.length > 0) {
              ForEach(this.selectedBook.holdings, (h: HoldingItem, idx?: number) => {
                Row({ space: 10 }) {
                  // 序号
                  Text('#' + ((idx ?? 0) + 1)).fontSize(12).fontColor('#999999').width(28).flexShrink(0)
                  // 信息
                  Column() {
                    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                      Text('索书号').fontSize(11).fontColor(ThemeColors.textSecondary).width(48).flexShrink(0)
                      Text(h.callNo).fontSize(13).fontColor(ThemeColors.textPrimary)
                    }.width('100%')
                    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                      Text('条码号').fontSize(11).fontColor(ThemeColors.textSecondary).width(48).flexShrink(0)
                      Text(h.barcode).fontSize(13).fontColor(ThemeColors.textPrimary)
                    }.width('100%').margin({ top: 2 })
                    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                      Text('馆藏地').fontSize(11).fontColor(ThemeColors.textSecondary).width(48).flexShrink(0)
                      Text(h.shelfPos && h.shelfPos.length > 0 ? h.shelfPos : h.locationName).fontSize(13).fontColor(ThemeColors.textPrimary)
                    }.width('100%').margin({ top: 2 })
                    if (h.inDate && h.inDate.length > 0) {
                      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                        Text('入藏').fontSize(11).fontColor(ThemeColors.textSecondary).width(48).flexShrink(0)
                        Text(h.inDate).fontSize(12).fontColor('#777777')
                      }.width('100%').margin({ top: 2 })
                    }
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  // 状态 + 借出应还日期（应还日期换行显示，避免长串遮挡左侧信息）
                  Column() {
                    Text(h.processType).fontSize(12)
                      .fontColor(h.processType === '在架' ? '#4CAF50' : '#E53935')
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 }).borderRadius(4)
                      .backgroundColor(h.processType === '在架' ? '#E8F5E9' : '#FFEBEE')
                    if (h.processType === '借出' && h.dueDate.length > 0) {
                      Column() {
                        Text('应还日期：').fontSize(10).fontColor('#999999')
                        Text(h.dueDate).fontSize(12).fontColor('#E53935').margin({ top: 2 })
                      }.alignItems(HorizontalAlign.End).margin({ top: 4 })
                    } else if (h.circAttr && h.circAttr.length > 0 && h.circAttr !== '0') {
                      Text(h.circAttr).fontSize(10).fontColor('#888888').margin({ top: 4 })
                    }
                  }.alignItems(HorizontalAlign.End).width(80)
                    .onAppear(() => {
                      hilog.info(0xFF00, 'LibDiag', 'RENDER type=%{public}s dueDate=%{public}s',
                        h.processType, h.dueDate);
                    })
                }.width('100%').padding({ top: 8, bottom: 8 }).alignItems(VerticalAlign.Top)
                Divider().color('#F2F2F2')
              }, (h: HoldingItem, idx?: number) => `hold_${idx}`)
            } else {
              Text('馆藏信息加载中…').fontSize(13).fontColor(ThemeColors.textSecondary)
                .width('100%').margin({ top: 16 })
            }
          }.width('100%').padding({ bottom: 16 })
        }.width('100%').height('100%')
      }
      }.layoutWeight(1).width('100%')
    }
    .width('100%').height('100%')
    .padding({ left: 20, right: 20, top: 20, bottom: 20 })
    .backgroundColor(ThemeColors.bgPage)
    .borderRadius({ topLeft: 20, topRight: 20 })
  }

  // 借阅详情弹窗内容（当前借阅 / 借阅历史 共用），全部用文字标签，不用 Emoji
  @Builder
  borrowDetailBuilder() {
    Column() {
      // 标题栏：书名 + 关闭按钮
      Row() {
        Text(this.detailBorrow?.title ?? this.detailHistory?.title ?? '')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Row() {
          Text('✕').fontSize(18).fontColor('#999999')
        }
        .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
        .justifyContent(FlexAlign.Center)
        .onClick(() => { this.closeDetail(); })
      }.width('100%').padding({ bottom: 8 })

      // 作者
      Text((this.detailBorrow?.author ?? this.detailHistory?.author ?? ''))
        .fontSize(13).fontColor(ThemeColors.textSecondary)
      Divider().margin({ top: 10, bottom: 10 }).color('#F0F0F0')

      // 可滚动内容区域
      Scroll() {
        Column() {
          // —— 当前借阅详情 ——
          if (this.detailBorrow !== null) {
            this.detailRow('借阅日期', this.fmtDateShort(this.detailBorrow.loanDate))
            this.detailRow('应还日期', this.fmtDateShort(this.detailBorrow.normReturnDate))
            this.detailRow('剩余天数', this.fmtLendDay(this.detailBorrow.lendDay), this.lendDayColor(this.detailBorrow.lendDay))
            this.detailRow('续借情况', '已续 ' + this.detailBorrow.renewTimes + ' 次 · 剩 ' + this.detailBorrow.surplusRenewTimes + ' 次')
            if (this.detailBorrow.callNo.length > 0) { this.detailRow('索书号', this.detailBorrow.callNo) }
            if (this.detailBorrow.yearVol.trim().length > 0) { this.detailRow('年卷期', this.detailBorrow.yearVol.trim()) }
            if (this.detailBorrow.propNo.length > 0) { this.detailRow('财产号', this.detailBorrow.propNo) }
            if (this.detailBorrow.phyLibName.length > 0) { this.detailRow('分馆', this.detailBorrow.phyLibName) }
            if (this.detailBorrow.publisher.length > 0) {
              this.detailRow('出版社', this.detailBorrow.publisher + (this.detailBorrow.publishYear.length > 0 ? ' (' + this.detailBorrow.publishYear + ')' : ''))
            }
            if (this.detailBorrow.isbn.length > 0) { this.detailRow('ISBN', this.detailBorrow.isbn) }
            if (this.detailBorrow.barcode.length > 0) { this.detailRow('条码', this.detailBorrow.barcode) }
            if (this.detailBorrow.loanType.length > 0) { this.detailRow('借阅类型', this.fmtLoanType(this.detailBorrow.loanType)) }
            if (this.detailBorrow.isRequested.length > 0) { this.detailRow('是否被预约', this.detailBorrow.isRequested) }
          }
          // —— 借阅历史详情 ——
          if (this.detailHistory !== null) {
            this.detailRow('借阅日期', this.fmtDateShort(this.detailHistory.loanDate))
            this.detailRow('应还日期', this.fmtDateShort(this.detailHistory.normReturnDate))
            this.detailRow('实际还书', this.fmtDateShort(this.detailHistory.returnDate))
            if (this.detailHistory.propNo.length > 0) { this.detailRow('财产号', this.detailHistory.propNo) }
            if (this.detailHistory.locationName.length > 0) { this.detailRow('馆藏地', this.detailHistory.locationName) }
            if (this.detailHistory.publisher.length > 0) {
              this.detailRow('出版社', this.detailHistory.publisher + (this.detailHistory.publishYear.length > 0 ? ' (' + this.detailHistory.publishYear + ')' : ''))
            }
            if (this.detailHistory.isbn.length > 0) { this.detailRow('ISBN', this.detailHistory.isbn) }
            if (this.detailHistory.barcode.length > 0) { this.detailRow('条码', this.detailHistory.barcode) }
          }
        }.width('100%')
      }
      .width('100%').layoutWeight(1)
    }
    .width('100%').height('100%')
    .padding({ left: 20, right: 20, top: 20, bottom: 20 })
    .backgroundColor(ThemeColors.bgPage)
    .borderRadius({ topLeft: 20, topRight: 20 })
  }

  // 详情弹窗单行（文字标签 + 值）
  @Builder
  detailRow(label: string, value: string, color?: string) {
    Row() {
      Text(label).fontSize(13).fontColor(ThemeColors.textSecondary).width(84)
      Text(value.length > 0 ? value : '-').fontSize(13)
        .fontColor(color ?? ThemeColors.textPrimary)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
    }.width('100%').padding({ top: 9, bottom: 9 })
    .border({ width: { bottom: 0.5 }, color: '#F0F0F0' })
  }

  private openEBookUrl(url: string): void {
    if (url.length === 0) return;
    const ctx = getContext(this) as common.UIAbilityContext;
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: url
    };
    ctx.startAbility(want).catch(() => {
      ToastUtil.show('无法打开链接', 1500);
    });
  }

  @Builder
  infoTag(label: string, value: string, color: string) {
    Column() {
      Text(label).fontSize(11).fontColor(ThemeColors.textSecondary)
      Text(value).fontSize(13).fontColor(
        color).margin({ top: 2 })
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width('47%').padding({ top: 6, bottom: 6 })
  }
}
