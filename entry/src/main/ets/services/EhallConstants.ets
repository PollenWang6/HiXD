// EhallConstants.ets — 共享的 ehall 常量（EHALL_HEADERS、APP_PATH_MAP、extractRaw）
import { EHALL_APP_CLASS_TABLE, EHALL_APP_EXAM, EHALL_APP_SCORE, EHALL_APP_EMPTY_CLASSROOM } from './Models';

export const EHALL_HEADERS: Record<string, string> = {
  'Referer': 'http://ehall.xidian.edu.cn/new/index_xd.html',
  'Host': 'ehall.xidian.edu.cn',
  'Accept': 'application/json, text/javascript, */*; q=0.01',
  'Accept-Language': 'zh-CN,zh;q=0.9',
  'Accept-Encoding': 'gzip, deflate, br',
  'Connection': 'keep-alive',
  'X-Requested-With': 'XMLHttpRequest',
};

export const APP_PATH_MAP: Map<string, string> = new Map([
  [EHALL_APP_CLASS_TABLE, '/jwapp/sys/wdkb'],
  [EHALL_APP_EXAM, '/jwapp/sys/studentWdksapApp'],
  [EHALL_APP_SCORE, '/jwapp/sys/cjcx'],
  [EHALL_APP_EMPTY_CLASSROOM, '/jwapp/sys/kxjas'],
]);

export function findAppIdByPath(path: string): string {
  if (path.includes('wdkb')) return EHALL_APP_CLASS_TABLE;
  if (path.includes('studentWdksapApp') || path.includes('wdksap')) return EHALL_APP_EXAM;
  if (path.includes('cjcx')) return EHALL_APP_SCORE;
  if (path.includes('kxjas')) return EHALL_APP_EMPTY_CLASSROOM;
  return '';
}

export function extractRaw(body: string, tag: string): object[] {
  try {
    console.info(tag, 'extractRaw: parsing body length=' + body.length);
    const obj = JSON.parse(body) as Record<string, object>;

    const datas = obj['datas'];
    if (datas !== null && typeof datas === 'object') {
      const datasMap = datas as Record<string, object>;
      for (const key of Object.keys(datasMap)) {
        const sub = datasMap[key];
        if (sub !== null && typeof sub === 'object') {
          const subMap = sub as Record<string, object>;
          const rows = subMap['rows'];
          if (Array.isArray(rows)) {
            console.info(tag, 'extractRaw: found rows via datas.' + key + '.rows, count=' + rows.length);
            return rows as object[];
          }
          const extParams = subMap['extParams'];
          if (extParams !== null && typeof extParams === 'object') {
            const extMap = extParams as Record<string, object>;
            const extRows = extMap['rows'];
            if (Array.isArray(extRows)) {
              console.info(tag, 'extractRaw: found rows via datas.' + key + '.extParams.rows, count=' + extRows.length);
              return extRows as object[];
            }
          }
        }
      }
    }

    for (const second of Object.values(obj)) {
      if (second !== null && typeof second === 'object') {
        const smap: Record<string, object> = second as Record<string, object>;
        for (const third of Object.values(smap)) {
          if (third !== null && typeof third === 'object') {
            const tmap: Record<string, object> = third as Record<string, object>;
            const rows = tmap['rows'];
            if (Array.isArray(rows)) {
              console.info(tag, 'extractRaw: found rows via recursive, count=' + rows.length);
              return rows as object[];
            }
          }
        }
      }
    }

    console.warn(tag, 'extractRaw: no rows found in response');
    return [];
  } catch (e) {
    console.error(tag, 'extractRaw parse error: ' + JSON.stringify(e) + ' body[0:200]=' + body.substring(0, 200));
    return [];
  }
}
