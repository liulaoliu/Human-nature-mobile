/// 全局「当前文章」的判定：存哪个键、脏值怎么清。
///
/// 为什么要有这一层：以前「本篇」是各模块自己的一份临时状态 ——
/// 背单词靠精读页的帧后回调推、产出训练/仿写的 `setArticleContext` 根本没人调、
/// 速读与跟读各记各的。用户要的是「主页面的文章决定一切」，
/// 所以「哪一篇是当前文章」必须是一份全局状态，且要落本机、重启还在。
///
/// 这一层只做纯判断，不碰存储、不碰通知：
///   - [currentArticleKey] 是 `shared_preferences` 的键名；
///   - [parseCurrentArticleId] 把读回来的字符串收拾干净（空白即「没选」）；
///   - [resolveCurrentArticleId] 拿现有文章 id 列表校验一遍 ——
///     文章被删掉之后偏好里会留一个悬空 id，必须当没选，不能拿它去查库。
library;

/// 「当前文章」在 `shared_preferences` 里的键。
const String currentArticleKey = 'reader:currentArticle';

/// 把存着的原始字符串读成 id；空、全空白都算「没选」。
String? parseCurrentArticleId(String? raw) {
  final text = (raw ?? '').trim();
  return text.isEmpty ? null : text;
}

/// 用现有文章 id 列表校验一次。
///
/// - [saved] 为空 → 返回 null（还没选过，或已经被清掉）；
/// - [saved] 不在 [existingIds] 里 → 返回 null（那篇文章被删了）；
/// - 其余情况原样返回。
///
/// [existingIds] 为空（一篇都没有）时恒为 null —— 空库时「当前文章」没有意义。
String? resolveCurrentArticleId(String? saved, Iterable<String> existingIds) {
  final id = parseCurrentArticleId(saved);
  if (id == null) return null;
  for (final existing in existingIds) {
    if (existing == id) return id;
  }
  return null;
}
