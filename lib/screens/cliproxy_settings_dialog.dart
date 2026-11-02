import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../services/cliproxy_client.dart';

class CliProxySettingsDialog extends StatefulWidget {
  final AppSettings settings;
  const CliProxySettingsDialog({super.key, required this.settings});
  @override
  State<CliProxySettingsDialog> createState() => _CliProxySettingsDialogState();
}

class _CliProxySettingsDialogState extends State<CliProxySettingsDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _url;
  late final TextEditingController _key;
  final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 30)));
  String _quality = 'high';
  String _imageModel = CliProxyClient.imageModel;
  bool _checking = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    final profiles = widget.settings.llmProfiles.where((p) => p.id == 'llm_cliproxy');
    final profile = profiles.isEmpty ? null : profiles.first;
    _url = TextEditingController(text: profile?.baseUrl ?? '');
    _key = TextEditingController(text: profile?.apiKey ?? '');
    final images = widget.settings.imageProfiles.where((p) => p.id == 'img_cliproxy');
    if (images.isNotEmpty) {
      _quality = images.first.quality;
      if ([CliProxyClient.imageModel, CliProxyClient.editModel].contains(images.first.model)) {
        _imageModel = images.first.model;
      }
    }
  }

  @override
  void dispose() {
    _url.dispose(); _key.dispose(); _dio.close(force: true);
    super.dispose();
  }

  Future<void> _checkModels() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _checking = true; _status = null; });
    try {
      final models = await CliProxyClient(_dio).models(_url.text, _key.text.trim());
      final missing = [CliProxyClient.textModel, CliProxyClient.imageModel, CliProxyClient.editModel]
          .where((id) => !models.contains(id)).toList();
      if (mounted) setState(() => _status = missing.isEmpty
          ? '三个目标模型均已列出。此检查不代表实际生成、编辑已通过。'
          : '代理未列出：${missing.join('、')}。请确认上游支持，不要仅修改模型别名。');
    } catch (e) {
      if (mounted) setState(() => _status = e is DioException
          ? '连接失败（${e.response?.statusCode ?? e.type.name}），请检查网关、密钥和网络。'
          : '模型检查失败，请确认代理返回标准模型列表。');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _apply() {
    if (!_form.currentState!.validate()) return;
    final settings = widget.settings;
    final base = CliProxyClient.normalizeBase(_url.text);
    final key = _key.text.trim();
    settings.llmProfiles.removeWhere((p) => p.id == 'llm_cliproxy');
    settings.llmProfiles.add(LlmProfile(id: 'llm_cliproxy', name: 'cliProxy · Sol',
      providerType: 'cliproxy', baseUrl: base, apiKey: key, model: CliProxyClient.textModel));
    settings.imageProfiles.removeWhere((p) => p.id == 'img_cliproxy');
    settings.imageProfiles.add(ImageProfile(id: 'img_cliproxy', name: 'cliProxy · 图片',
      providerType: 'cliproxy', baseUrl: base, apiKey: key, model: _imageModel, quality: _quality));
    settings.activeLlmProfileId = 'llm_cliproxy';
    settings.activeImageProfileId = 'img_cliproxy';
    settings.enableImageFallback = false;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('连接 cliProxy'),
    content: SizedBox(width: 480, child: SingleChildScrollView(child: Form(key: _form,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('统一连接故事、照片识别、生图与角色参考图编辑。语音伴读仍需单独配置。'),
        const SizedBox(height: 16),
        TextFormField(controller: _url, decoration: const InputDecoration(
          labelText: 'HTTPS 网关地址', hintText: 'https://你的网关/v1',
          helperText: '手机上的 127.0.0.1 不会连接到东京服务器'),
          validator: (value) { try { CliProxyClient.normalizeBase(value ?? ''); return null; }
            catch (_) { return '请输入有效的基础地址，不含具体接口路径'; } }),
        const SizedBox(height: 12),
        TextFormField(controller: _key, obscureText: true, enableSuggestions: false, autocorrect: false,
          decoration: const InputDecoration(labelText: 'cliProxy 访问密钥'),
          validator: (value) => value == null || value.trim().isEmpty ? '请填写访问密钥' : null),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(initialValue: _imageModel,
          decoration: const InputDecoration(labelText: '无参考图时使用'),
          items: const [DropdownMenuItem(value: CliProxyClient.imageModel, child: Text('Flare · 日常生成')),
            DropdownMenuItem(value: CliProxyClient.editModel, child: Text('Sunburst · 精细生成'))],
          onChanged: (v) => setState(() => _imageModel = v!)),
        DropdownButtonFormField<String>(initialValue: _quality,
          decoration: const InputDecoration(labelText: '图片质量'),
          items: const ['auto', 'low', 'medium', 'high'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: (v) => setState(() => _quality = v!)),
        const SizedBox(height: 12),
        const Text('文本：gpt-6.1-sol · medium · Responses\n参考图编辑：gpt-image-2.5-sunburst\n启用后关闭跨厂商自动生图回退。'),
        TextButton(onPressed: _checking ? null : _checkModels,
          child: Text(_checking ? '正在检查…' : '检查模型列表')),
        if (_status != null) Text(_status!),
      ])))),
    actions: [TextButton(onPressed: _checking ? null : () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(onPressed: _checking ? null : _apply, child: const Text('保存并启用'))],
  );
}
