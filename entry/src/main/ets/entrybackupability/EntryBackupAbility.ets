import { hilog } from '@kit.PerformanceAnalysisKit';
import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';

const DOMAIN = 0x0000;

export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup() {
    await Promise.resolve();
  }

  async onRestore(bundleVersion: BundleVersion) {
    await Promise.resolve();
  }
}
