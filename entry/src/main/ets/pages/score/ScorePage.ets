import { AccentColors } from '../../utils/AccentColors';
import { menuOptions } from '../../utils/MaterialKit';
// ScorePage.ets — 成绩查询（含成绩构成详情，增强层次感版）
import { SemesterUtil, ScoreItemModel, ComposeDetail } from '../../services/ids/EhallService';
import { ScoreService } from '../../services/ids/ScoreService';
import { ThemeColors } from '../../utils/ThemeColors';
import { motion } from '@kit.MultimodalAwarenessKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { curves } from '@kit.ArkUI';

@Component
export struct ScorePage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  pageInfo: NavPathStack = new NavPathStack();
  @State loading: boolean = true;  // 初始为 true，避免 waitAndLoad 等待期间显示空状态
  @State errorMsg: string = '';
  @State staleTip: string = '';     // 非空时表示当前显示的是离线/过期缓存数据，附「重试」
  @State selectedSemester: string = '';
  @State semesterCodes: string[] = [];
  @State selectedType: string = '__all__';
  @State typeOptions: string[] = [];
  @State currentScores: ScoreItemModel[] = [];
  @State searchWord: string = '';
  @State totalGPA: string = '';
  @State totalAvg: string = '';
  @State totalCredits: string = '';

  // 成绩构成详情弹窗状态
  @State selectedCell: ScoreItemModel | null = null;
  @State cardScale: number = 0.85;
  @State cardOpacity: number = 0;
  @State maskOpacity: number = 0; // 新增：单独控制背景遮罩透明度
  @State detailLoading: boolean = false;
  @State currentDetail: ComposeDetail[] = [];
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;

  // ===== 选择成绩计算 =====
  @State isSelectMode: boolean = false;
  @State isLeftHand: boolean = false;
  @State fabTranslateX: number = 0;  // 悬浮按钮位置：正值靠右，负值靠左
  private fabInitialized: boolean = false;  // 首次布局完成后才做动画
  private screenWidth: number = 360;  // 屏幕宽度（vp），onAreaChange 更新

  // 成绩卡片网格列数：宽屏多列，窄屏单列（对齐 Flutter AlignedGridView count = maxWidth~/cardWidth）
  private getScoreColumns(): number {
    if (this.screenWidth <= 0) return 1;
    return Math.max(1, Math.floor(this.screenWidth / 380));
  }
  @State selectedIndexes: Set<number> = new Set();
  @State selectedGPA: string = '--';
  @State selectedAvg: string = '--';
  @State selectedCredit: string = '0';

  private allScores: ScoreItemModel[] = [];
  private detailCache: Map<string, ComposeDetail[]> = new Map();

    @Builder buildWhiteTitle(t: string) {
    Row() {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.close'))
          .height(22)
          .fillColor(ThemeColors.textPrimary)
          .draggable(false)
      }
      .height(40).width(40)
      .hoverEffect(HoverEffect.Auto).onClick(() => { this.pageInfo.pop(); })
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


  aboutToAppear(): void {
    this.waitAndLoad();
    this.startHoldingHandDetection();
  }

  aboutToDisappear(): void {
    try {
      motion.off('holdingHandChanged');
    } catch (e) {
      // ignore
    }
  }

  private startHoldingHandDetection(): void {
    try {
      motion.on('holdingHandChanged', (data: number) => {
        const wasLeft = this.isLeftHand;
        this.isLeftHand = (data === 1 || data === 3);
        if (wasLeft !== this.isLeftHand) {
          this.animateFab();
        }
      });
    } catch (err) {
      const e = err as BusinessError;
      if (e.code === 801) {
      }
      this.isLeftHand = false;
    }
  }

  private animateFab(): void {
    if (!this.fabInitialized) return;
    // 右手：translateX = 0（按钮在右侧 Stack.BottomEnd）
    // 左手：translateX = -(screenWidth - 80)（滑到左侧）
    const targetX = this.isLeftHand ? -(this.screenWidth - 80) : 0;
    animateTo({ duration: 400, curve: curves.springMotion(0.45, 0.85) }, () => {
      this.fabTranslateX = targetX;
    });
  }

  private async waitAndLoad(): Promise<void> {
    let waited = 0;
    while (waited < 2000) {
      await new Promise<void>((r) => { setTimeout(r, 300); });
      waited += 300;
    }
    this.loadScores();
  }

  async loadScores(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      const raw: string = await ScoreService.getInstance().getScores('');
      const items: ScoreItemModel[] = ScoreService.parseScores(raw);

      this.allScores = items;

      const semSet: string[] = [];
      const seen = new Set<string>();
      for (let i = 0; i < items.length; i++) {
        const item: ScoreItemModel = items[i];
        const sem: string = item.xnxqdm;
        if (!seen.has(sem)) {
          seen.add(sem);
          semSet.push(sem);
        }
      }
      semSet.sort((a, b) => b.localeCompare(a));
      this.semesterCodes = semSet;

      // 提取课程类型
      const typeSet: string[] = [];
      const seenType = new Set<string>();
      for (let i = 0; i < items.length; i++) {
        const label = this.getTagLabel(items[i]);
        if (label && !seenType.has(label)) {
          seenType.add(label);
          typeSet.push(label);
        }
      }
      this.typeOptions = typeSet;

      if (semSet.length > 0) {
        this.selectedSemester = semSet[0];
        this.applyFilter();
      }
      // 判断展示的是否为「离线/过期缓存」：CacheService.getOrFetch 已自动回退过期缓存，
      // 因此即便网络失败也可能拿到数据；用「未过期缓存」是否存在来区分，给出离线提示。
      const fresh: boolean = await ScoreService.getInstance().isScoreCacheFresh('');
      if (fresh) {
        this.staleTip = '';
      } else {
        const st: string = AppStorage.get('loginStatus') as string ?? '';
        this.staleTip = st === 'expired' ? '登录已过期，已显示缓存数据' : '网络异常，已显示缓存数据';
      }
    } catch (e) {
      const msg = (e as Error).message || '';
      // 用 MainPage 同步到 AppStorage 的 loginStatus 准确判断是否登录过期，
      // 不再依赖脆弱的「未登录」字符串匹配（NETSTACK 401 报错里不含该词）。
      const st: string = AppStorage.get('loginStatus') as string ?? '';
      const expired: boolean = st === 'expired' || msg.includes('未登录');
      this.errorMsg = expired ? '登录已过期，请重新登录' : '加载成绩失败';
    } finally {
      this.loading = false;
    }
  }

  private scoreToGPA(score: string, scoreType: string): string {
    if (scoreType === '五级成绩') {
      const num = parseFloat(score);
      if (!isNaN(num)) {
        if (num >= 90) return '4.0';
        if (num >= 80) return '3.8';
        if (num >= 70) return '3.2';
        if (num >= 60) return '2.4';
        return '0';
      }
      if (score === '优秀') return '4.0';
      if (score === '良好') return '3.8';
      if (score === '中等') return '3.2';
      if (score === '及格') return '2.4';
      return '0';
    }
    if (scoreType === '二级成绩') {
      const num = parseFloat(score);
      if (!isNaN(num)) {
        return num >= 60 ? '3.2' : '0';
      }
      if (score === '通过') return '3.2';
      return '0';
    }
    const num = parseFloat(score);
    if (isNaN(num)) return '0';
    if (num >= 95) return '4.0';
    if (num >= 90) return '3.9';
    if (num >= 84) return '3.8';
    if (num >= 80) return '3.6';
    if (num >= 76) return '3.4';
    if (num >= 73) return '3.2';
    if (num >= 70) return '3.0';
    if (num >= 67) return '2.7';
    if (num >= 64) return '2.4';
    if (num >= 62) return '2.2';
    if (num >= 60) return '2.0';
    return '0';
  }

  private getScoreDisplay(item: ScoreItemModel): string {
    const scoreType = item.djcjlxdmDisplay;
    const zcj = String(item.zcj);
    if (!zcj || zcj === '') return '暂无';

    if (scoreType === '五级成绩') {
      const num = parseFloat(zcj);
      if (!isNaN(num)) {
        if (num >= 90) return '优秀';
        if (num >= 80) return '良好';
        if (num >= 70) return '中等';
        if (num >= 60) return '及格';
        return '不及格';
      }
      return zcj;
    }
    if (scoreType === '二级成绩') {
      const num = parseFloat(zcj);
      if (!isNaN(num)) {
        return num >= 60 ? '通过' : '不通过';
      }
      return zcj;
    }
    return zcj;
  }

  private getScoreColor(score: string): string {
    const s = String(score);
    const num: number = parseFloat(s);
    if (isNaN(num)) {
      if (s === '优秀') return '#2E7D32';
      if (s === '良好') return '#1976D2';
      if (s === '中等') return '#FFB300';
      if (s === '通过') return '#2E7D32';
      if (s === '不通过' || s === '不及格') return '#C62828';
      return '#999999';
    }
    if (num >= 90) return '#2E7D32';
    if (num >= 80) return '#1976D2';
    if (num >= 70) return '#FFB300';
    if (num >= 60) return '#FF7043';
    return '#C62828';
  }

  private getTagLabel(item: ScoreItemModel): string {
    if (item.xgxklbdmDisplay) {
      const parts: string[] = item.xgxklbdmDisplay.split('/');
      return parts[parts.length - 1];
    }
    if (item.kclbdmDisplay) {
      return item.kclbdmDisplay;
    }
    return '';
  }

  private getTagColor(label: string): string {
    if (label.includes('必修') || label.includes('核心') || label.includes('专业')) return '#E3F2FD';
    if (label.includes('选修') || label.includes('任选') || label.includes('通识教育')) return '#FFF3E0';
    if (label.includes('非标') || label.includes('实践') || label.includes('集中')) return '#F3E5F5';
    if (label.includes('限选')) return '#E8F5E9';
    if (label.includes('通识') || label.includes('公共')) return '#E0F7FA';
    if (label.includes('拓展')) return '#FBE9E7';
    return '#F5F5F5';
  }

  private getTagTextColor(label: string): string {
    if (label.includes('必修') || label.includes('核心') || label.includes('专业')) return '#1565C0';
    if (label.includes('选修') || label.includes('任选') || label.includes('通识教育')) return '#BF4D00';
    if (label.includes('非标') || label.includes('实践') || label.includes('集中')) return '#7B1FA2';
    if (label.includes('限选')) return '#2E7D32';
    if (label.includes('通识') || label.includes('公共')) return '#00838F';
    if (label.includes('拓展')) return '#BF360C';
    return '#757575';
  }

  private async showScoreDetail(item: ScoreItemModel): Promise<void> {
    if (!item.jxbid) {
      AlertDialog.show({ message: '该课程暂无成绩构成信息' });
      return;
    }

    const cacheKey = item.jxbid + '_' + item.xnxqdm;
    if (this.detailCache.has(cacheKey)) {
      this.currentDetail = this.detailCache.get(cacheKey)!;
      this.selectedCell = item;
      this.animateShowCard();
      return;
    }

    this.selectedCell = item;
    this.detailLoading = true;
    this.currentDetail = [];
    this.animateShowCard();

    try {
      const details = await ScoreService.getInstance().getScoreDetail(item.jxbid, item.xnxqdm);
      this.currentDetail = details;
      this.detailCache.set(cacheKey, details);
    } catch (e) {
      AlertDialog.show({ message: '获取成绩构成失败' });
    } finally {
      this.detailLoading = false;
    }
  }

  // 优化：背景遮罩和弹窗同步动画，增强层次感
  private animateShowCard(): void {
    this.cardScale = 0.85;
    this.cardOpacity = 0;
    this.maskOpacity = 0;
    animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, () => {
      this.cardScale = 1;
      this.cardOpacity = 1;
      this.maskOpacity = 0.7; // 背景变暗到70%透明度，凸显弹窗
    });
  }

  private hideScoreDetail(): void {
    animateTo({ duration: 180, curve: Curve.EaseIn, onFinish: () => {
      this.selectedCell = null;
    }}, () => {
      this.cardScale = 0.85;
      this.cardOpacity = 0;
      this.maskOpacity = 0; // 背景恢复透明
    });
  }

  // ===== GPA 计算 =====
  private ignoreCourse(name: string, type: string): boolean {
    const kw: string[] = ['军事', '形势与政策', '创业基础', '新生', '写作与沟通', '学科导论', '心理', '物理实验'];
    for (const k of kw) { if (name.indexOf(k) >= 0) return true; }
    const tp: string[] = ['通识教育选修课', '集中实践环节', '拓展提高', '通识教育核心课', '专业选修课'];
    for (const t of tp) { if (type.indexOf(t) >= 0) return true; }
    if (name.indexOf('国家英语四级') >= 0 || name.indexOf('国家英语六级') >= 0) return true;
    return false;
  }

  private scoreToGPANum(zcj: string, typeDisplay: string): number {
    const num = parseFloat(zcj);
    if (isNaN(num)) return -1;
    if (typeDisplay === '五级成绩') {
      if (num >= 90) return 4.0;
      if (num >= 80) return 3.8;
      if (num >= 70) return 3.2;
      if (num >= 60) return 2.4;
      return 0;
    }
    if (typeDisplay === '二级成绩') {
      return num >= 60 ? 3.2 : 0;
    }
    if (num >= 95) return 4.0;
    if (num >= 90) return 3.9;
    if (num >= 84) return 3.8;
    if (num >= 80) return 3.6;
    if (num >= 76) return 3.4;
    if (num >= 73) return 3.2;
    if (num >= 70) return 3.0;
    if (num >= 67) return 2.7;
    if (num >= 64) return 2.4;
    if (num >= 62) return 2.2;
    if (num >= 60) return 2.0;
    return 0;
  }

  private calcGPA(): void {
    let totalCredits = 0;
    let weightedSum = 0;
    let totalScore = 0;
    let count = 0;
    for (const item of this.currentScores) {
      if (!item.zcj || item.zcj.length === 0) continue;
      if (this.ignoreCourse(item.xskcm, item.xgxklbdmDisplay)) continue;
      const gpa = this.scoreToGPANum(item.zcj, item.djcjlxdmDisplay);
      if (gpa < 0) continue;
      const credit = parseFloat(item.xf) || 0;
      totalCredits += credit;
      weightedSum += gpa * credit;
      const sc = parseFloat(item.zcj);
      if (!isNaN(sc)) { totalScore += sc; count++; }
    }
    this.totalGPA = totalCredits > 0 ? (weightedSum / totalCredits).toFixed(3) : '--';
    this.totalAvg = count > 0 ? (totalScore / count).toFixed(1) : '--';
    this.totalCredits = totalCredits.toFixed(1);
  }

  private applyFilter(): void {
    let list = this.allScores.filter((it: ScoreItemModel) =>
      (this.selectedSemester === '__all__' || it.xnxqdm === this.selectedSemester)
    );
    if (this.selectedType !== '__all__') {
      const filtered: ScoreItemModel[] = [];
      for (const item of list) {
        if (this.getTagLabel(item) === this.selectedType) filtered.push(item);
      }
      list = filtered;
    }
    if (this.searchWord.length > 0) {
      const q = this.searchWord;
      const filtered: ScoreItemModel[] = [];
      for (const item of list) {
        if (item.xskcm.indexOf(q) >= 0) filtered.push(item);
      }
      list = filtered;
    }
    this.currentScores = list;
    this.calcGPA();
  }

  // ===== 选择模式计算 =====
  private toggleSelectMode(): void {
    this.isSelectMode = !this.isSelectMode;
    if (this.isSelectMode) {
      this.selectedIndexes.clear();
      this.calcSelected();
    } else {
      this.selectedIndexes.clear();
    }
  }

  private calcSelected(): void {
    if (this.selectedIndexes.size === 0) {
      this.selectedGPA = '--';
      this.selectedAvg = '--';
      this.selectedCredit = '0';
      return;
    }
    let totalCredits = 0;
    let weightedGPA = 0;
    let weightedScore = 0;
    let scoreCount = 0;
    for (let i = 0; i < this.currentScores.length; i++) {
      if (!this.selectedIndexes.has(i)) continue;
      const item = this.currentScores[i];
      if (!item.zcj || item.zcj.length === 0) continue;
      if (!this.evalCount(item)) continue;
      const gpa = this.scoreToGPANum(item.zcj, item.djcjlxdmDisplay);
      if (gpa < 0) continue;
      const credit = parseFloat(item.xf) || 0;
      totalCredits += credit;
      weightedGPA += gpa * credit;
      const sc = parseFloat(item.zcj);
      if (!isNaN(sc)) {
        weightedScore += sc * credit;
        scoreCount++;
      }
    }
    this.selectedGPA = totalCredits > 0 ? (weightedGPA / totalCredits).toFixed(3) : '--';
    this.selectedAvg = weightedScore > 0 && totalCredits > 0 ? (weightedScore / totalCredits).toFixed(1) : '--';
    this.selectedCredit = totalCredits.toFixed(1);
  }

  // 参考 Flutter _evalCount：排除四六级、未完成、非初修挂科等
  private evalCount(item: ScoreItemModel): boolean {
    if (item.xskcm.indexOf('国家英语四级') >= 0 || item.xskcm.indexOf('国家英语六级') >= 0) return false;
    if (!item.zcj || item.zcj.length === 0) return false;
    if (item.sfjg && item.sfjg === '0' && item.cxckdmDisplay !== '初修' && item.cxckdmDisplay) return false;
    return true;
  }

  // 统计当前视图下可通过 ignoreCourse 过滤的课程数量
  private countFilterable(): number {
    let count = 0;
    for (let i = 0; i < this.currentScores.length; i++) {
      if (!this.ignoreCourse(this.currentScores[i].xskcm, this.currentScores[i].xgxklbdmDisplay)) {
        count++;
      }
    }
    return count;
  }

  @Builder
  semesterMenuBuilder() {
    Menu() {
      MenuItem({ content: '全部学期' })
        .selected(this.selectedSemester === '__all__')
        .hoverEffect(HoverEffect.Auto).onClick(() => { this.selectedSemester = '__all__'; this.applyFilter(); })
      ForEach(this.semesterCodes, (code: string) => {
        MenuItem({ content: SemesterUtil.formatSemester(code) })
          .selected(code === this.selectedSemester)
          .hoverEffect(HoverEffect.Auto).onClick(() => { this.selectedSemester = code; this.applyFilter(); })
      })
    }
  }

  @Builder
  typeMenuBuilder() {
    Menu() {
      MenuItem({ content: '全部类型' })
        .selected(this.selectedType === '__all__')
        .hoverEffect(HoverEffect.Auto).onClick(() => { this.selectedType = '__all__'; this.applyFilter(); })
      ForEach(this.typeOptions, (t: string) => {
        MenuItem({ content: t })
          .selected(t === this.selectedType)
          .hoverEffect(HoverEffect.Auto).onClick(() => { this.selectedType = t; this.applyFilter(); })
      })
    }
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {

          // ===== 顶部固定区域（始终显示） =====
          Column() {
            // 第一行：学期 + 类型
            Row({ space: 8 }) {
              Button() {
                Row() {
                  Text(this.selectedSemester === '__all__' ? '全部学期' : SemesterUtil.formatSemester(this.selectedSemester))
                    .fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.accentColor)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(' ▾').fontSize(12).fontColor(this.accentColor)
                }
              }
              .height(40).layoutWeight(1).borderRadius(20)
              .backgroundColor(this.themeIsDark ? '#16263D' : '#EEF3FF')
              .border({ width: 0, color: Color.Transparent })
              .bindMenu(this.semesterMenuBuilder, menuOptions())

              Button() {
                Row() {
                  Text(this.selectedType === '__all__' ? '全部类型' : this.selectedType)
                    .fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.accentColor)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .constraintSize({ maxWidth: 90 })
                  Text(' ▾').fontSize(12).fontColor(this.accentColor)
                }
              }
              .height(40).layoutWeight(1).borderRadius(20)
              .backgroundColor(this.themeIsDark ? '#16263D' : '#EEF3FF')
              .border({ width: 0, color: Color.Transparent })
              .bindMenu(this.typeMenuBuilder, menuOptions())
            }
            .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 4 })

            // 第二行：搜索框（始终显示）
            Row({ space: 8 }) {
              TextInput({ placeholder: '搜索课程名称', text: this.searchWord })
                .fontSize(13).layoutWeight(1).height(34)
                .backgroundColor(ThemeColors.bgInput).borderRadius(8)
                .onChange((v: string) => { this.searchWord = v; this.applyFilter(); })
                .onSubmit(() => { this.applyFilter(); })

              Button('搜索')
                .fontSize(13).fontColor('#FFFFFF')
                .height(34).borderRadius(8)
                .backgroundColor(this.accentColor)
                .hoverEffect(HoverEffect.Auto).onClick(() => { this.applyFilter(); })
            }
            .width('100%').padding({ left: 12, right: 12, top: 4, bottom: 4 })

            // 第三行：GPA 统计（始终显示，无数据时显示 --）
            Row() {
              Row({ space: 0 }) {
                // GPA
                Column() {
                  Text(this.totalGPA || '--').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#2E7D32')
                  Text('GPA').fontSize(10).fontColor(ThemeColors.textHint)
                }.alignItems(HorizontalAlign.Center).margin({ right: 20 })

                Column().width(1).height(30).backgroundColor(ThemeColors.border)

                // 均分
                Column() {
                  Text(this.totalAvg || '--').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#1976D2')
                  Text('均分').fontSize(10).fontColor(ThemeColors.textHint)
                }.alignItems(HorizontalAlign.Center).margin({ left: 20, right: 20 })

                Column().width(1).height(30).backgroundColor(ThemeColors.border)

                // 学分
                Column() {
                  Text(this.totalCredits || '--').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#BF4D00')
                  Text('学分').fontSize(10).fontColor(ThemeColors.textHint)
                }.alignItems(HorizontalAlign.Center).margin({ left: 20 })
              }
              Blank()
              Text(this.currentScores.length + '门课程')
                .fontSize(11).fontColor(ThemeColors.textSecondary)
            }
            .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 })
          }
          .backgroundColor(ThemeColors.bgCard)

          // 离线/过期缓存提示条：显示缓存数据的同时允许用户主动「重试」
          if (this.staleTip.length > 0) {
            Row() {
              Text('📦 ' + this.staleTip)
                .fontSize(12).fontColor('#BF4D00').layoutWeight(1)
              Text('重试')
                .fontSize(12).fontColor(this.accentColor)
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .border({ width: 1, color: this.accentColor, radius: 4 })
                .hoverEffect(HoverEffect.Auto).onClick(() => { this.loadScores(); })
            }
            .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor(ThemeColors.isDark ? '#3A2A12' : '#FFF3E0')
          }

          Divider().color(ThemeColors.border)

          // ===== 列表区域 =====
          if (this.loading) {
            Column() {
              LoadingProgress().width(36).height(36).color(this.accentColor)
              Text('加载中...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
            }
            .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
          } else if (this.errorMsg.length > 0) {
            Column() {
              Text('⚠').fontSize(40).fontColor(ThemeColors.textHint)
              Text(this.errorMsg).fontSize(14).fontColor(ThemeColors.error).margin({ top: 8 })
              Button('重试').margin({ top: 12 }).hoverEffect(HoverEffect.Auto).onClick(() => { this.loadScores(); })
            }
            .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
          } else if (this.currentScores.length === 0) {
            Column() {
              Text('未找到匹配的课程').fontSize(14).fontColor(ThemeColors.textSecondary)
              if (this.searchWord.length > 0) {
                Text('换个关键词试试').fontSize(12).fontColor(ThemeColors.textHint).margin({ top: 4 })
              }
            }
            .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
          } else {
            Grid() {
              ForEach(this.currentScores, (item: ScoreItemModel, idx?: number) => {
                GridItem() {
                  Row() {
                    // 选择模式勾选圈
                    if (this.isSelectMode) {
                      Column()
                        .width(20).height(20).borderRadius(10)
                        .border({ width: 1.5, color: this.selectedIndexes.has(idx!) ? this.accentColor : '#CCCCCC' })
                        .backgroundColor(this.selectedIndexes.has(idx!) ? this.accentColor : '#00000000')
                        .margin({ right: 10 })
                    }

                    // 左侧竖线
                    Column()
                      .width(3).height(40).borderRadius(1.5)
                      .backgroundColor(item.zcj ? this.getScoreColor(item.zcj) : ThemeColors.border)
                      .margin({ right: 12 })

                    // 科目名 + 标签
                    Column({ space: 5 }) {
                      Text(item.xskcm)
                        .fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Row({ space: 4 }) {
                        if (this.getTagLabel(item)) {
                          Text(this.getTagLabel(item))
                            .fontSize(9).fontColor(this.getTagTextColor(this.getTagLabel(item)))
                            .backgroundColor(this.getTagColor(this.getTagLabel(item)))
                            .borderRadius(2).padding({ left: 4, right: 4, top: 1, bottom: 1 })
                        }
                        if (item.cxckdmDisplay && item.cxckdmDisplay !== '初修') {
                          Text(item.cxckdmDisplay)
                            .fontSize(9).fontColor(ThemeColors.error)
                            .backgroundColor(ThemeColors.isDark ? '#3E1A1A' : '#FFEBEE')
                            .borderRadius(2).padding({ left: 4, right: 4, top: 1, bottom: 1 })
                        }
                        if (item.xf) {
                          Text(item.xf + '学分')
                            .fontSize(10).fontColor(ThemeColors.textSecondary)
                        }
                      }
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)

                    // 右侧分数
                    Column() {
                      Text(this.getScoreDisplay(item))
                        .fontSize(20).fontWeight(FontWeight.Bold)
                        .fontColor(this.getScoreColor(item.zcj))
                      if (item.zcj) {
                        Text('绩点 ' + this.scoreToGPA(item.zcj, item.djcjlxdmDisplay))
                          .fontSize(11).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
                      }
                    }.alignItems(HorizontalAlign.End).justifyContent(FlexAlign.Center).width(60)
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 14, bottom: 14 })
                  .alignItems(VerticalAlign.Center)
                  .backgroundColor(this.isSelectMode && this.selectedIndexes.has(idx!) ?
                    (this.themeIsDark ? '#1A2A40' : '#F0F5FF') : ThemeColors.bgCard)
                  .borderRadius(12)
                  .hoverEffect(HoverEffect.Auto).onClick(() => {
                    if (this.isSelectMode) {
                      if (this.selectedIndexes.has(idx!)) {
                        this.selectedIndexes.delete(idx!);
                      } else {
                        this.selectedIndexes.add(idx!);
                      }
                      this.calcSelected();
                    } else {
                      this.showScoreDetail(item);
                    }
                  })
                  .animation({ duration: 150, curve: Curve.EaseOut })
                }
              }, (item: ScoreItemModel) => 'score_' + (item.jxbid || (item.xnxqdm + '_' + item.xskcm)))
            }
            .columnsGap(12).rowsGap(12)
            .columnsTemplate('1fr '.repeat(this.getScoreColumns()).trim())
            .layoutWeight(1)
            .padding({ left: 0, right: 0, top: 10, bottom: 16 })
            .margin({ bottom: this.isSelectMode ? 64 : 0 })
            .edgeEffect(EdgeEffect.Spring)
          }
        }
        .width('100%').height('100%').backgroundColor(ThemeColors.bgPage)
        .zIndex(0)

        // 悬浮计算按钮（单按钮 + translate 滑动动画）
        if (!this.detailLoading && this.selectedCell === null) {
          Stack({ alignContent: Alignment.BottomEnd }) {
            Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
              Image($r('app.media.calculator_1'))
                .width(26).height(26)
                .fillColor(this.themeIsDark ? '#FFFFFF' : '#333333')
            }
            .width(48).height(48)
            .borderRadius(999)
            .backdropBlur(18)
            .backgroundColor(this.themeIsDark ? 'rgba(40,40,45,0.35)' : 'rgba(255,255,255,0.15)')
            .border({ width: 1, color: 'rgba(255,255,255,0.30)' })
            .shadow({ radius: 10, color: 'rgba(0,0,0,0.12)', offsetX: 0, offsetY: 4 })
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.toggleSelectMode(); })
            .margin({ bottom: 80, right: 16 })
            .translate({ x: this.fabTranslateX })
          }
          .width('100%').height('100%')
          .hitTestBehavior(HitTestMode.Transparent)
          .zIndex(1)
          .onAreaChange((oldVal, newVal) => {
            const w = newVal.width as number;
            if (w > 0) this.screenWidth = w;
            if (!this.fabInitialized) {
              this.fabInitialized = true;
              // 默认右手模式在右侧，translateX=0；左手模式滑到左侧
              // 滑动距离 = 屏幕宽 - 按钮宽48 - 右边距16 - 左边距16 = screenWidth - 80
              this.fabTranslateX = this.isLeftHand ? -(this.screenWidth - 80) : 0;
            }
          })
        }

        // 底部计算栏（选择模式下）
        if (this.isSelectMode) {
          Column() {
            Blank()
            Row() {
              // 操作按钮区域
              Row({ space: 8 }) {
                Button() {
                  Row({ space: 4 }) {
                    Text('智能勾选')
                      .fontSize(13).fontColor(this.accentColor)
                    if (this.selectedIndexes.size === this.countFilterable() && this.selectedIndexes.size > 0) {
                      Text('✓')
                        .fontSize(12).fontColor(this.accentColor)
                    }
                  }
                }
                .backgroundColor(Color.Transparent)
                .height(36).border({ width: 1, color: this.accentColor, radius: 18 })
                .padding({ left: 14, right: 14 })
                .hoverEffect(HoverEffect.Auto).onClick(() => {
                  this.selectedIndexes.clear();
                  for (let i = 0; i < this.currentScores.length; i++) {
                    if (this.ignoreCourse(this.currentScores[i].xskcm, this.currentScores[i].xgxklbdmDisplay)) continue;
                    this.selectedIndexes.add(i);
                  }
                  this.calcSelected();
                })

                Button('重置')
                  .fontSize(13).fontColor(ThemeColors.textSecondary)
                  .backgroundColor(Color.Transparent)
                  .height(36).border({ width: 1, color: '#CCCCCC', radius: 18 })
                  .padding({ left: 14, right: 14 })
                  .hoverEffect(HoverEffect.Auto).onClick(() => {
                    this.selectedIndexes.clear();
                    this.calcSelected();
                  })
              }

              Blank()

              // 计算结果区域
              Row({ space: 6 }) {
                Text(this.selectedGPA)
                  .fontSize(16).fontWeight(FontWeight.Bold).fontColor('#4CAF50')
                Text('GPA')
                  .fontSize(10).fontColor(ThemeColors.textHint)
                  .margin({ right: 4 })
                Text(this.selectedAvg)
                  .fontSize(16).fontWeight(FontWeight.Bold).fontColor('#1976D2')
                Text('均分')
                  .fontSize(10).fontColor(ThemeColors.textHint)
                  .margin({ right: 4 })
                Text(this.selectedCredit)
                  .fontSize(16).fontWeight(FontWeight.Bold).fontColor('#BF4D00')
                Text('学分')
                  .fontSize(10).fontColor(ThemeColors.textHint)
              }
            }
            .width('100%')
            .height(60)
            .padding({ left: 16, right: 16 })
            .backgroundColor(ThemeColors.bgCard)
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .border({ width: { top: 0.5 }, color: '#E8E8E8' })
            .shadow({ radius: 8, color: '#00000010', offsetX: 0, offsetY: -2 })
          }
          .width('100%').height('100%')
          .zIndex(2)
          .hitTestBehavior(HitTestMode.Transparent)
          .animation({ duration: 250, curve: Curve.FastOutSlowIn })
        }

        // 第三层：半透明背景遮罩（中间层）
        if (this.selectedCell !== null) {
          Column()
            .width('100%').height('100%')
            .backgroundColor('rgba(0,0,0,0.7)') // 加深背景透明度，增强层次感
            .opacity(this.maskOpacity)
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.hideScoreDetail(); })
            .zIndex(3) // 遮罩在主页面之上
        }

        // 第三层：成绩构成详情弹窗（最顶层）
        if (this.selectedCell !== null) {
          Column() {
            // 顶部色条（用成绩颜色）
            Row().width('100%').height(4)
              .backgroundColor(this.getScoreColor(this.selectedCell.zcj))
              .borderRadius({ topLeft: 12, topRight: 12 })

            // 课程名
            Text(this.selectedCell.xskcm)
              .fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              .margin({ top: 16, bottom: 12 }).width('100%')

            Divider().color('#F0F0F0')

            // 成绩+绩点概览
            Row() {
              Column() {
                Text('成绩').fontSize(12).fontColor(ThemeColors.textSecondary)
                Text(this.getScoreDisplay(this.selectedCell))
                  .fontSize(24).fontWeight(FontWeight.Bold)
                  .fontColor(this.getScoreColor(this.selectedCell.zcj))
                  .margin({ top: 4 })
              }.alignItems(HorizontalAlign.Start)

              Blank()

              Column() {
                Text('绩点').fontSize(12).fontColor(ThemeColors.textSecondary)
                Text(this.scoreToGPA(this.selectedCell.zcj, this.selectedCell.djcjlxdmDisplay))
                  .fontSize(24).fontWeight(FontWeight.Bold)
                  .fontColor('#1976D2')
                  .margin({ top: 4 })
              }.alignItems(HorizontalAlign.End)
            }
            .width('100%')
            .padding({ top: 12, bottom: 12 })

            Divider().color('#F0F0F0')

            // 成绩构成详情列表
            if (this.detailLoading) {
              Column() {
                LoadingProgress().width(32).height(32).color(this.accentColor)
                  .margin({ top: 20, bottom: 20 })
              }.width('100%')
            } else if (this.currentDetail.length === 0) {
              Column() {
                Text('暂无成绩构成信息')
                  .fontSize(14).fontColor(ThemeColors.textSecondary)
                  .margin({ top: 20, bottom: 20 })
              }.width('100%')
            } else {
              Column({ space: 10 }) {
                ForEach(this.currentDetail, (detail: ComposeDetail) => {
                  Row() {
                    Text(detail.content)
                      .fontSize(14).fontColor(ThemeColors.textPrimary)
                      .layoutWeight(1)
                    Text(detail.ratio)
                      .fontSize(14).fontColor(ThemeColors.textSecondary)
                      .margin({ right: 16 })
                    Text(detail.score)
                      .fontSize(14).fontWeight(FontWeight.Medium)
                      .fontColor(this.getScoreColor(detail.score))
                      .width(60).textAlign(TextAlign.End)
                  }
                  .width('100%')
                }, (detail: ComposeDetail) => detail.content)
              }
              .width('100%')
              .margin({ top: 12 })
            }
          }
          .width('75%')
          .padding({ left: 20, right: 20, bottom: 20 })
          .backgroundColor(ThemeColors.bgInput)
          .borderRadius(12)
          .shadow({
            radius: 24,
            color: 'rgba(0,0,0,0.25)',
            offsetY: 10
          })
          .scale({ x: this.cardScale, y: this.cardScale })
          .opacity(this.cardOpacity)
          .zIndex(4) // 弹窗在最顶层
        }
      }
      .width('100%')
      .height('100%')
    }
    .title({ builder: this.buildWhiteTitle('成绩查询'), height: 52 + this.statusBarHeight }, { backgroundColor: this.accentColor })
    .hideBackButton(true).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .backgroundColor(ThemeColors.bgPage)
    .onReady((ctx: NavDestinationContext) => {})
    .onBackPressed(() => {
      if (this.selectedCell !== null) {
        this.selectedCell = null;
        this.cardScale = 0.85;
        return true;
      }
      if (this.isSelectMode) {
        this.isSelectMode = false;
        this.selectedIndexes.clear();
        return true;
      }
      return false;
    })
  }}
