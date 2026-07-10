import { ToastUtil } from '../../utils/ToastUtil';
﻿import { AccentColors } from '../../utils/AccentColors';
// LibraryPage.ets — 图书馆页面
import { ThemeColors } from '../../utils/ThemeColors';
import { HttpUtil, HttpResponse } from '../../utils/HttpUtil';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { CasLoginService, LibraryAuthResult } from '../../services/CasLoginService';
import { common } from '@kit.AbilityKit';

import Want from '@ohos.app.ability.Want';

interface BookLocation {
  locationName: string;
  barCode: string;
  searchCode: string;
  campus: string;
  processType: string;  // "在架" or others
  itemId: string;
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
  totalCount: number;   // 馆藏总数
  availableCount: number; // 可借数
  imageUrl: string;
}

interface BorrowItem {
  title: string;
  author: string;
  publisher: string;
  isbn: string;
  barcode: string;
  loanDate: string;
  normReturnDate: string;
  lendDay: number;
  imageUrl: string;
  locationName: string;
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
  @State errorMsg: string = '';
  @State currentTab: number = 0;
  @State isSearching: boolean = false;
  @State selectedBook: BookItem | null = null;
  @State bookMaskOpacity: number = 0;
  @State bookSheetOffset: number = 100;
  @State searchHistory: SearchHistoryItem[] = [];
  @State searchFocused: boolean = false;
  private searchInputController: TextInputController = new TextInputController();
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;

  private http = HttpUtil.getInstance();

  aboutToAppear(): void { this.loadBorrowList(); this.loadSearchHistory(); }

  closeBookDetail(): void {
    animateTo({ duration: 200, curve: Curve.EaseIn }, () => {
      this.bookMaskOpacity = 0;
      this.bookSheetOffset = 100;
    });
    setTimeout(() => { this.selectedBook = null; }, 200);
  }

  private makeBookItem(raw: Record<string, Object>): BookItem {
    const locations: BookLocation[] = [];
    const rawItems: Object[] = (raw['items'] as Object[]) || [];
    let available = 0;
    for (let i = 0; i < rawItems.length; i++) {
      const loc = rawItems[i] as Record<string, string>;
      const pt = loc['processType'] || '';
      if (pt === '在架') available++;
      locations.push({
        locationName: loc['locationName'] || '',
        barCode: loc['barCode'] || '',
        searchCode: loc['searchCode'] || '',
        campus: loc['campus'] || '',
        processType: pt,
        itemId: loc['itemId'] || ''
      });
    }
    const ebooks: EBookItem[] = [];
    const rawEItems: Object[] = (raw['eitems'] as Object[]) || [];
    for (let i = 0; i < rawEItems.length; i++) {
      const eb = rawEItems[i] as Record<string, string>;
      ebooks.push({
        itemId: eb['itemId'] || '',
        packageId: eb['packageId'] || '',
        packageName: eb['packageName'] || '',
        collectionName: eb['collectionName'] || '',
        dbVender: eb['dbVender'] || '',
        url: eb['url'] || '',
        elecResourceUrl: eb['elecResourceUrl'] || ''
      });
    }
    return {
      bookName: String(raw['bookName'] ?? ''),
      author: String(raw['author'] ?? ''),
      publisher: String(raw['publisher'] ?? ''),
      publishYear: String(raw['publishYear'] ?? ''),
      isbn: String(raw['isbn'] ?? ''),
      docNumber: String(raw['docNumber'] ?? ''),
      callNos: String(raw['callNos'] ?? ''),
      groupCode: String(raw['groupCode'] ?? ''),
      subject: String(raw['subject'] ?? ''),
      items: locations,
      eitems: ebooks,
      totalCount: locations.length,
      availableCount: available,
      imageUrl: ''
    };
  }

  private makeBorrowItem(raw: Record<string, string>): BorrowItem {
    const ld: number = parseInt(raw['lendDay'] || '0');
    return {
      title: raw['title'] || '',
      author: raw['author'] || '',
      publisher: raw['publisher'] || '',
      isbn: raw['isbn'] || raw['isbn13'] || raw['isbn10'] || '',
      barcode: raw['barcode'] || '',
      loanDate: raw['loanDate'] || '',
      normReturnDate: raw['normReturnDate'] || '',
      lendDay: isNaN(ld) ? 0 : ld,
      imageUrl: '',
      locationName: raw['locationName'] || ''
    };
  }

  private buildFormBody(...pairs: string[]): string {
    const parts: string[] = [];
    for (let i = 0; i < pairs.length; i += 2) {
      parts.push(encodeURIComponent(pairs[i]) + '=' + encodeURIComponent(pairs[i + 1] || ''));
    }
    return parts.join('&');
  }

  private async renewBook(borrow: BorrowItem): Promise<void> {
    const userId: string = PreferenceUtil.getString('library_user_id');
    const token: string = PreferenceUtil.getString('library_token');
    if (!userId || !token) {
      this.errorMsg = '认证已过期，请下拉重试';
      return;
    }
    try {
      const body: string = this.buildFormBody(
        'libraryId', '5', 'userId', userId, 'token', token,
        'cardNumber', PreferenceUtil.getString('ids_account'),
        'barNumber', borrow.barcode
      );
      const resp: HttpResponse = await this.http.postRaw(
        'https://shuwo.xidian.edu.cn/xidian_book/api/borrow/renewBook.html',
        body, 'application/x-www-form-urlencoded; charset=UTF-8', undefined
      );
      if (resp.statusCode === 200) {
        const raw: Record<string, Object> = resp.json<Record<string, Object>>();
        const msg: string = String(raw['msg'] ?? '续借成功');
        this.errorMsg = msg;
      } else {
        this.errorMsg = '续借失败 (HTTP ' + resp.statusCode + ')';
      }
    } catch (e) {
      this.errorMsg = '续借请求失败';
    }
    // 清除提示
    setTimeout(() => { this.errorMsg = ''; }, 3000);
  }

  private fmtDateShort(raw: string): string {
    // "2026-05-20" or "2026/05/20" → "05/20"
    const m: RegExpMatchArray | null = (raw).match(/(\d{2})[\/-](\d{2})$/);
    return m ? (m[1] + '/' + m[2]) : raw.substring(0, 10);
  }

  private lendDayColor(day: number): string {
    if (day < 0) return '#E53935';
    if (day <= 3) return '#FF9800';
    return '#4CAF50';
  }

  private fmtLendDay(day: number): string {
    if (day < 0) return '已逾期 ' + Math.abs(day) + ' 天 😥';
    if (day === 0) return '今日到期 ⚡';
    if (day <= 3) return '剩余 ' + day + ' 天 ⚡';
    return '剩余 ' + day + ' 天';
  }

  private async fetchBorrowCovers(borrows: BorrowItem[]): Promise<void> {
    for (let i: number = 0; i < borrows.length; i += 5) {
      const batch: BorrowItem[] = borrows.slice(i, i + 5);
      const tasks: Promise<string>[] = batch.map((b: BorrowItem) =>
        this.fetchBookCover(b.title, b.isbn, b.barcode)
      );
      const urls: string[] = await Promise.all(tasks);
      for (let j: number = 0; j < batch.length; j++) {
        batch[j].imageUrl = urls[j];
      }
    }
    // 新建对象数组触发 ForEach 重渲染
    const updated: BorrowItem[] = [];
    for (let k: number = 0; k < borrows.length; k++) {
      const b: BorrowItem = borrows[k];
      updated.push({
        title: b.title, author: b.author, publisher: b.publisher,
        isbn: b.isbn, barcode: b.barcode,
        loanDate: b.loanDate, normReturnDate: b.normReturnDate,
        lendDay: b.lendDay, imageUrl: b.imageUrl, locationName: b.locationName
      });
    }
    this.borrowList = updated;
  }

  async loadBorrowList(): Promise<void> {
    // 先获取图书馆 token（通过 CAS 重定向到 hyytsgxzs 获取）
    let userId: string = PreferenceUtil.getString('library_user_id');
    let token: string = PreferenceUtil.getString('library_token');
    if (!userId || !token) {
      try {
        const auth: LibraryAuthResult | null =
          await CasLoginService.getInstance().getLibraryAuth();
        if (auth) { userId = auth.userId; token = auth.token; }
      } catch (_authErr) {}
    }
    if (!userId || !token) { this.errorMsg = '图书馆认证失败，请重试'; return; }
    try {
      await this.http.loadCookies();
      const body = this.buildFormBody(
        'libraryId', '5', 'userId', userId, 'token', token,
        'cardNumber', PreferenceUtil.getString('ids_account'), 'page', '0'
      );
      const resp = await this.http.postRaw(
        'https://shuwo.xidian.edu.cn/xidian_book/api/borrow/getBorrowList.html',
        body, 'application/x-www-form-urlencoded; charset=UTF-8', undefined
      );
      if (resp.statusCode !== 200) {
        throw new Error('HTTP ' + resp.statusCode);
      }
      const raw: Record<string, object> = resp.json<Record<string, object>>();
      const rawList: Record<string, string>[] = (raw['data'] as Record<string, string>[]) || [];
      const result: BorrowItem[] = [];
      for (let i = 0; i < rawList.length; i++) {
        result.push(this.makeBorrowItem(rawList[i]));
      }
      this.borrowList = result;
      // 保存借阅概况给主页卡片用
      let overdue = 0;
      for (const b of result) { if (b.lendDay < 0) overdue++; }
      PreferenceUtil.putString('lib_summary', result.length + '|' + overdue);
      this.fetchBorrowCovers(result);
    } catch (e) {
      this.errorMsg = '借阅列表加载失败，请下拉重试';
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
        return url;
      }
    } catch (e) {
      // 封面获取失败不影响主流程
    }
    return '';
  }

  private cloneBookItem(b: BookItem): BookItem {
    return {
      bookName: b.bookName, author: b.author, publisher: b.publisher,
      publishYear: b.publishYear, isbn: b.isbn, docNumber: b.docNumber,
      callNos: b.callNos, groupCode: b.groupCode, subject: b.subject,
      items: b.items, eitems: b.eitems, totalCount: b.totalCount, availableCount: b.availableCount,
      imageUrl: b.imageUrl
    };
  }

  private async fetchAllCovers(newBooks: BookItem[]): Promise<void> {
    for (let i: number = 0; i < newBooks.length; i += 5) {
      const batch: BookItem[] = newBooks.slice(i, i + 5);
      const tasks: Promise<string>[] = batch.map((b: BookItem) =>
        this.fetchBookCover(b.bookName, b.isbn, b.docNumber)
      );
      const urls: string[] = await Promise.all(tasks);
      for (let j: number = 0; j < batch.length; j++) {
        batch[j].imageUrl = urls[j];
      }
    }
    // 基于当前 this.books 重建数组，触发 ForEach 重渲染（保留所有页的数据）
    const updated: BookItem[] = [];
    for (let k: number = 0; k < this.books.length; k++) {
      updated.push(this.cloneBookItem(this.books[k]));
    }
    this.books = updated;
  }

  async searchBooks(page?: number): Promise<void> {
    if (!this.searchWord.trim()) return;
    const p: number = page ?? 1;
    if (p === 1) { this.books = []; this.searchPage = 1; }
    this.isSearching = true;
    try {
      await this.http.loadCookies();
      const body = this.buildFormBody(
        'libraryId', '5', 'searchWord', this.searchWord.trim(),
        'searchFiled', this.searchField, 'page', String(p), 'searchLocationStatus', '1'
      );
      const resp = await this.http.postRaw(
        'https://shuwo.xidian.edu.cn/xidian_book/api/search/list.html',
        body, 'application/x-www-form-urlencoded; charset=UTF-8', undefined
      );
      if (resp.statusCode !== 200) {
        throw new Error('HTTP ' + resp.statusCode);
      }
      const raw: Record<string, object> = resp.json<Record<string, object>>();
      const listData = raw['data'] as Record<string, object>;
      const rawList: Record<string, Object>[] = (listData?.['list'] as Record<string, Object>[]) || [];
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
      this.hasMore = rawList.length >= 20;
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

  // 点击历史标签：回填字段+关键词并立即搜索
  private applyHistory(item: SearchHistoryItem): void {
    this.searchField = item.f;
    this.searchWord = item.w;
    this.searchInputController.stopEditing();
    this.searchFocused = false;
    this.searchBooks();
  }

  // 统一搜索入口：收起键盘与历史面板后执行搜索
  private doSearch(): void {
    this.searchInputController.stopEditing();
    this.searchFocused = false;
    this.searchBooks();
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
    .position({ x: 0, y: 56 })
    .backgroundColor(ThemeColors.bgCard)
    .borderRadius(12)
    .shadow({ radius: 8, color: '#00000018', offsetY: 4 })
    .zIndex(100)
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          Row({ space: 6 }) {
            Select([{ value: '关键词' }, { value: '书名' }, { value: '作者' },
              { value: 'ISBN' }, { value: '条码' }, { value: '索书号' }])
              .selected(this.getSearchFieldIndex())
              .value(this.fieldLabel())
              .onSelect((idx: number) => { this.searchField = this.indexToField(idx); })
              .width(100)
            TextInput({ placeholder: '搜索图书...', text: this.searchWord, controller: this.searchInputController })
          .layoutWeight(1).height(40).borderRadius(20).backgroundColor(ThemeColors.bgInput).padding({ left: 16, right: 16 })
          .onChange((v: string) => { this.searchWord = v; })
          .onSubmit(() => { this.doSearch(); })
          .onFocus(() => { this.searchFocused = true; })
          .onBlur(() => { this.searchFocused = false; })
        Button('搜索').height(40).borderRadius(20).backgroundColor('#8E24AA').fontColor('#FFFFFF')
          .onClick(() => { this.doSearch(); })
      }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 })

      Row() {
        Text('搜索结果').fontSize(14)
          .fontWeight(this.currentTab === 0 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.currentTab === 0 ? '#8E24AA' : '#999999')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .onClick(() => { this.currentTab = 0; })
        Text('我的借阅').fontSize(14)
          .fontWeight(this.currentTab === 1 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.currentTab === 1 ? '#8E24AA' : '#999999')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .onClick(() => { this.currentTab = 1; this.loadBorrowList(); })
      }.width('100%').backgroundColor(ThemeColors.bgCard)
      Divider().color('#F0F0F0')

      if (this.currentTab === 0) {
        if (this.isSearching && this.books.length === 0) {
          // 首次搜索：全屏加载
          Column() {
            LoadingProgress().width(40).height(40).color(this.accentColor)
            Text('搜索中...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.books.length > 0) {
          // 有数据：显示列表（翻页时列表保留，底部追加 loading）
          List({ space: 4 }) {
            ForEach(this.books, (book: BookItem, idx?: number) => {
              ListItem() {
                Row() {
                  if (book.imageUrl && book.imageUrl.length > 0) {
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
                  this.selectedBook = book;
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
        } else {
          Column() {
            Text('📚').fontSize(48)
            Text(this.searchPage > 0 ? '未找到相关图书' : '搜索图书试试吧')
              .fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        }
      } else {
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
                    if (borrow.imageUrl && borrow.imageUrl.length > 0) {
                      Image(borrow.imageUrl).width(72).height(100)
                        .objectFit(ImageFit.Cover).borderRadius(6)
                    } else {
                      Column() {
                        Text('📖').fontSize(28)
                        Text(borrow.title).fontSize(8).maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .textAlign(TextAlign.Center)
                          .padding({ left: 3, right: 3 })
                          .fontColor(this.themeIsDark ? '#888888' : '#AAAAAA')
                      }.width(72).height(100).borderRadius(6)
                      .backgroundColor(this.themeIsDark ? '#252525' : '#F5F5F5')
                      .justifyContent(FlexAlign.Center)
                      .border({ width: 0.5, color: this.themeIsDark ? '#3A3A3A' : '#DDDDDD' })
                    }
                    // 右侧信息
                    Column() {
                      Text(borrow.title).fontSize(15).fontWeight(FontWeight.Medium)
                        .fontColor(ThemeColors.textPrimary)
                        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                      if (borrow.author.length > 0) {
                        Row() {
                          Text(borrow.author).fontSize(12).fontColor('#888888')
                            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                            .layoutWeight(1)
                          if (borrow.locationName.length > 0) {
                            Text('📍' + borrow.locationName).fontSize(10)
                              .fontColor('#8E24AA')
                              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                              .border({ width: 0.5, color: '#E1BEE7', radius: 8 })
                          }
                        }.width('100%').margin({ top: 3 })
                      }
                      // 日期戳
                      Row({ space: 6 }) {
                        Row({ space: 2 }) {
                          Text('📅').fontSize(10)
                          Text(this.fmtDateShort(borrow.loanDate)).fontSize(11)
                            .fontColor('#666666')
                        }.padding({ left: 8, right: 8, top: 3, bottom: 3 })
                        .backgroundColor(this.themeIsDark ? '#1E2A1E' : '#E8F5E9')
                        .borderRadius(10)
                        Text('→').fontSize(11).fontColor('#CCCCCC')
                        Row({ space: 2 }) {
                          Text('⏰').fontSize(10)
                          Text(this.fmtDateShort(borrow.normReturnDate)).fontSize(11)
                            .fontColor('#E65100')
                        }.padding({ left: 8, right: 8, top: 3, bottom: 3 })
                        .backgroundColor(this.themeIsDark ? '#2E1E1E' : '#FFF3E0')
                        .borderRadius(10)
                      }.margin({ top: 8 })
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start).margin({ left: 12 })
                  }.width('100%')
                  // 剩余天数 + 续借
                  Row() {
                    Text(this.fmtLendDay(borrow.lendDay)).fontSize(13).fontWeight(FontWeight.Medium)
                      .fontColor(this.lendDayColor(borrow.lendDay)).layoutWeight(1)
                    if (borrow.lendDay >= 0) {
                      Text('🔄 续借').fontSize(12).fontColor('#8E24AA')
                        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                        .border({ width: 1, color: '#CE93D8', radius: 14 })
                        .onClick(() => { this.renewBook(borrow); })
                    } else {
                      Text('已逾期不可续').fontSize(11).fontColor('#CCCCCC')
                        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                        .border({ width: 1, color: '#EEEEEE', radius: 14 })
                    }
                  }.width('100%').margin({ top: 10 })
                }.width('100%').padding(14)
                .backgroundColor(ThemeColors.bgCard).borderRadius(12)
                .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
              }.padding({ left: 14, right: 14, top: 12, bottom: 12 })
                .margin({ left: 14, right: 14, bottom: 8 })
            }, (borrow: BorrowItem, idx?: number) => `borrow_${idx}_${borrow.imageUrl.length > 0 ? '1' : '0'}`)
          }.layoutWeight(1)
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
        }
      }
        }
        .width('100%').height('100%').backgroundColor(ThemeColors.bgPage)

        if (this.searchFocused && this.searchHistory.length > 0) {
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
          .width('100%').height('70%')
          .position({ x: 0, y: '30%' })
          .translate({ y: this.bookSheetOffset + '%' })
        }
      }
    }
    .title({ builder: this.buildWhiteTitle('图书馆'), height: 52 + this.statusBarHeight }, { backgroundColor: this.accentColor })
    .hideBackButton(true).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .backgroundColor(ThemeColors.bgPage)
    .onBackPressed(() => {
      if (this.selectedBook !== null) {
        this.closeBookDetail();
        return true;
      }
      return false;
    })
  }
  @Builder
  bookDetailBuilder() {
    Column() {
      // 标题栏：书名 + 关闭按钮
      Row() {
        Text(this.selectedBook?.bookName ?? '')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Row() {
          Text('✕').fontSize(18).fontColor('#999999')
        }
        .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
        .justifyContent(FlexAlign.Center)
        .onClick(() => { this.closeBookDetail(); })
      }.width('100%').padding({ bottom: 8 })

      // 封面
      if (this.selectedBook?.imageUrl && (this.selectedBook!.imageUrl.length > 0)) {
        Image(this.selectedBook!.imageUrl)
          .width(100).height(140)
          .objectFit(ImageFit.Cover).borderRadius(8)
          .margin({ bottom: 10 })
      } else {
        Column() {
          Text('📖').fontSize(36)
          Text(this.selectedBook!.bookName)
            .fontSize(10).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
            .padding({ left: 8, right: 8 })
            .fontColor(this.themeIsDark ? '#888888' : '#999999')
        }.width(100).height(140).borderRadius(8)
        .backgroundColor(this.themeIsDark ? '#252525' : '#F5F5F5')
        .justifyContent(FlexAlign.Center)
        .border({ width: 0.5, color: this.themeIsDark ? '#3A3A3A' : '#DDDDDD' })
        .margin({ bottom: 10 })
      }

      // 作者
      Text(this.selectedBook?.author ?? '').fontSize(13).fontColor(ThemeColors.textSecondary)
      Divider().margin({ top: 10, bottom: 10 }).color('#F0F0F0')

      // 可滚动内容区域
      Scroll() {
        Column() {
          // 信息网格
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            this.infoTag('📚 可借', `${this.selectedBook?.availableCount ?? 0}`, this.selectedBook !== null && this.selectedBook.availableCount > 0 ? '#4CAF50' : '#E53935')
            this.infoTag('🏢 馆藏', `${this.selectedBook?.totalCount ?? 0}`, '#333333')
            this.infoTag('🏷️ 索书号', this.selectedBook?.callNos || (this.selectedBook !== null && this.selectedBook.items.length > 0 ? this.selectedBook.items[0].searchCode : '') || '-', '#555555')
            this.infoTag('📅 发行时间', this.selectedBook?.publishYear ?? '-', '#555555')
            this.infoTag('🔢 ISBN', this.selectedBook?.isbn ?? '-', '#555555')
            this.infoTag('📋 编排号码', this.selectedBook?.docNumber ?? '-', '#555555')
          }.width('100%')
          // 馆藏位置列表
          if (this.selectedBook !== null && this.selectedBook.items.length > 0) {
            Text('📍 馆藏位置').fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
              .margin({ top: 14, bottom: 6 }).width('100%')
            ForEach(this.selectedBook.items, (loc: BookLocation) => {
              Row() {
                Column() {
                  Text(loc.locationName).fontSize(13).fontColor(ThemeColors.textPrimary)
                  Text('🔖 书籍编号：' + loc.barCode).fontSize(11).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text(loc.processType).fontSize(12)
                  .fontColor(loc.processType === '在架' ? '#4CAF50' : '#E53935')
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 }).borderRadius(4)
                  .backgroundColor(loc.processType === '在架' ? '#E8F5E9' : '#FFEBEE')
              }.width('100%').padding({ top: 8, bottom: 8 })
            }, (loc: BookLocation, idx?: number) => `loc_${idx}`)
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
        }
        .width('100%')
      }
      .width('100%').layoutWeight(1)
    }
    .width('100%').height('100%')
    .padding({ left: 20, right: 20, top: 20, bottom: 20 })
    .backgroundColor(ThemeColors.bgPage)
    .borderRadius({ topLeft: 20, topRight: 20 })
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
