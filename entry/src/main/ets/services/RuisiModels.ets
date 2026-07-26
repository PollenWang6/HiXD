// RuisiModels.ets — 睿思论坛数据模型
// 对标 Flutter ruisi 模块的所有数据结构

// ==================== 板块 ====================

export class Forum {
  fid: number = 0;
  name: string = '';
  threads: number = 0;
  todayPosts: number = 0;
  iconUrl: string = '';
  description: string = '';
  isHot: boolean = false;
}

export class ForumGroup {
  title: string = '';
  forums: Forum[] = [];
}

// ==================== 帖子 ====================

export class Topic {
  tid: number = 0;
  fid: number = 0;
  favId: number = 0;   // 收藏 ID（我的收藏页专用，用于删除）
  title: string = '';
  author: string = '';
  authorId: number = 0;
  views: number = 0;
  replies: number = 0;
  lastReplyTime: string = '';
  postTime: string = '';
  isStick: boolean = false;
  isImage: boolean = false;
  categoryName: string = '';
  forumName: string = ''; // 所述板块名（首页聚合流里显示，对标 Flutter categoryName=板块名）
  excerpt: string = ''; // 摘要
  avatarUrl: string = '';
}

// ==================== 楼层/帖子详情 ====================

export class ImageAttachment {
  aid: number = 0;
  url: string = '';
  thumbUrl: string = '';
  filename: string = '';
  width: number = 0;
  height: number = 0;
}

// 纯文件附件（别人发的 PDF / 文档等，对应 Discuz <dl class="tattl attnm"> 下载链接）
// 对标 Flutter _IgnoreJsOpFileCard（topic_detail_page.dart:839）
export class RuisiFileAttachment {
  url: string = '';        // 下载地址（forum.php?mod=attachment&aid=...）
  fileName: string = '';   // 文件名（带扩展名）
}

export class Post {
  pid: number = 0;
  tid: number = 0;
  authorId: number = 0;
  author: string = '';
  avatar: string = '';
  time: string = '';
  content: string = ''; // HTML 内容（已清理）
  isQuote: boolean = false;
  images: ImageAttachment[] = [];
  fileAttachments: RuisiFileAttachment[] = []; // 纯文件附件（非图片）
  index: number = 0; // 楼层号
  floor: number = 0;
  replyUrl: string = '';   // 回复该楼层的专属 URL（Android .replybtn input href）
}

// 投票
export class VoteOption {
  id: number = 0;
  text: string = '';
  voteCount: number = 0;
  percent: number = 0;
}

export class VoteResultItem {
  optionId: number = 0;
  optionText: string = '';
  voteCount: number = 0;
  percent: number = 0;
}

export class VoteStatus {
  hasVoted: boolean = false;
  votedOptions: number[] = [];
  totalVotes: number = 0;
  canVote: boolean = false;
}

export class VoteData {
  voteId: number = 0;
  question: string = '';
  options: VoteOption[] = [];
  results: VoteResultItem[] = [];
  status: VoteStatus = new VoteStatus();
  maxChoices: number = 1;
  expireTime: string = '';
  isExpired: boolean = false;
}

export class TopicDetail {
  tid: number = 0;
  fid: number = 0;
  title: string = '';
  author: string = '';
  authorId: number = 0;
  time: string = '';
  replies: number = 0;
  views: number = 0;
  isFavorite: boolean = false;
  posts: Post[] = [];
  currentPage: number = 1;
  totalPages: number = 1;
  vote: VoteData | null = null;
  fidName: string = '';
}

// ==================== 通知 ====================

export class ReplyNotification {
  id: number = 0;
  tid: number = 0;
  pid: number = 0;
  title: string = '';
  author: string = '';
  authorId: number = 0;
  time: string = '';
  content: string = '';
  avatar: string = '';
  isNew: boolean = false;
}

export class AtNotification {
  id: number = 0;
  tid: number = 0;
  pid: number = 0;
  title: string = '';
  author: string = '';
  authorId: number = 0;
  time: string = '';
  content: string = '';
  avatar: string = '';
  isNew: boolean = false;
}

// ==================== 签到 ====================

export class SignResult {
  success: boolean = false;
  message: string = '';
  // 累计签到天数（对标官方 Android/iOS：从响应 HTML「您累计已签到 N 天」取）
  totalDays: number = 0;
  // 本月已签到天数（对标官方：「您本月已累计签到 N 天」取）
  monthDays: number = 0;
  reward: string = '';
}

// 签到统计（累计/本月天数），由 getSignStats() 单独异步拉取，避免阻塞签到动作。
export interface SignStats {
  totalDays: number;
  monthDays: number;
}

// ==================== 用户信息 ====================

export class UserInfo {
  uid: number = 0;
  username: string = '';
  avatar: string = '';
  groupTitle: string = '';
  threads: number = 0;
  posts: number = 0;
  digest: number = 0;
  credits: number = 0;
  oldCredits: number = 0; // 旧积分（独立于「积分」的另一项统计）
  coins: number = 0; // 金币（独立货币，单独接口拉取）
  extCredits: Record<string, number> = {};
  joinDate: string = '';
  lastVisit: string = '';
  signature: string = '';
  email: string = '';
  gender: string = '';
  birthday: string = '';
}

// ==================== 发帖元数据 ====================

// 帖子类型 / 主题分类选项（如「原创」「求助」「二手」等），Discuz 用 typeid 提交
export class ForumTypeOption {
  id: number = 0;
  name: string = '';
}

export class PostPageMeta {
  typeOptions: ForumTypeOption[] = []; // 帖子类型选项（含 id，用于提交 typeid）
  uploadUid: string = '';
  uploadHash: string = '';
  seccodeHash: string = '';
  formhash: string = '';
  fid: number = 0;
  isImageUploadEnabled: boolean = false;
}

// 已上传的附件（图片），随帖/随回复提交时引用 aid
export class RuisiAttachment {
  aid: string = '';      // Discuz 附件 id
  name: string = '';     // 文件名
  url: string = '';      // 缩略/原图地址（仅用于预览展示）
}

// ==================== 搜索结果 ====================

export class SearchResult {
  tid: number = 0;
  fid: number = 0;
  title: string = '';
  author: string = '';
  authorId: number = 0;
  replies: number = 0;
  views: number = 0;
  postTime: string = '';
  excerpt: string = '';
  forumName: string = '';
}

export class CatIndex {
  title: string = '';
  index: number = 0;
}

export class LoginPageInfo {
  formhash: string = '';
  loginhash: string = '';
  seccodehash: string = '';
}

export class TopicListResult {
  topics: Topic[] = [];
  totalPages: number = 1;
}

// ==================== 操作结果 ====================

export class LoginResult {
  success: boolean = false;
  message: string = '';
  uid: number = 0;
  formhash: string = '';
}

export class ReplyResult {
  success: boolean = false;
  message: string = '';
}

export class NewPostResult {
  success: boolean = false;
  message: string = '';
  tid: number = 0;
}

export class FavoriteResult {
  success: boolean = false;
  message: string = '';
}

// ==================== 举报 ====================

/** 举报结果 */
export class ReportResult {
  success: boolean = false;
  message: string = '';
}

/**
 * 举报表单（动态解析自真实举报页 misc.php?mod=report&inajax=1）。
 * 睿思举报无理由分类下拉，仅有一个 JS 生成的确认项（var reasons=['...']）+
 * 一个自由描述文本框（name=message）。reasons 即该确认项文案数组。
 */
export class ReportForm {
  formhash: string = '';
  reasons: string[] = [];
}

export class UploadResult {
  success: boolean = false;
  aid: string = '';   // Discuz 附件 id（随帖/回复提交时引用）
  url: string = '';   // 附件地址（预览用）
  message: string = '';
}

// ==================== 板块常量 ====================

export class RuisiConstants {
  static readonly BASE_URL: string = 'https://rs.xidian.edu.cn';
  static readonly DOMAIN: string = 'rs.xidian.edu.cn';
  static readonly COOKIE_KEY: string = 'ruisi_cookies';
  static readonly FORMHASH_KEY: string = 'ruisi_formhash';
  static readonly UID_KEY: string = 'ruisi_uid';
  static readonly USERNAME_KEY: string = 'ruisi_username';
  static readonly PASSWORD_KEY: string = 'ruisi_password';
  static readonly LOGIN_STATUS_KEY: string = 'ruisi_login_status';

  // 固定板块 ID
  static readonly FORUM_WATER: number = 72;       // 水区(随机聊天)
  static readonly FORUM_TRADE: number = 110;      // 二手交易
  static readonly FORUM_LOST: number = 142;       // 失物招领
  static readonly FORUM_JOB: number = 553;        // 就业
  static readonly FORUM_PHOTO: number = 561;      // 摄影

  // 热门板块列表
  static readonly HOT_FORUMS: number[] = [72, 110, 142, 553, 561];
}

// ==================== 私信（短消息） ====================

// 私信会话列表项（消息中心「私信」tab 用）
export class PmConversation {
  tuid: number = 0;          // 对方 uid
  username: string = '';     // 对方用户名
  lastMessage: string = '';  // 最后一条消息预览
  time: string = '';         // 时间
  avatar: string = '';       // 对方头像
  unread: boolean = false;   // 是否有未读
}

// 私信对话中的单条消息（RuisiChatPage 用）
export class ChatMessage {
  isMe: boolean = false;     // true=自己(右侧) / false=对方(左侧)
  content: string = '';      // 消息内容（可能含 Discuz 表情 HTML，按纯文本展示）
  time: string = '';         // 发送时间
  avatar: string = '';       // 头像（对方侧用，自己侧可空）
}

// 进入私信对话页参数
export class PmParam {
  tuid: number = 0;
  username: string = '';
  constructor(tuid: number = 0, username: string = '') {
    this.tuid = tuid;
    this.username = username;
  }
}

// 发送私信结果
export class ChatResult {
  success: boolean = false;
  message: string = '';
}

// 添加好友结果
export class FriendResult {
  success: boolean = false;
  message: string = '';
}

export class ChatDetailResult {
  messages: ChatMessage[] = [];
  replyUrl: string = '';
}

// ==================== 嵌套 Navigation 导航参数 ====================
// ArkTS 要求传给 NavPathStack.pushPath 的 param 必须是显式声明的类实例，
// 内联对象字面量会触发 arkts-no-untyped-obj-literals。

export class TopicDetailParam {
  tid: number = 0;
  constructor(tid: number) {
    this.tid = tid;
  }
}

export class UserParam {
  uid: number = 0;
  username: string = '';
  constructor(uid: number = 0, username: string = '') {
    this.uid = uid;
    this.username = username;
  }
}

// 查看某用户的主题/回帖列表（个人主页「他的主题 / 他的回帖」入口用）
// uid=0 表示查看当前登录用户自己；mode: 'me'=他的主题，'reply'=他的回帖
export class UserThreadsParam {
  uid: number = 0;
  mode: string = 'me';
  constructor(uid: number = 0, mode: string = 'me') {
    this.uid = uid;
    this.mode = mode;
  }
}

export class TopicListParam {
  fid: number = 0;
  name: string = '';
  constructor(fid: number, name: string) {
    this.fid = fid;
    this.name = name;
  }
}

export class NewPostParam {
  fid: number = 0;
  forumName: string = '';
  constructor(fid: number, forumName: string = '') {
    this.fid = fid;
    this.forumName = forumName;
  }
}

// 论坛内置表情（Discuz smiley）：code 为短码 {:分类_编号:}，url 为图片完整地址，category 为分类目录名
export class Smiley {
  code: string = '';
  url: string = '';
  category: string = '';
}

// 表情分类（面板 tab 用）：key 为英文目录名（内部键），name 为中文显示名
export interface SmileyCategory {
  key: string;
  name: string;
}
