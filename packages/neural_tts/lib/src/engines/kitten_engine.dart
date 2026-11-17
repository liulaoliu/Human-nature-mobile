import '../engine.dart';
import '../constants.dart';
import '../download/models.dart';
import 'native_engine.dart';

class KittenEngine extends NativeEngine {
  @override
  EngineId get id => EngineId.kitten;
  @override
  Future<List<Voice>> getVoices() async => [...kittenVoices];
  @override
  Future<Map<String, dynamic>> initializationArguments() async {
    final engineDir = await downloader.getEngineDir(EngineId.kitten);
    final dictPath = '${(await downloader.getTtsDir()).path}/en-us.bin';
    return {
      'engine': 'kitten',
      'modelPath': '${engineDir.path}/${KittenVariant.nanoInt8.modelFileName}',
      'voicesPath': '${engineDir.path}/voices.npz',
      // config.json 里有 speed_priors（八个音色全是 0.8）：官方 `_prepare_inputs`
      // 会把它乘到 speed 上，所以默认语速其实是 0.8 而不是 1.0。
      'configPath': '${engineDir.path}/config.json',
      'dictPath': dictPath,
      'executionProviders': 'cpu',
      // 官方 chunk_text(max_len=400)，且切的是原文 —— 不是 Kokoro 那条 200。
      'maxChunkSize': kittenMaxChunkSize,
      'silentMode': 'obey',
      'ducking': true,
    };
  }
}
