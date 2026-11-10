import 'dart:convert';

import 'package:dlaoshi_app/core/ai_config.dart';
import 'package:dlaoshi_app/services/ai_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 把 OpenAI 兼容的响应体拼出来。
String chatResponse(String content) => jsonEncode(<String, Object?>{
      'choices': <Object?>[
        <String, Object?>{
          'message': <String, Object?>{'role': 'assistant', 'content': content},
        },
      ],
    });

/// 200 响应：必须带 `content-type: application/json` 且用 UTF-8 字节。
///
/// `http.Response(String, 200)` 不带 header 时会用 latin1 编 body，中文编不出来
/// 会抛 `Contains invalid characters`；真服务端不会这样，测试别自己踩这个坑。
http.Response okResponse(String content) => http.Response.bytes(
      utf8.encode(chatResponse(content)),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );

const AiConfig config = AiConfig(apiKey: 'sk-test-key');

void main() {
  group('aiContentFromResponse', () {
    test('正常取出 message.content', () {
      expect(aiContentFromResponse(chatResponse('正常')), '正常');
    });

    test('坏 JSON 抛 FormatException', () {
      expect(() => aiContentFromResponse('not json'), throwsFormatException);
    });

    test('choices 空 / message 坏 / content 非字符串都返 null', () {
      expect(aiContentFromResponse('{}'), isNull);
      expect(aiContentFromResponse('{"choices":[]}'), isNull);
      expect(aiContentFromResponse('{"choices":[{}]}'), isNull);
      expect(
        aiContentFromResponse('{"choices":[{"message":{"content":123}}]}'),
        isNull,
      );
      expect(
        aiContentFromResponse(
            '{"choices":[{"message":{"content":null}}]}'),
        isNull,
      );
    });
  });

  group('aiErrorMessage 分相', () {
    test('401 / 429 / 504 / 500 / 其它', () {
      expect(aiErrorMessage(401, ''), contains('key 不对'));
      expect(aiErrorMessage(403, ''), contains('key 不对'));
      expect(aiErrorMessage(429, ''), contains('限流'));
      expect(aiErrorMessage(504, ''), contains('超时'));
      expect(aiErrorMessage(500, ''), contains('服务端出错'));
      expect(aiErrorMessage(418, ''), contains('HTTP 418'));
    });
  });

  group('complete：请求拼装', () {
    test('200 正常：POST /chat/completions，headers 与 body 都对', () async {
      http.Request? captured;
      final client = AiClient(
        inner: MockClient((request) async {
          captured = request;
          return okResponse('跑完了');
        }),
      );
      final reply = await client.complete(config, '查词提示词');
      expect(reply.isOk, isTrue);
      expect(reply.text, '跑完了');
      expect(captured, isNotNull);
      expect(captured!.method, 'POST');
      expect(captured!.url.path, '/chat/completions');
      expect(captured!.headers['Authorization'], 'Bearer sk-test-key');
      expect(captured!.headers['Content-Type'], contains('application/json'));
      final body = jsonDecode(captured!.body) as Map;
      expect(body['model'], defaultAiModel);
      expect(body['stream'], false);
      expect(body['temperature'], defaultAiTemperature);
      expect(body['max_tokens'], 4096);
      final messages = body['messages'] as List;
      expect(messages.single['content'], '查词提示词');
      client.close();
    });

    test('响应体带 UTF-8 中文，allowMalformed 解码不炸', () async {
      final client = AiClient(
        inner: MockClient((request) async {
          return okResponse('中文表格 | 第二列');
        }),
      );
      final reply = await client.complete(config, 'x');
      expect(reply.isOk, isTrue);
      expect(reply.text, '中文表格 | 第二列');
      client.close();
    });

    test('baseUrl 不是 http(s)：直接判不合法，不发请求', () async {
      var called = false;
      final client = AiClient(
        inner: MockClient((request) async {
          called = true;
          return okResponse('正常');
        }),
      );
      final reply = await client.complete(
        config.copyWith(baseUrl: 'ftp://evil.com'),
        'x',
      );
      expect(reply.isOk, isFalse);
      expect(reply.errorKind, AiErrorKind.badResponse);
      expect(called, isFalse);
      client.close();
    });
  });

  group('complete：错误分相', () {
    Future<AiReply> withStatus(int status, [String body = '']) async {
      final client = AiClient(
        inner: MockClient((request) async => http.Response(body, status)),
      );
      final reply = await client.complete(config, 'x');
      client.close();
      return reply;
    }

    test('没填 key：直接拦下，不发请求', () async {
      var called = false;
      final client = AiClient(
        inner: MockClient((request) async {
          called = true;
          return http.Response(chatResponse('x'), 200);
        }),
      );
      final reply = await client.complete(defaultAiConfig, 'x');
      expect(reply.isOk, isFalse);
      expect(reply.errorKind, AiErrorKind.unauthorized);
      expect(called, isFalse);
      client.close();
    });

    test('401 → unauthorized，429 → rateLimited，500 → server', () async {
      final a = await withStatus(401);
      expect(a.errorKind, AiErrorKind.unauthorized);
      expect(a.error, contains('key 不对'));

      final b = await withStatus(429);
      expect(b.errorKind, AiErrorKind.rateLimited);
      expect(b.error, contains('限流'));

      final c = await withStatus(503);
      expect(c.errorKind, AiErrorKind.server);
      expect(c.error, contains('服务端出错'));
    });

    test('200 但响应不是 JSON → badResponse', () async {
      final reply = await withStatus(200, 'not json');
      expect(reply.isOk, isFalse);
      expect(reply.errorKind, AiErrorKind.badResponse);
    });

    test('200 但 choices 为空 → empty', () async {
      final reply = await withStatus(200, '{"choices":[]}');
      expect(reply.isOk, isFalse);
      expect(reply.errorKind, AiErrorKind.empty);
    });

    test('200 但 content 是空串 → empty', () async {
      final reply = await withStatus(200, chatResponse('   '));
      expect(reply.isOk, isFalse);
      expect(reply.errorKind, AiErrorKind.empty);
    });

    test('ClientException → network', () async {
      final client = AiClient(
        inner: MockClient((request) async {
          throw http.ClientException('连不上');
        }),
      );
      final reply = await client.complete(config, 'x');
      expect(reply.isOk, isFalse);
      expect(reply.errorKind, AiErrorKind.network);
      expect(reply.error, contains('连不上'));
      client.close();
    });

    test('其它异常（超时等）也归 network', () async {
      final client = AiClient(
        inner: MockClient((request) async {
          throw StateError('socket 断了');
        }),
      );
      final reply = await client.complete(config, 'x');
      expect(reply.isOk, isFalse);
      expect(reply.errorKind, AiErrorKind.network);
      client.close();
    });
  });

  group('close', () {
    test('外部传入的 client 不帮忙关', () async {
      var closed = false;
      final fake = _TrackingClient(() => closed = true);
      final client = AiClient(inner: fake);
      client.close();
      expect(closed, isFalse);
    });
  });
}

/// 只为了验证「内部 new 的才 close」这条约定。
class _TrackingClient extends http.BaseClient {
  _TrackingClient(this.onClose);

  final void Function() onClose;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      throw UnimplementedError();

  @override
  void close() => onClose();
}
