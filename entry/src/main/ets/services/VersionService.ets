// VersionService.ets — 版本检查（从自建已备案域名 hixdapp.cn 拉取 version.json 比对）
import { http } from '@kit.NetworkKit';
import { bundleManager } from '@kit.AbilityKit';

const TAG = 'VersionService';

// 自建已备案域名（hixdapp.cn）下的 version.json
const VERSION_JSON_URL = 'https://hixdapp.cn/version.json';

export interface VersionInfo {
  version: string;
  url: string;
  changelog: string[];
}

export class VersionService {
  // 获取当前版本号
  static async getCurrentVersion(): Promise<string> {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionName;
    } catch (_) {
      return '0.0.0';
    }
  }

  // 从远程拉取版本信息
  static async fetchRemoteVersion(): Promise<VersionInfo | null> {
    try {
      const req = http.createHttp();
      const resp = await req.request(VERSION_JSON_URL, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 5000,
        readTimeout: 5000
      });
      req.destroy();
      if (resp.responseCode === 200) {
        const text: string = typeof resp.result === 'string' ? resp.result : '';
        if (text.length > 0) {
          const obj: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
          const cl: string[] = (obj['changelog'] as string[]) || [];
          return {
            version: String(obj['version'] ?? ''),
            url: String(obj['url'] ?? ''),
            changelog: cl
          };
        }
      }
    } catch (_) {}
    return null;
  }

  // 比较版本号：返回 -1(old<new), 0(equal), 1(old>new)
  static compareVersion(current: string, remote: string): number {
    const curParts = current.split('.').map(n => parseInt(n) || 0);
    const remParts = remote.split('.').map(n => parseInt(n) || 0);
    for (let i = 0; i < Math.max(curParts.length, remParts.length); i++) {
      const c = curParts[i] || 0;
      const r = remParts[i] || 0;
      if (c < r) return -1;
      if (c > r) return 1;
    }
    return 0;
  }

  // 完整检查：返回 null 表示无更新，否则返回更新信息和下载链接
  static async checkForUpdate(): Promise<VersionInfo | null> {
    try {
      const current = await VersionService.getCurrentVersion();
      const remote = await VersionService.fetchRemoteVersion();
      if (remote && remote.version.length > 0) {
        if (VersionService.compareVersion(current, remote.version) < 0) {
          return remote;
        }
      }
    } catch (_) {}
    return null;
  }
}
