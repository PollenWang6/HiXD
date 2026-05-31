// CacheService.ets — 本地缓存服务
import { fileIo } from '@kit.CoreFileKit';

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
    let hash = 0;
    for (let i = 0; i < key.length; i++) {
      hash = ((hash << 5) - hash) + key.charCodeAt(i);
      hash = hash & hash;
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
        try { fileIo.unlinkSync(path); } catch { /* ignore */ }
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
      const buf2 = new ArrayBuffer(content2.length * 2);
      const view = new Uint8Array(buf2);
      for (let i = 0; i < content2.length; i++) view[i] = content2.charCodeAt(i);
      fileIo.writeSync(file.fd, buf2);
      fileIo.closeSync(file);
    } catch (e) {
      console.error(CACHE_TAG, 'Cache set failed');
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