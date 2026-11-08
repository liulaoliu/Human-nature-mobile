/// 已保存文章「从哪来」的唯一合法值。
///
/// 只在**写入边界**标：原文库 / 粘贴 / EPUB / 文件。旧数据没有这个字段就保持未知，
/// 不拿 `sourceKey` 或时间反推（反推出来的来源会骗人，无法再纠正）。
/// 对应 Web 版 `src/core/articleOrigin.ts`（26 行）。
library;

import '../models/document.dart' show ArticleOrigin;

export '../models/document.dart' show ArticleOrigin;

/// 存档里写的字符串（与 Web 版一致，小写英文）。
const Map<ArticleOrigin, String> articleOriginName = {
  ArticleOrigin.library: 'library',
  ArticleOrigin.paste: 'paste',
  ArticleOrigin.epub: 'epub',
  ArticleOrigin.file: 'file',
};

/// 给人看的中文名。
const Map<ArticleOrigin, String> articleOriginLabel = {
  ArticleOrigin.library: '原文库',
  ArticleOrigin.paste: '粘贴',
  ArticleOrigin.epub: 'EPUB',
  ArticleOrigin.file: '文件',
};

/// 白名单解析：不是合法值就返回 null（当未知），绝不猜。
ArticleOrigin? parseArticleOrigin(Object? raw) {
  if (raw is! String) return null;
  for (final key in articleOriginName.keys) {
    if (articleOriginName[key] == raw) return key;
  }
  return null;
}

/// 是不是合法来源（外部输入守卫用）。
bool isArticleOrigin(Object? raw) => parseArticleOrigin(raw) != null;

/// 中文名；未知来源返回 null（界面据此不显示）。
String? articleOriginLabelOf(Object? raw) {
  final origin = parseArticleOrigin(raw);
  return origin == null ? null : articleOriginLabel[origin];
}
