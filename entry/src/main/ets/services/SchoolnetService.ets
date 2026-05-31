// SchoolnetService.ets — 校园网服务
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';

const TAG = 'SchoolnetService';

export class SchoolnetService {
  private static instance: SchoolnetService;
  private http = HttpUtil.getInstance();

  private constructor() {}

  static getInstance(): SchoolnetService {
    if (!SchoolnetService.instance) SchoolnetService.instance = new SchoolnetService();
    return SchoolnetService.instance;
  }

  async getCurrentOnlineInfo(): Promise<Record<string, string | number>> {
    const resp: HttpResponse = await this.http.getWithQuery(
      'https://w.xidian.edu.cn/cgi-bin/rad_user_info',
      { 'callback': 'jsonp', '_': Date.now().toString() }
    );
    // CSV 格式: username,start_time,last_acct,flow1,0,0,sum_flow,remain_flow,ip,status,...
    let raw: string = resp.body;
    let info: Record<string, string | number> = {};

    console.info(TAG, 'rad_user_info raw: [' + raw + ']');

    // 去掉 BOM 头
    if (raw.charCodeAt(0) === 0xFEFF || raw.startsWith('\uFEFF')) {
      raw = raw.substring(1);
    }
    // 去掉末尾换行
    raw = raw.replace(/[\r\n]+$/, '');

    // 尝试 JSONP 包裹解析
    const jsonpMatch = raw.match(/^jsonp\d*\((.+)\)$/s);
    if (jsonpMatch) {
      try {
        info = JSON.parse(jsonpMatch[1]) as Record<string, string | number>;
        console.info(TAG, 'Parsed JSONP format');
      } catch (e) {
        console.warn(TAG, 'JSONP parse failed: ' + JSON.stringify(e));
      }
    }

    // 如果 JSONP 解析失败或没有 JSONP 包裹，尝试 CSV 解析
    if (Object.keys(info).length === 0) {
      const parts = raw.split(',');
      console.info(TAG, 'CSV parts count: ' + parts.length + ', parts: [' + parts.join(' | ') + ']');
      // 字段顺序:
      //   0=username, 1=start_time(上线时间戳), 2=last_acct_time,
      //   3=flow1, 4=?, 5=?,
      //   6=sum_flow(bytes总已用), 7=remain_flow(bytes剩余),
      //   8=user_ip, 9=status(0=在线)
      if (parts.length >= 10) {
        info['user_name'] = parts[0].trim();
        info['start_time'] = parseInt(parts[1].trim()) || 0;       // 上线时间戳
        info['last_acct_time'] = parseInt(parts[2].trim()) || 0;   // 最后计费时间
        info['user_ip'] = parts[8].trim();
        // 已用流量和剩余流量 — 转为数字以去掉不可见字符
        info['sum_flow'] = parseFloat(parts[6].trim()) || 0;       // 总已用字节数
        info['remain_flow'] = parseFloat(parts[7].trim()) || 0;     // 剩余字节数
        // 在线状态: 0=在线, 1=离线
        info['is_online'] = parts[9]?.trim() === '0' ? 1 : 0;
      }
      console.info(TAG, 'Parsed CSV: user=' + info['user_name']
        + ', start_time=' + info['start_time']
        + ', ip=' + info['user_ip']
        + ', sum=' + info['sum_flow']
        + ', remain=' + info['remain_flow']);
    }

    // ===== 统一字段名（兼容 JSONP 和 CSV）=====
    if (!info['sum_flow'] && info['sum_bytes']) {
      info['sum_flow'] = parseFloat(String(info['sum_bytes'])) || 0;
    }
    if (!info['remain_flow'] && info['remain_bytes']) {
      info['remain_flow'] = parseFloat(String(info['remain_bytes'])) || 0;
    }
    // 确保数值类型
    if (typeof info['sum_flow'] === 'string') {
      info['sum_flow'] = parseFloat(String(info['sum_flow'])) || 0;
    }
    if (typeof info['remain_flow'] === 'string') {
      info['remain_flow'] = parseFloat(String(info['remain_flow'])) || 0;
    }
    // JSONP 特有字段名映射
    if (info['online_ip'] && !info['user_ip']) {
      info['user_ip'] = String(info['online_ip']);
    }
    // JSONP add_time = 上线时间戳（秒）
    if (info['add_time'] && !info['add_time_ts']) {
      info['add_time_ts'] = parseInt(String(info['add_time'])) || 0;
    }
    // JSONP bytes_in = V4入流量（字节）
    if (info['bytes_in'] && !info['v4_bytes_in']) {
      info['v4_bytes_in'] = parseFloat(String(info['bytes_in'])) || 0;
    }
    // JSONP 没有 start_time，但有 sum_seconds（总已用秒数）
    if (!info['start_time'] && info['sum_seconds']) {
      info['start_time'] = parseInt(String(info['sum_seconds'])) || 0;
    }
    // start_time / last_acct_time 兼容 JSONP 字段名
    if (!info['start_time'] && info['acct_start_time']) {
      info['start_time'] = parseInt(String(info['acct_start_time'])) || 0;
    }
    if (!info['last_acct_time'] && info['acct_stop_time']) {
      info['last_acct_time'] = parseInt(String(info['acct_stop_time'])) || 0;
    }

    console.info(TAG, 'Final: user=' + info['user_name']
      + ', ip=' + info['user_ip']
      + ', sum=' + info['sum_flow']
      + ', remain=' + info['remain_flow']
      + ', start_time=' + info['start_time']);

    return info;
  }
}
