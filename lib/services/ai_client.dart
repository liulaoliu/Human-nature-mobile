library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/ai_config.dart';

/// AI 跑批的错误类型（界面据此给不同的话，别让用户对着「请求失败」猜）。
enum AiErrorKind { network, unauthorized, rateLimited, server, badResponse, empty }

/// 一次请求的结果：成功给文本，失败给分好类的错误。
class AiReply {
  const AiReply.ok(this.text) : error = null, errorKind = null;
  const AiReply.fail(this.error, this.errorKind) : text = '';

  final String text;
  final String? error;
  final AiErrorKind? errorKind;

  bool get isOk => error == null;
}

/// 把一个 HTTP 状态码 + 响应体转成给用户看的一句话。
String aiErrorMessage(int status, String body) {
  switch (status) {
    case 401:
    case 403:
      return 'key 不对或没权限（HTTP $status），去设置里检查一下';
    case 429:
      return '被限流了（HTTP 429），等一会儿再点「继续」';
    case 408:
    case 504:
      return '服务端超时（HTTP $status），可以稍后续跑';
    default:
      if (status >= 500) return '服务端出错（HTTP $status），稍后续跑就行';
      return '请求被拒绝（HTTP $status）';
  }
}

/// 从 OpenAI 兼容的 `/chat/completions` 响应里取出正文。
///
/// 坏 JSON、`choices` 空、`message.content` 不是字符串都算坏响应，
/// 不让 ViewModel 拿到一个 `null` 再去 parse。
String? aiContentFromResponse(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map) return null;
  final choices = decoded['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final first = choices.first;
  if (first is! Map) return null;
  final message = first['message'];
  if (message is! Map) return null;
  final content = message['content'];
  if (content is! String) return null;
  return content;
}

/// 客户端直连的 AI 服务（无服务端、无轮询）。
///
/// 只做三件事：拼 OpenAI 兼容的请求体 → `POST {baseUrl}/chat/completions` →
/// 把状态码/坏 JSON/网络异常翻译成分好类的 [AiReply]。**不解析业务内容**，
/// 那是 `core/analyzer_parse.dart` 的事；也不重试，重试/续跑由 ViewModel 决定。
class AiClient {
  AiClient({http.Client? inner, this._timeout = const Duration(seconds: 60)})
      : _inner = inner ?? http.Client(),
        _ownsInner = inner == null;

  final http.Client _inner;
  final bool _ownsInner;
  final Duration _timeout;

  /// 跑一条提示词，返回模型正文（可能带 ```json``` 围栏，交给解析器处理）。
  ///
  /// 「测试连接」不单独做一条通道：它只是把同一句话发出去（见
  /// `AiBatchViewModel.testConnection`），少一套并行的实现就少一处漂移。
  Future<AiReply> complete(
    AiConfig config,
    String prompt, {
    int maxTokens = 4096,
  }) async {
    if (!config.hasApiKey) {
      return const AiReply.fail('还没填 API key', AiErrorKind.unauthorized);
    }
    final uri = _completionsUri(config.baseUrl);
    if (uri == null) {
      return const AiReply.fail('服务地址不合法', AiErrorKind.badResponse);
    }
    final requestBody = jsonEncode(<String, Object?>{
      'model': config.model,
      'messages': <Object?>[
        <String, Object?>{'role': 'user', 'content': prompt},
      ],
      'temperature': config.temperature,
      'max_tokens': maxTokens,
      'stream': false,
    });

    try {
      final response = await _inner
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Bearer ${config.apiKey.trim()}',
            },
            body: requestBody,
            encoding: utf8,
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return AiReply.fail(
          aiErrorMessage(response.statusCode, response.body),
          _kindOf(response.statusCode),
        );
      }
      final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
      String? content;
      try {
        content = aiContentFromResponse(decodedBody);
      } on FormatException {
        return const AiReply.fail(
          '模型返回的不是合法 JSON，稍后再试',
          AiErrorKind.badResponse,
        );
      }
      if (content == null || content.trim().isEmpty) {
        return const AiReply.fail(
          '模型没给回内容（choices 为空）',
          AiErrorKind.empty,
        );
      }
      return AiReply.ok(content.trim());
    } on http.ClientException catch (e) {
      return AiReply.fail('网络不通：${e.message}', AiErrorKind.network);
    } on FormatException {
      return const AiReply.fail(
        '响应不是合法 JSON',
        AiErrorKind.badResponse,
      );
    } on Object catch (e) {
      // TimeoutException / SocketException / 平台通道异常都归到「网络」，
      // 用户能做的都是「检查网络再点继续」。
      return AiReply.fail('网络异常：$e', AiErrorKind.network);
    }
  }

  void close() {
    if (_ownsInner) _inner.close();
  }

  Uri? _completionsUri(String baseUrl) {
    final uri = Uri.tryParse('$baseUrl/chat/completions');
    if (uri == null || uri.host.isEmpty) return null;
    // 只认 http(s)：`file://` / `ftp://` 之类即使 host 不为空也不该被当成服务地址
    // （读路径的 `normalizeAiConfig` 已经挡了一次，这里是第二道）。
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri;
  }

  AiErrorKind _kindOf(int status) {
    if (status == 401 || status == 403) return AiErrorKind.unauthorized;
    if (status == 429) return AiErrorKind.rateLimited;
    if (status >= 500 || status == 408 || status == 504) {
      return AiErrorKind.server;
    }
    return AiErrorKind.badResponse;
  }
}
