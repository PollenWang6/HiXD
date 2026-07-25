// RuisiAttachmentUtil.ets — 睿思图片附件：从相册选图 → 读取字节 → 上传拿 aid
// 发帖页 / 回复页共用，避免重复编写相册选择 + 二进制读取逻辑。

import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { RuisiApiService } from './RuisiApiService';
import { UploadResult } from './RuisiModels';

// 常用表情（Unicode，无需额外资源），点击插入到光标处
export const RUISI_EMOJIS: string[] = [
  '😀', '😂', '😍', '😊', '🤔', '😅', '😎', '😭',
  '👍', '👏', '🙏', '💪', '❤️', '💔', '🔥', '✨',
  '🎉', '😴', '🤩', '😜', '🥺', '😡', '🤝', '✅',
  '🐶', '🐱', '🌟', '☀️', '🌈', '🍻', '🎓', '📚'
];

/**
 * 在指定光标位置插入文本（表情/引用），返回新文本。
 * caretPos 由调用方通过 TextArea 的 onSelectionChange 跟踪得到。
 * 插入后尝试把光标移动到插入文本末尾。
 */
export function ruisiInsertAtCaret(
  controller: TextAreaController,
  currentText: string,
  caretPos: number,
  insertText: string
): string {
  let pos = caretPos;
  if (pos < 0 || pos > currentText.length) pos = currentText.length;
  const newText = currentText.substring(0, pos) + insertText + currentText.substring(pos);
  const newCaret = pos + insertText.length;
  setTimeout(() => {
    try {
      controller.setTextSelection(newCaret, newCaret);
    } catch (e) {
      // ignore
    }
  }, 0);
  return newText;
}

export class RuisiAttachmentUtil {
  /**
   * 从相册选一张图片，读取为字节并上传到睿思。
   * @param fid 板块 id（用于获取上传凭证）
   * @returns UploadResult，成功时含 aid 与 url
   */
  static async pickAndUpload(fid: number): Promise<UploadResult> {
    const result = new UploadResult();
    try {
      const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const selectResult = await photoPicker.select(photoSelectOptions);
      if (!selectResult.photoUris || selectResult.photoUris.length === 0) {
        result.message = '未选择图片';
        return result;
      }
      const uri = selectResult.photoUris[0];
      // 与课表背景裁剪页同一套读图方式：用解码后的 path 交给 createImageSource 读取媒体库图片
      // （fileIo.openSync 无法直接开媒体库文件，无论是 /media/... 路径还是 file:// URI 都不行）
      const path = new fileUri.FileUri(uri).path;
      const rawName = path.substring(path.lastIndexOf('/') + 1) || 'upload';
      const dot = rawName.lastIndexOf('.');
      const baseName = dot > 0 ? rawName.substring(0, dot) : rawName;
      const outName = baseName + '.jpg';

      const src = image.createImageSource(path);
      const pm = await src.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
      const packer = image.createImagePacker();
      const buffer = await packer.packing(pm, { format: 'image/jpeg', quality: 90 });
      packer.release();
      pm.release();
      const bytes = new Uint8Array(buffer);

      const api = RuisiApiService.getInstance();
      return await api.uploadImage(fid, bytes, outName, 'image/jpeg');
    } catch (e) {
      result.message = '选择图片失败: ' + String(e);
      return result;
    }
  }

  private static mimeOf(filename: string): string {
    const ext = filename.toLowerCase().split('.').pop() ?? '';
    switch (ext) {
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'bmp': return 'image/bmp';
      case 'webp': return 'image/webp';
      default: return 'image/jpeg';
    }
  }
}
