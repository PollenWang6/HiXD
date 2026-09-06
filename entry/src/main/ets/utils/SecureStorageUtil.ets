/**
 * SecureStorageUtil - 基于 AssetStoreKit 的安全存储工具
 * 设备级加密存储，用于密码等敏感数据，非明文落盘
 * 参考 RuisiService 的 asset 实现封装
 */

import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';

const TAG = 'SecureStorageUtil';

export class SecureStorageUtil {
  // 写入密码（已存在则更新）
  static async put(alias: string, value: string): Promise<void> {
    const aliasBytes: Uint8Array = new util.TextEncoder().encodeInto(alias);
    const secret: Uint8Array = new util.TextEncoder().encodeInto(value);
    const attr: asset.AssetMap = new Map();
    attr.set(asset.Tag.ALIAS, aliasBytes);
    attr.set(asset.Tag.SECRET, secret);
    try {
      await asset.add(attr);
    } catch (_) {
      // 已存在 → 按 alias 更新
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, aliasBytes);
      const update: asset.AssetMap = new Map();
      update.set(asset.Tag.SECRET, secret);
      try {
        await asset.update(query, update);
      } catch (e) {
        console.error(TAG, 'put update failed: ' + String(e));
        throw new Error('保存密码失败: ' + String(e));
      }
    }
  }

  // 读取密码（不存在返回空字符串）
  static async get(alias: string): Promise<string> {
    const aliasBytes: Uint8Array = new util.TextEncoder().encodeInto(alias);
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, aliasBytes);
    // 关键：必须设置 RETURN_TYPE=ALL，否则 SECRET 字段不会返回（鸿蒙 AssetStoreKit 官方要求）
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const res = await asset.query(query);
      console.info(TAG, 'get query result count: ' + res.length + ' alias: ' + alias);
      if (res.length > 0) {
        const secret = res[0].get(asset.Tag.SECRET) as Uint8Array;
        if (secret) {
          const pwd = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(secret));
          console.info(TAG, 'get success, pwd length: ' + pwd.length);
          return pwd;
        } else {
          console.error(TAG, 'get SECRET is null!');
        }
      }
    } catch (e) {
      console.error(TAG, 'get failed: ' + String(e));
    }
    return '';
  }

  // 删除密码
  static async remove(alias: string): Promise<void> {
    const aliasBytes: Uint8Array = new util.TextEncoder().encodeInto(alias);
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, aliasBytes);
    try {
      await asset.remove(query);
    } catch (e) {
      console.info(TAG, 'remove no record or failed: ' + String(e));
    }
  }
}

// 常用 alias 常量
export class SecureAlias {
  static readonly LOGIN_PASSWORD: string = 'com.hixd.login.password.v1';
  static readonly SPORT_PASSWORD: string = 'com.hixd.sport.password.v1';
  static readonly SCHOOLNET_PASSWORD: string = 'com.hixd.schoolnet.password.v1';
  static readonly PHYSICS_PWD: string = 'com.hixd.physics.pwd.v1';
  static readonly CHAOXING_PASSWORD: string = 'com.hixd.chaoxing.password.v1';
}
