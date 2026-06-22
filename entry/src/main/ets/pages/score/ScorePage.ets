// ScorePage.ets — 成绩查询（含成绩构成详情，增强层次感版）
import { SemesterUtil, ScoreItemModel, ComposeDetail } from '../../services/EhallService';
import { ScoreService } from '../../services/ScoreService';
import { ThemeColors } from '../../utils/ThemeColors';
import { motion } from '@kit.MultimodalAwarenessKit';
import { BusinessError } from '@kit.BasicServicesKit';

@Component
export struct ScorePage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  pageInfo: NavPathStack = new NavPathStack();
  @State loading: boolean = false;
  @State errorMsg: string = '';
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
  @State selectedIndexes: Set<number> = new Set();
  @State isLeftHand: boolean = false;
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
      .onClick(() => { this.pageInfo.pop(); })
      Text(t)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .layoutWeight(1)
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 16 })
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
        this.isLeftHand = (data === 1 || data === 3);
      });
    } catch (err) {
      const e = err as BusinessError;
      if (e.code === 801) {
        console.info('[ScorePage] 智感握持不支持，使用默认右手模式');
      }
      this.isLeftHand = false;
    }
  }

  private async waitAndLoad(): Promise<void> {
    let waited = 0;
    while (waited < 2000) {
      await new Promise<void>((r) => { setTimeout(r, 300); });
      waited += 300;
    }
    console.info('[ScorePage] waitAndLoad done');
    this.loadScores();
  }

  async loadScores(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      const raw: string = await ScoreService.getInstance().getScores('');
      const items: ScoreItemModel[] = ScoreService.parseScores(raw);
      console.info('[ScorePage] parsed ' + items.length + ' items');

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
    } catch (e) {
      const msg = (e as Error).message || '';
      this.errorMsg = msg.includes('未登录') ? '登录已过期，请重新登录' : '加载成绩失败';
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
      if (s === '优秀') return '#43A047';
      if (s === '良好') return '#1976D2';
      if (s === '中等') return '#FFB300';
      if (s === '通过') return '#43A047';
      if (s === '不通过' || s === '不及格') return '#FF5252';
      return '#999999';
    }
    if (num >= 90) return '#43A047';
    if (num >= 80) return '#1976D2';
    if (num >= 70) return '#FFB300';
    if (num >= 60) return '#FF7043';
    return '#FF5252';
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
    if (label.includes('选修') || label.includes('任选') || label.includes('通识教育')) return '#E65100';
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
        .onClick(() => { this.selectedSemester = '__all__'; this.applyFilter(); })
      ForEach(this.semesterCodes, (code: string) => {
        MenuItem({ content: SemesterUtil.formatSemester(code) })
          .selected(code === this.selectedSemester)
          .onClick(() => { this.selectedSemester = code; this.applyFilter(); })
      })
    }
  }

  @Builder
  typeMenuBuilder() {
    Menu() {
      MenuItem({ content: '全部类型' })
        .selected(this.selectedType === '__all__')
        .onClick(() => { this.selectedType = '__all__'; this.applyFilter(); })
      ForEach(this.typeOptions, (t: string) => {
        MenuItem({ content: t })
          .selected(t === this.selectedType)
          .onClick(() => { this.selectedType = t; this.applyFilter(); })
      })
    }
  }

  build() {
    NavDestination() {
      Stack() {
        // 第一层：主页面内容（最底层）
        Column() {

          // 筛选栏：学期 + 类型 双下拉
          Row({ space: 10 }) {
            // 学期下拉
            Button() {
              Row() {
                Text('学期 ').fontSize(12).fontColor(ThemeColors.textSecondary)
                Text(this.selectedSemester === '__all__' ? '全部' : SemesterUtil.formatSemester(this.selectedSemester))
                  .fontSize(13).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(' ▾').fontSize(10).fontColor(ThemeColors.textHint)
              }
            }
            .height(36).layoutWeight(1).borderRadius(10)
            .backgroundColor(ThemeColors.bgInput)
            .border({ width: 0.5, color: '#E8E8E8' })
            .bindMenu(this.semesterMenuBuilder, { backgroundBlurStyle: BlurStyle.COMPONENT_THICK })

            // 类型下拉
            Button() {
              Row() {
                Text('类型 ').fontSize(12).fontColor(ThemeColors.textSecondary)
                Text(this.selectedType === '__all__' ? '全部' : this.selectedType)
                  .fontSize(13).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: 100 })
                Text(' ▾').fontSize(10).fontColor(ThemeColors.textHint)
              }
            }
            .height(36).layoutWeight(1).borderRadius(10)
            .backgroundColor(ThemeColors.bgInput)
            .border({ width: 0.5, color: '#E8E8E8' })
            .bindMenu(this.typeMenuBuilder, { backgroundBlurStyle: BlurStyle.COMPONENT_THICK })
          }
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .width('100%')
          .backgroundColor(ThemeColors.bgCard)

          Divider().color('#F0F0F0')

          // 搜索框 + GPA 汇总
          Row() {
            Row() {
              Text('\ud83d\udd0d').fontSize(14).margin({ right: 4 })
              TextInput({ placeholder: '搜索课程名...', text: this.searchWord })
                .fontSize(13).layoutWeight(1).height(32).backgroundColor('#00000000')
                .onChange((v: string) => { this.searchWord = v; this.applyFilter(); })
            }.layoutWeight(1).height(32).padding({ left: 8, right: 8 })
            .backgroundColor(ThemeColors.bgInput).borderRadius(16)

            if (this.currentScores.length > 0) {
              Text('GPA ' + this.totalGPA).fontSize(12).fontWeight(FontWeight.Bold).fontColor('#4CAF50')
                .padding({ left: 4, right: 4 })
              Text('|').fontSize(12).fontColor(ThemeColors.textHint)
              Text(this.totalAvg + '分').fontSize(12).fontColor('#1976D2')
                .padding({ left: 4, right: 4 })
              Text('|').fontSize(12).fontColor(ThemeColors.textHint)
              Text(this.totalCredits + '学分').fontSize(12).fontColor('#FF9800')
                .padding({ left: 4, right: 4 })
            }
          }.width('100%').padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .backgroundColor(ThemeColors.bgCard)

          if (this.loading) {
            Column() {
              LoadingProgress().width(40).height(40).color(this.accentColor)
              Text('加载中...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
            }
            .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
          } else if (this.errorMsg.length > 0) {
            Column() {
              Text('⚠️').fontSize(40)
              Text(this.errorMsg).fontSize(14).fontColor(ThemeColors.error).margin({ top: 8 })
              Button('重试').margin({ top: 12 }).onClick(() => { this.loadScores(); })
            }
            .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
          } else {
            List() {
              ForEach(this.currentScores, (item: ScoreItemModel, idx?: number) => {
                ListItem() {
                  Row() {
                    // 选择模式下的勾选圈
                    if (this.isSelectMode) {
                      Column()
                        .width(24).height(24).borderRadius(12)
                        .border({ width: 2, color: this.selectedIndexes.has(idx!) ? '#3B82F6' : '#CCCCCC' })
                        .backgroundColor(this.selectedIndexes.has(idx!) ? '#3B82F6' : '#00000000')
                        .justifyContent(FlexAlign.Center)
                        .margin({ right: 12 })
                    }

                    Column() {
                      Text(item.xskcm)
                        .fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Row({ space: 6 }) {
                        if (this.getTagLabel(item)) {
                          Text(this.getTagLabel(item))
                            .fontSize(10)
                            .fontColor(this.getTagTextColor(this.getTagLabel(item)))
                            .backgroundColor(this.getTagColor(this.getTagLabel(item)))
                            .borderRadius(4)
                            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        }
                        if (item.cxckdmDisplay && item.cxckdmDisplay !== '初修') {
                          Text(item.cxckdmDisplay)
                            .fontSize(10).fontColor(ThemeColors.error)
                            .backgroundColor(ThemeColors.isDark ? '#3E1A1A' : '#FFEBEE').borderRadius(4)
                            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        }
                        if (item.xf) {
                          Text(item.xf + '学分')
                            .fontSize(11).fontColor(ThemeColors.textSecondary)
                        }
                      }.margin({ top: 6 })
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)

                    Column() {
                      Text(this.getScoreDisplay(item))
                        .fontSize(22).fontWeight(FontWeight.Bold)
                        .fontColor(this.getScoreColor(item.zcj))
                      if (item.zcj) {
                        Text('绩点 ' + this.scoreToGPA(item.zcj, item.djcjlxdmDisplay))
                          .fontSize(10).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
                      }
                    }.alignItems(HorizontalAlign.End)
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 14, bottom: 14 })
                  .alignItems(VerticalAlign.Center)
                  .backgroundColor(this.isSelectMode && this.selectedIndexes.has(idx!) ?
                    (this.themeIsDark ? '#1A2A40' : '#F0F5FF') : Color.Transparent)
                  .onClick(() => {
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
              }, (item: ScoreItemModel, idx?: number) => `score_${item.xnxqdm}_${item.xskcm}_${idx}`)
            }
            .divider({ strokeWidth: 0.5, color: '#F5F5F5' })
            .layoutWeight(1)
            // 选择模式下底部留空给计算栏
            .margin({ bottom: this.isSelectMode ? 64 : 0 })
          }
        }
        .width('100%').height('100%').backgroundColor(ThemeColors.bgCard)
        .zIndex(0) // 明确层级：主页面在最底层

        // 悬浮计算按钮
        if (!this.detailLoading && this.selectedCell === null) {
          Column() {
            Blank()
            Row() {
              if (this.isLeftHand) {
                // 左手模式：按钮靠左
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
                .onClick(() => { this.toggleSelectMode(); })
                .margin({ left: 16, bottom: 80 })

                Blank()
              } else {
                // 右手模式：按钮靠右
                Blank()

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
                .onClick(() => { this.toggleSelectMode(); })
                .margin({ right: 16, bottom: 80 })
              }
            }
            .width('100%')
          }
          .width('100%').height('100%')
          .hitTestBehavior(HitTestMode.Transparent)
          .zIndex(1)
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
                .onClick(() => {
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
                  .onClick(() => {
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
                  .fontSize(16).fontWeight(FontWeight.Bold).fontColor('#FF9800')
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
            .onClick(() => { this.hideScoreDetail(); })
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
    .title({ builder: this.buildWhiteTitle('成绩查询'), height: 56 }, { backgroundColor: this.accentColor })
    .hideBackButton(true).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
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