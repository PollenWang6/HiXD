import connection from '@ohos.net.connection';
import { BusinessError } from '@ohos.base';

const TAG = 'NetworkUtil';

type NetworkCallback = (available: boolean) => void;

/**
 * 网络监听工具类
 * 使用 @ohos.net.connection 实时监听网络变化
 */
class NetworkUtil {
  private static instance: NetworkUtil;
  private netConnection: connection.NetConnection | null = null;
  private callbacks: Array<NetworkCallback> = [];
  private _isAvailable: boolean = true;
  private registered: boolean = false;

  static getInstance(): NetworkUtil {
    if (!NetworkUtil.instance) {
      NetworkUtil.instance = new NetworkUtil();
    }
    return NetworkUtil.instance;
  }

  get isNetworkAvailable(): boolean {
    return this._isAvailable;
  }

  /**
   * 异步检测当前网络是否可用
   * netId !== 0 表示有激活的网络
   */
  async checkNow(): Promise<boolean> {
    try {
      const netHandle: connection.NetHandle = await connection.getDefaultNet();
      if (netHandle && netHandle.netId !== 0) {
        this._isAvailable = true;
        return true;
      }
      this._isAvailable = false;
      return false;
    } catch (_) {
      this._isAvailable = false;
      return false;
    }
  }

  startListen(callback: NetworkCallback): void {
    const exists: boolean = this.callbacks.some(
      (cb: NetworkCallback): boolean => cb === callback
    );
    if (exists) return;
    this.callbacks.push(callback);

    if (!this.registered) {
      this.initConnection();
      this.registered = true;
    }
  }

  stopListen(callback: NetworkCallback): void {
    const idx: number = this.callbacks.findIndex(
      (cb: NetworkCallback): boolean => cb === callback
    );
    if (idx >= 0) {
      this.callbacks.splice(idx, 1);
    }
  }

  private initConnection(): void {
    try {
      // 不传参数 = 监听默认网络（所有类型）
      this.netConnection = connection.createNetConnection();

      this.netConnection.on('netAvailable', (netHandle: connection.NetHandle): void => {
        this._isAvailable = true;
        this.notifyAll(true);
      });

      this.netConnection.on('netUnavailable', (): void => {
        this._isAvailable = false;
        this.notifyAll(false);
      });

      this.netConnection.on('netLost', (netHandle: connection.NetHandle): void => {
        setTimeout((): void => {
          this.checkNow().then((available: boolean): void => {
            if (!available) {
              this._isAvailable = false;
              this.notifyAll(false);
            }
          });
        }, 1000);
      });

      this.netConnection.register((err: BusinessError): void => {
        if (err) {
        } else {
        }
      });
    } catch (e) {
    }
  }

  private notifyAll(available: boolean): void {
    for (let i = 0; i < this.callbacks.length; i++) {
      try {
        this.callbacks[i](available);
      } catch (e) {
      }
    }
  }

  destroy(): void {
    if (this.netConnection) {
      try {
        this.netConnection.unregister((err: BusinessError): void => {
          if (err) {
          }
        });
        this.netConnection = null;
      } catch (e) {
      }
    }
    this.callbacks.length = 0;
    this.registered = false;
  }
}

export default NetworkUtil.getInstance();
