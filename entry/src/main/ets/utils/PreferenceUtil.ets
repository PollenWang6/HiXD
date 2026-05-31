// PreferenceUtil.ets — 基于 @ohos.data.preferences 的持久化存储 + 内存缓存
import dataPreferences from '@ohos.data.preferences';
import { Context } from '@kit.AbilityKit';
import web from '@ohos.web.webview';
import { HttpUtil } from './HttpUtil';

type ValueType = string | number | boolean;

const TAG = 'PreferenceUtil';
const STORE_NAME = 'hixd_prefs';

let prefsInstance: dataPreferences.Preferences | null = null;

// 内存缓存：在 prefs 还没 init 时，put 的值先存在这里
const inMemoryCache: Map<string, string | boolean | number> = new Map();

interface CookieEntry {
  name: string;
  value: string;
  domain: string;
  path: string;
}

export class PreferenceUtil {
  static async init(context: Context): Promise<void> {
    try {
      prefsInstance = await dataPreferences.getPreferences(context, STORE_NAME);
      console.info(TAG, 'Preferences initialized');
      await HttpUtil.getInstance().loadCookies();
      console.info(TAG, 'HttpUtil cookies loaded from storage');
      await PreferenceUtil.syncCookiesToWeb();
    } catch (e) {
      console.error(TAG, 'Failed to init preferences: ' + JSON.stringify(e));
    }
  }

  private static async syncCookiesToWeb(): Promise<void> {
    try {
      const raw: string = PreferenceUtil.getString('http_cookies');
      if (raw.length === 0) return;
      const entries: CookieEntry[] = JSON.parse(raw) as CookieEntry[];
      for (const entry of entries) {
        try {
          const fullCookie: string = entry.name + '=' + entry.value + '; path=' + (entry.path || '/');
          await web.WebCookieManager.setCookie(entry.domain, fullCookie);
        } catch (e2) {
          console.warn(TAG, 'Failed to sync cookie ' + entry.name + ': ' + JSON.stringify(e2));
        }
      }
    } catch (e) {
      console.warn(TAG, 'Failed to sync cookies: ' + JSON.stringify(e));
    }
  }

  private static getPrefs(): dataPreferences.Preferences | null {
    return prefsInstance;
  }

  // 内部方法：统一写内存缓存 + 持久化
  private static _put(key: string, value: string | boolean | number): void {
    inMemoryCache.set(key, value);
    const prefs = PreferenceUtil.getPrefs();
    if (prefs) {
      try {
        (prefs.put(key, value as ValueType) as Promise<void>).then(() => prefs.flush()).catch(() => {});
      } catch (_) {}
    }
  }

  // 内部方法：统一读内存缓存 + 持久化
  private static _get<T>(key: string, defaultValue: T): T {
    if (inMemoryCache.has(key)) {
      return inMemoryCache.get(key) as T;
    }
    const prefs = PreferenceUtil.getPrefs();
    if (prefs) {
      try {
        const val = prefs.getSync(key, defaultValue as ValueType);
        if (val !== defaultValue) {
          // 同步到内存缓存
          inMemoryCache.set(key, val as string | boolean | number);
        }
        return val as T;
      } catch (_) {}
    }
    return defaultValue;
  }

  static async putString(key: string, value: string): Promise<void> {
    PreferenceUtil._put(key, value);
  }

  static getString(key: string, defaultValue: string = ''): string {
    return PreferenceUtil._get(key, defaultValue);
  }

  static async putBool(key: string, value: boolean): Promise<void> {
    PreferenceUtil._put(key, value);
  }

  static getBool(key: string, defaultValue: boolean = false): boolean {
    return PreferenceUtil._get(key, defaultValue);
  }

  static async putNumber(key: string, value: number): Promise<void> {
    PreferenceUtil._put(key, value);
  }

  static getNumber(key: string, defaultValue: number = 0): number {
    return PreferenceUtil._get(key, defaultValue);
  }

  static async delete(key: string): Promise<void> {
    inMemoryCache.delete(key);
    const prefs = PreferenceUtil.getPrefs();
    if (prefs) {
      try {
        await prefs.delete(key);
        await prefs.flush();
      } catch (e) {
        console.error(TAG, 'delete failed: ' + JSON.stringify(e));
      }
    }
  }

  static async has(key: string): Promise<boolean> {
    if (inMemoryCache.has(key)) return true;
    const prefs = PreferenceUtil.getPrefs();
    if (prefs) {
      try {
        return await prefs.has(key);
      } catch (e) {
        return false;
      }
    }
    return false;
  }
}