// LibraryPage.ets — 图书馆页面
import { ThemeColors } from '../../utils/ThemeColors';
import { HttpUtil } from '../../utils/HttpUtil';
import { PreferenceUtil } from '../../utils/PreferenceUtil';

interface BookLocation {
  locationName: string;
  barCode: string;
  searchCode: string;
  campus: string;
  processType: string;  // "在架" or others
  itemId: string;
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
  totalCount: number;   // 馆藏总数
  availableCount: number; // 可借数
}

interface BorrowItem {
  name: string;
  borrowDate: string;
  returnDate: string;
}


@Component
export struct LibraryPage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  pageInfo: NavPathStack = new NavPathStack();
  @State searchWord: string = '';
  @State books: BookItem[] = [];
  @State borrowList: BorrowItem[] = [];
  @State currentTab: number = 0;
  @State isSearching: boolean = false;
  @State selectedBook: BookItem | null = null;
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;

  private http = HttpUtil.getInstance();

  aboutToAppear(): void { this.loadBorrowList(); }

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
      totalCount: locations.length,
      availableCount: available
    };
  }

  private makeBorrowItem(raw: Record<string, string>): BorrowItem {
    const item: BorrowItem = { name: '', borrowDate: '', returnDate: '' };
    item.name = raw['title'] || raw['bookName'] || '';
    item.borrowDate = raw['loanDate'] || '';
    item.returnDate = raw['returnDate'] || raw['normReturnDateTime'] || '';
    return item;
  }

  private buildFormBody(...pairs: string[]): string {
    const parts: string[] = [];
    for (let i = 0; i < pairs.length; i += 2) {
      parts.push(encodeURIComponent(pairs[i]) + '=' + encodeURIComponent(pairs[i + 1] || ''));
    }
    return parts.join('&');
  }

  async loadBorrowList(): Promise<void> {
    const userId: string = PreferenceUtil.getString('library_user_id');
    const token: string = PreferenceUtil.getString('library_token');
    if (!userId || !token) return;
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
    } catch { /* ignore */ }
  }

  async searchBooks(): Promise<void> {
    if (!this.searchWord.trim()) return;
    this.isSearching = true;
    try {
      await this.http.loadCookies();
      const body = this.buildFormBody(
        'libraryId', '5', 'searchWord', this.searchWord.trim(),
        'searchFiled', 'keyWord', 'page', '1', 'searchLocationStatus', '1'
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
      const result: BookItem[] = [];
      for (let i = 0; i < rawList.length; i++) {
        result.push(this.makeBookItem(rawList[i]));
      }
      this.books = result;
    } catch { this.books = []; } finally { this.isSearching = false; }
  }

  build() {
    NavDestination() {
      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索图书...', text: this.searchWord })
          .layoutWeight(1).height(40).borderRadius(20).backgroundColor(ThemeColors.bgInput).padding({ left: 16, right: 16 })
          .onChange((v: string) => { this.searchWord = v; })
          .onSubmit(() => { this.searchBooks(); })
        Button('搜索').height(40).borderRadius(20).backgroundColor('#8E24AA').fontColor('#FFFFFF')
          .onClick(() => { this.searchBooks(); })
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
        if (this.isSearching) {
          Column() {
            LoadingProgress().width(40).height(40).color(this.accentColor)
            Text('搜索中...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.books.length > 0) {
          List({ space: 4 }) {
            ForEach(this.books, (book: BookItem, idx?: number) => {
              ListItem() {
                Row() {
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
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .borderRadius(8).backgroundColor(ThemeColors.bgCard)
                .onClick(() => { this.selectedBook = book; })
              }.padding({ left: 12, right: 12 })
            }, (book: BookItem, idx?: number) => `book_${idx}`)
          }.layoutWeight(1)
        } else {
          Column() {
            Text('📚').fontSize(48)
            Text('搜索图书试试吧').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        }
      } else {
        if (this.borrowList.length > 0) {
          List({ space: 8 }) {
            ForEach(this.borrowList, (borrow: BorrowItem, idx?: number) => {
              ListItem() {
                Column() {
                  Text(borrow.name).fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                    .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Row({ space: 16 }) {
                    Text('借: ' + borrow.borrowDate).fontSize(11).fontColor(ThemeColors.textSecondary)
                    Text('还: ' + borrow.returnDate).fontSize(11).fontColor('#FF7043')
                  }.margin({ top: 4 })
                }.width('100%').padding(16).alignItems(HorizontalAlign.Start)
              }.padding({ left: 16, right: 16 })
            }, (borrow: BorrowItem, idx?: number) => `borrow_${idx}`)
          }.layoutWeight(1)
        } else {
          Column() {
            Text('📖').fontSize(48)
            Text('暂无借阅记录').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
            Text('首次使用需通过官网登录图书馆').fontSize(12).fontColor('#BBBBBB').margin({ top: 4 })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        }
      }
    }.width('100%').height('100%').backgroundColor(ThemeColors.bgPage)
    .bindContentCover(this.selectedBook !== null, this.bookDetailBuilder(), {
      modalTransition: ModalTransition.DEFAULT,
      backgroundColor: Color.Transparent
    })
    .title('图书馆', { backgroundColor: this.accentColor })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .backgroundColor(ThemeColors.bgPage)
  }
  @Builder
  bookDetailBuilder() {
    Column() {
      // 半透明背景点击关闭
      Column().width('100%').layoutWeight(1).onClick(() => { this.selectedBook = null; })
      // 详情卡片（限高75%，内容可滚动）
      Scroll() {
        Column() {
          // 书名
          Text(this.selectedBook?.bookName ?? '').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          // 作者
          Text(this.selectedBook?.author ?? '').fontSize(13).fontColor(ThemeColors.textSecondary).margin({ top: 6 })
          Divider().margin({ top: 12, bottom: 8 }).color('#F0F0F0')
          // 信息网格
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            this.infoTag('可借', `${this.selectedBook?.availableCount ?? 0}`, this.selectedBook !== null && this.selectedBook.availableCount > 0 ? '#4CAF50' : '#E53935')
            this.infoTag('馆藏', `${this.selectedBook?.totalCount ?? 0}`, '#333333')
            this.infoTag('索书号', this.selectedBook?.callNos || (this.selectedBook !== null && this.selectedBook.items.length > 0 ? this.selectedBook.items[0].searchCode : '') || '-', '#555555')
            this.infoTag('发行时间', this.selectedBook?.publishYear ?? '-', '#555555')
            this.infoTag('ISBN', this.selectedBook?.isbn ?? '-', '#555555')
            this.infoTag('编排号码', this.selectedBook?.docNumber ?? '-', '#555555')
          }.width('100%')
          // 馆藏位置列表
          if (this.selectedBook !== null && this.selectedBook.items.length > 0) {
            Text('馆藏位置').fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
              .margin({ top: 14, bottom: 6 }).width('100%')
            ForEach(this.selectedBook.items, (loc: BookLocation) => {
              Row() {
                Column() {
                  Text(loc.locationName).fontSize(13).fontColor(ThemeColors.textPrimary)
                  Text(loc.barCode).fontSize(11).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text(loc.processType).fontSize(12)
                  .fontColor(loc.processType === '在架' ? '#4CAF50' : '#E53935')
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 }).borderRadius(4)
                  .backgroundColor(loc.processType === '在架' ? '#E8F5E9' : '#FFEBEE')
              }.width('100%').padding({ top: 8, bottom: 8 })
            }, (loc: BookLocation, idx?: number) => `loc_${idx}`)
          }
        }.width('100%').padding(20)
      }.width('100%').constraintSize({ maxHeight: '75%' }).backgroundColor(ThemeColors.bgInput).borderRadius({ topLeft: 16, topRight: 16 })
    }.width('100%').height('100%')
  }
  @Builder
  infoTag(label: string, value: string, color: string) {
    Column() {
      Text(label).fontSize(11).fontColor(ThemeColors.textSecondary)
      Text(value).fontSize(13).fontColor(color).margin({ top: 2 })
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width('47%').padding({ top: 6, bottom: 6 })
  }
}
