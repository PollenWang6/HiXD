// PreferenceUtil.ets — 基于 @ohos.data.preferences 的持久化存储 + 内存缓存
import dataPreferences from '@ohos.data.preferences';
import { Context } from '@kit.AbilityKit';
import web from '@ohos.web.webview';
import { HttpUtil } from './HttpUtil';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

type ValueType = string | number | boolean;

const TAG = 'PreferenceUtil';
const STORE_NAME = 'hixd_prefs';

let prefsInstance: dataPreferences.Preferences | null = null;
let sFilesDir: string = '';  // 共享文件目录（主应用/卡片进程均可访问）

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
      sFilesDir = context.filesDir;
      console.info(TAG, 'Preferences initialized, filesDir=' + sFilesDir);
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
        (prefs.put(key, value as ValueType) as Promise<void>).then(() => prefs.flush()).catch(() => { console.warn("PreferenceUtil", "flush failed"); });
      } catch (_) { console.warn("PreferenceUtil", "ignored error"); }
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
      } catch (_) { console.warn("PreferenceUtil", "ignored error"); }
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

  // 共享文件读写（主应用/卡片进程都可通过 filesDir 访问同一文件）
  // 用于绕过 Preferences 的跨进程隔离
  static saveSharedFile(filename: string, content: string): void {
    console.error(TAG, '[DIAG-SAVE] sFilesDir="' + sFilesDir + '" len=' + sFilesDir.length);
    if (sFilesDir.length === 0) {
      console.warn(TAG, 'saveSharedFile: filesDir not initialized');
      return;
    }
    try {
      const path: string = sFilesDir + '/' + filename + '.json';
      console.error(TAG, '[DIAG-SAVE] writing to: ' + path + ' contentLen=' + content.length);
      const encoder = new util.TextEncoder();
      const encoded: Uint8Array = encoder.encodeInto(content);
      const file: fileIo.File = fileIo.openSync(path,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
      fileIo.writeSync(file.fd, encoded.buffer);
      fileIo.closeSync(file);
      console.error(TAG, '[DIAG-SAVE] SUCCESS: ' + filename + ' written (' + content.length + ' chars)');
    } catch (e) {
      console.error(TAG, '[DIAG-SAVE] FAIL: ' + JSON.stringify(e));
    }
  }

  static readSharedFile(filename: string, filesDir: string = ''): string {
    const dir: string = filesDir.length > 0 ? filesDir : sFilesDir;
    console.error(TAG, '[DIAG-READ] filesDir="' + filesDir + '" sFilesDir="' + sFilesDir + '" useDir="' + dir + '"');
    if (dir.length === 0) {
      console.error(TAG, '[DIAG-READ] FAIL: no dir');
      return '';
    }
    try {
      const path: string = dir + '/' + filename + '.json';
      console.error(TAG, '[DIAG-READ] trying path: ' + path);
      const file: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(path);
      console.error(TAG, '[DIAG-READ] file opened, size=' + stat.size);
      const buf = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file);
      const decoder = util.TextDecoder.create('utf-8');
      const result: string = decoder.decodeToString(new Uint8Array(buf));
      console.error(TAG, '[DIAG-READ] SUCCESS, rawLen=' + result.length + ' first80=' + result.substring(0, 80));
      // strip BOM if present
      if (result.length > 0 && result.charCodeAt(0) === 0xFEFF) {
        console.error(TAG, '[DIAG-READ] BOM detected, stripping');
        return result.substring(1);
      }
      return result;
    } catch (e) {
      console.error(TAG, '[DIAG-READ] FAIL: ' + JSON.stringify(e));
      return '';
    }
  }
}