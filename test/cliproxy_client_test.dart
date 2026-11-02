import 'dart:convert';
import 'package:bookbuddy/services/cliproxy_client.dart';
import 'package:bookbuddy/services/book_engine_service.dart';
import 'package:bookbuddy/models/app_settings.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  late List<RequestOptions> calls;
  late Dio dio;
  late dynamic response;
  late CliProxyClient client;
  setUp(() {
    calls = [];
    dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      calls.add(o);
      h.resolve(Response(requestOptions: o, data: response));
    }));
    client = CliProxyClient(dio);
  });
  test('normalize root and v1 URL without duplicate suffix; reject endpoint URLs', () {
    expect(CliProxyClient.normalizeBase('https://proxy.test/'), 'https://proxy.test/v1');
    expect(CliProxyClient.normalizeBase('https://proxy.test/v1/'), 'https://proxy.test/v1');
    expect(() => CliProxyClient.normalizeBase('https://proxy.test/v1/responses'), throwsFormatException);
    expect(() => CliProxyClient.normalizeBase('https://user:key@proxy.test/v1'), throwsFormatException);
  });
  test('story engine uses Responses medium and parses output after reasoning', () async {
    response = {'status': 'completed', 'output': [
      {'type': 'reasoning', 'summary': []},
      {'type': 'message', 'content': [{'type': 'output_text', 'text': '{"title":"小猫","story":"小猫找到了家。"}'}]},
    ]};
    final story = await BookEngineService(dio: dio).composeStory(
      settings: AppSettings(llmType: 'cliproxy', llmBaseUrl: 'https://proxy.test/v1/',
        llmApiKey: 'test-key', llmModel: CliProxyClient.textModel), cards: [], brief: '小猫回家');
    expect(story.title, '小猫');
    expect(calls.single.path, 'https://proxy.test/v1/responses');
    expect(calls.single.headers['Authorization'], 'Bearer test-key');
    expect(calls.single.data['reasoning'], {'effort': 'medium'});
    expect(calls.single.data.containsKey('temperature'), isFalse);
  });
  test('vision uses input_image; incomplete and empty text are rejected', () async {
    response = {'status': 'completed', 'output': [{'type':'message', 'content':[{'type':'output_text','text':'猫'}]}]};
    Future<String> request() => client.text(base:'https://proxy.test', key:'test', model:CliProxyClient.textModel,
      instructions:'识别', prompt:'这是什么', images:[{'mimeType':'image/png','base64':'YWJj'}]);
    expect(await request(), '猫');
    expect(calls.single.data['input'][0]['content'][1]['type'], 'input_image');
    response = {'status':'incomplete','output':[]};
    await expectLater(request(), throwsStateError);
    response = {'status':'completed','output':[]};
    await expectLater(request(), throwsFormatException);
  });
  test('generation returns decodable PNG and never uses chat', () async {
    final png = base64Encode(img.encodePng(img.Image(width: 2, height: 2)));
    response = {'data':[{'b64_json':png}]};
    final result = await client.image(base:'https://proxy.test/v1', key:'test',
      model:CliProxyClient.imageModel, prompt:'小猫', quality:'medium');
    expect(img.decodeImage(base64Decode(result)), isNotNull);
    expect(calls.single.path, endsWith('/images/generations'));
    expect(calls.single.data['model'], CliProxyClient.imageModel);
    expect(calls.single.data['quality'], 'medium');
    response = {'data':[{'b64_json':'YWJj'}]};
    await expectLater(client.image(base:'https://proxy.test', key:'test', model:CliProxyClient.imageModel, prompt:'猫'), throwsFormatException);
  });
  test('multiple references become multipart image[] with Sunburst', () async {
    final png = base64Encode(img.encodePng(img.Image(width: 2, height: 2)));
    response = {'data':[{'b64_json':png}]};
    await client.image(base:'https://proxy.test', key:'test', model:CliProxyClient.imageModel,
      prompt:'保留主体，修改背景', references:[{'name':'原图','base64':png},{'name':'小猫','base64':png}]);
    expect(calls.single.path, endsWith('/images/edits'));
    final form = calls.single.data as FormData;
    expect(form.files.map((f)=>f.key), ['image[]','image[]']);
    expect(Map.fromEntries(form.fields)['model'], CliProxyClient.editModel);
    expect(form.files.first.value.contentType.toString(), 'image/png');
    expect(form.files.first.value.length, base64Decode(png).length);
  });
  test('404 image route is not retried as chat', () async {
    final failing = Dio()..interceptors.add(InterceptorsWrapper(onRequest:(o,h) {
      calls.add(o);
      h.reject(DioException(requestOptions:o, response:Response(requestOptions:o,statusCode:404), type:DioExceptionType.badResponse));
    }));
    await expectLater(CliProxyClient(failing).image(base:'https://proxy.test',key:'test',model:CliProxyClient.imageModel,prompt:'猫'), throwsA(isA<DioException>()));
    expect(calls, hasLength(1));
    expect(calls.single.path, endsWith('/images/generations'));
  });
  test('profile quality persists and cliProxy enables reference images', () {
    final profile = ImageProfile(id:'cli', name:'cli', providerType:'cliproxy', quality:'medium');
    expect(ImageProfile.fromJson(profile.toJson()).copyWith().quality, 'medium');
    expect(BookEngineService().supportsCharacterReference(type:'cliproxy',baseUrl:'https://proxy.test',model:CliProxyClient.imageModel), isTrue);
  });
  test('model discovery returns exact IDs', () async {
    response = {'data':[{'id':CliProxyClient.textModel}, {'id':CliProxyClient.imageModel}]};
    expect(await client.models('https://proxy.test','test'), [CliProxyClient.textModel,CliProxyClient.imageModel]);
    expect(calls.single.path, endsWith('/models'));
  });
}
