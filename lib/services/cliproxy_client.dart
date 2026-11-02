import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;

/// Explicit routes: text never uses image models; images never use chat.
class CliProxyClient {
  final Dio dio;
  CliProxyClient(this.dio);
  static const textModel = 'gpt-6.1-sol';
  static const imageModel = 'gpt-image-2.5-flare';
  static const editModel = 'gpt-image-2.5-sunburst';

  static String normalizeBase(String value) {
    final base = value.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(base);
    if (uri == null || !uri.hasAuthority ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw const FormatException('请填写有效的网关地址，例如 https://你的网关/v1');
    }
    if (RegExp(r'/(responses|models|images/(generations|edits)|chat/completions)$').hasMatch(base)) {
      throw const FormatException('请填写以 /v1 结尾的基础地址，不要填写具体接口路径');
    }
    return base.endsWith('/v1') ? base : '$base/v1';
  }

  Options options(String key) => Options(
    headers: {'Authorization': 'Bearer $key'},
    receiveTimeout: const Duration(minutes: 5),
    sendTimeout: const Duration(minutes: 2),
  );

  Future<List<String>> models(String base, String key) async {
    final response = await dio.get('${normalizeBase(base)}/models', options: options(key));
    final data = response.data;
    if (data is! Map || data['data'] is! List) {
      throw const FormatException('模型列表响应格式不正确');
    }
    return (data['data'] as List).whereType<Map>()
        .map((item) => item['id']).whereType<String>().toList();
  }

  Future<String> text({required String base, required String key,
    required String model, required String instructions, required String prompt,
    List<Map<String, String>> images = const []}) async {
    final response = await dio.post('${normalizeBase(base)}/responses',
      options: options(key), data: {
        'model': model,
        'reasoning': {'effort': 'medium'},
        'instructions': instructions,
        'input': [{'role': 'user', 'content': [
          {'type': 'input_text', 'text': prompt},
          for (final image in images)
            {'type': 'input_image', 'image_url': 'data:${image['mimeType']};base64,${image['base64']}'},
        ]}],
        'stream': false,
        'store': false,
      });
    final body = response.data;
    if (body is! Map) throw const FormatException('Responses 返回格式不正确');
    if (body['error'] != null || (body['status'] != null && body['status'] != 'completed')) {
      throw StateError('Responses 未完成，请检查代理支持情况或稍后重试');
    }
    final output = body['output'];
    final texts = <String>[];
    if (output is List) {
      for (final item in output.whereType<Map>()) {
        if (item['type'] != 'message' || item['content'] is! List) continue;
        for (final part in (item['content'] as List).whereType<Map>()) {
          if (part['type'] == 'refusal') throw StateError('模型拒绝了该请求，请调整内容');
          if (part['type'] == 'output_text' && part['text'] is String) texts.add(part['text']);
        }
      }
    }
    final result = texts.join('\n').trim();
    if (result.isEmpty) throw const FormatException('Responses 未返回有效文本');
    return result;
  }

  Future<String> image({required String base, required String key,
    required String model, required String prompt, String quality = 'high',
    List<Map<String, String>> references = const []}) async {
    final fields = <String, dynamic>{
      'model': references.isEmpty ? model : editModel,
      'prompt': [prompt, for (var i = 0; i < references.length; i++)
        '参考图 ${i + 1} 对应 ${references[i]['name']}，保留其主体外貌与服装，按本页情节调整动作和场景。'].join('\n'),
      'quality': quality, 'size': '1024x1024', 'output_format': 'png', 'n': 1,
    };
    Object data = fields;
    if (references.isNotEmpty) {
      final form = FormData.fromMap(fields);
      for (var i = 0; i < references.length; i++) {
        final raw = references[i]['base64']!;
        final bytes = base64Decode(raw.startsWith('data:') ? raw.substring(raw.indexOf(',') + 1) : raw);
        final png = bytes.length >= 8 && bytes[0] == 137 && bytes[1] == 80;
        final jpg = bytes.length >= 3 && bytes[0] == 255 && bytes[1] == 216;
        final webp = bytes.length >= 12 && ascii.decode(bytes.sublist(0,4), allowInvalid: true) == 'RIFF' && ascii.decode(bytes.sublist(8,12), allowInvalid: true) == 'WEBP';
        if (!png && !jpg && !webp) throw const FormatException('参考图必须是 PNG、JPEG 或 WebP');
        final ext = png ? 'png' : (jpg ? 'jpeg' : 'webp');
        form.files.add(MapEntry('image[]', MultipartFile.fromBytes(bytes,
          filename: 'reference-$i.$ext', contentType: DioMediaType('image', ext))));
      }
      data = form;
    }
    final response = await dio.post('${normalizeBase(base)}/images/${references.isEmpty ? 'generations' : 'edits'}',
      options: options(key), data: data);
    final body = response.data;
    if (body is! Map || body['data'] is! List || (body['data'] as List).isEmpty) {
      throw const FormatException('图片接口未返回图片，请检查代理是否支持 Images API');
    }
    final first = (body['data'] as List).first;
    final encoded = first is Map ? first['b64_json'] : null;
    if (encoded is! String || encoded.isEmpty) throw const FormatException('图片接口未返回 b64_json');
    final bytes = base64Decode(encoded);
    if (bytes.isEmpty || img.decodeImage(bytes) == null) throw const FormatException('返回数据不是可解码的图片');
    return encoded;
  }
}
