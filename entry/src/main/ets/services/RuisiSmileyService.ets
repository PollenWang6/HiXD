// RuisiSmileyService.ets — 论坛内置表情（Discuz smiley）缓存与分组
// 对标 Flutter/iOS 的表情面板：表情来自论坛 api/mobile/index.php?version=4&module=smiley，
// 每个表情是图片 + 短码 {:分类_编号:}，按分类目录分组展示。

import { RuisiApiService } from './RuisiApiService';
import { Smiley, SmileyCategory } from './RuisiModels';
import { LOCAL_SMILIES } from './SmileyLocalData';

export class RuisiSmileyService {
  private static instance: RuisiSmileyService | null = null;

  static getInstance(): RuisiSmileyService {
    if (!RuisiSmileyService.instance) {
      RuisiSmileyService.instance = new RuisiSmileyService();
    }
    return RuisiSmileyService.instance;
  }

  private smilies: Smiley[] = [];
  private byCategory: Map<string, Smiley[]> = new Map();
  private loaded: boolean = false;
  private loading: boolean = false;

  /** 加载并缓存表情（离线：直接分组本地快照 LOCAL_SMILIES，零网络，秒开） */
  async ensureLoaded(): Promise<void> {
    if (this.loaded) return;
    const list: Smiley[] = LOCAL_SMILIES.map((s) => {
      const sm = new Smiley();
      sm.code = s.code;
      sm.url = s.image;        // rawfile 相对路径，如 'smiley/yct/35.gif'
      sm.category = s.category;
      return sm;
    });
    this.smilies = list;
    this.byCategory.clear();
    for (const s of list) {
      if (!this.byCategory.has(s.category)) {
        this.byCategory.set(s.category, []);
      }
      this.byCategory.get(s.category)!.push(s);
    }
    this.loaded = true;
  }

  getCategories(): string[] {
    return Array.from(this.byCategory.keys());
  }

  getSmilies(category: string): Smiley[] {
    return this.byCategory.get(category) ?? [];
  }

  /**
   * 分类英文文件夹名 → 中文显示名。
   * 论坛接口只返回英文文件夹名（如 yct/tieba/ali），不返回中文，这里自行维护映射。
   * 下面带 * 的是较有把握的（知名表情包），其余为按原意/音译的最佳猜测，可随时改。
   */
  private static CATEGORY_NAMES: Record<string, string> = {
    'yct': '默认表情',        // *
    'qq': 'QQ表情',           // *
    'tieba': '贴吧表情',      // *
    'ali': '阿狸',            // * 知名漫画形象
    'luoxiaohei': '罗小黑',   // * 知名动画形象
    'acn': 'AC娘',
    'bomb': '暴漫',
    'coolmonkey': '酷猴',
    'jgz': '果珍',
    'lindab': '琳达',
    'milk': '牛奶',
    'qiubilong': '丘比龙',
  };

  /** 分类列表（含中文显示名），用于面板 tab 展示；顺序与接口返回一致 */
  getCategoryList(): SmileyCategory[] {
    const list: SmileyCategory[] = [];
    for (const key of this.byCategory.keys()) {
      list.push({ key, name: RuisiSmileyService.CATEGORY_NAMES[key] ?? key });
    }
    return list;
  }

  isLoaded(): boolean {
    return this.loaded;
  }
}
