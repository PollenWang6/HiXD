// CacheService.ets — 本地缓存服务
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

const CACHE_TAG = 'CacheService';

interface CacheEntry {
  data: string;
  timestamp: number;
  expiresAt: number;
}

export interface CacheConfig {
  ttl: number;
}

export class CacheService {
  private static instance: CacheService;
  private ready = false;
  private baseDir = '/data/storage/el2/base/haps/hixd_cache';

  private constructor() {}

  static getInstance(): CacheService {
    if (!CacheService.instance) CacheService.instance = new CacheService();
    return CacheService.instance;
  }

  async init(): Promise<void> {
    if (this.ready) return;
    try {
      fileIo.mkdirSync(this.baseDir);
    } catch {
      // 目录可能已存在
    }
    this.ready = true;
  }

  private filePath(key: string): string {
    // 用 UTF-8 字节计算 hash，避免 charCodeAt 对多字节字符产生不一致结果
    const encoder = new util.TextEncoder();
    const bytes: Uint8Array = encoder.encodeInto(key);
    let hash = 0;
    for (let i = 0; i < bytes.length; i++) {
      hash = ((hash << 5) - hash) + bytes[i];
      hash = hash & hash; // 保持 32bit
    }
    const n = hash >= 0 ? hash : -hash;
    return this.baseDir + '/c_' + n.toString(16) + '.json';
  }

  async get(key: string): Promise<string | null> {
    if (!this.ready) return null;
    const path = this.filePath(key);
    try {
      const content: string = fileIo.readTextSync(path);
      const entry: CacheEntry = JSON.parse(content);
      if (Date.now() > entry.expiresAt) {
        // 不删除过期文件，让 getStale() 仍可兜底（离线时过期缓存优于无数据）
        // 文件会在 set() 时被覆盖，或 clear() 时统一清理
        return null;
      }
      return entry.data;
    } catch { return null; }
  }

  // 读取缓存（忽略过期时间），离线时仍可使用过期缓存
  async getStale(key: string): Promise<string | null> {
    if (!this.ready) return null;
    const path = this.filePath(key);
    try {
      const content: string = fileIo.readTextSync(path);
      const entry: CacheEntry = JSON.parse(content);
      // 不过期检查，不删除文件，直接返回数据
      return entry.data;
    } catch { return null; }
  }

  async set(key: string, data: string, ttl: number): Promise<void> {
    if (!this.ready) return;
    const path = this.filePath(key);
    const now = Date.now();
    const entry: CacheEntry = { data, timestamp: now, expiresAt: now + ttl };
    try {
      const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
      const content2 = JSON.stringify(entry);
      // 使用 TextEncoder 正确处理 UTF-8 多字节字符
      const encoder = new util.TextEncoder();
      const encoded = encoder.encodeInto(content2);
      fileIo.writeSync(file.fd, encoded.buffer);
      fileIo.closeSync(file);
    } catch (e) {
    }
  }

  async clear(): Promise<void> {
    try {
      const files: string[] = fileIo.listFileSync(this.baseDir);
      for (const f of files) {
        try { fileIo.unlinkSync(this.baseDir + '/' + f); } catch { /* ignore */ }
      }
    } catch { /* ignore */ }
  }

  async getOrFetch<T>(
    key: string,
    fetchFn: () => Promise<T>,
    ttlMs: number,
    forceRefresh?: boolean
  ): Promise<T> {
    if (!forceRefresh) {
      const cached: string | null = await this.get(key);
      if (cached !== null) {
        try { return JSON.parse(cached) as T; } catch { /* ignore */ }
      }
    }
    try {
      const data: T = await fetchFn();
      try {
        await this.set(key, JSON.stringify(data), ttlMs);
      } catch { /* ignore */ }
      return data;
    } catch (fetchErr) {
      // 网络请求失败，尝试用过期缓存兜底
      const stale: string | null = await this.getStale(key);
      if (stale !== null) {
        try { return JSON.parse(stale) as T; } catch { /* ignore */ }
      }
      throw new Error(String(fetchErr));
    }
  }
}
