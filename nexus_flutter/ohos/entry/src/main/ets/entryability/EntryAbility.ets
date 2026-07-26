
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { LiveViewHelper } from '../helpers/LiveViewHelper';
import { NotificationHelper } from '../helpers/NotificationHelper';

export default class EntryAbility extends FlutterAbility {
  private liveViewHelper?: LiveViewHelper;
  private notificationHelper?: NotificationHelper;

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)

    // Register native kit method channels
    this.liveViewHelper = new LiveViewHelper(flutterEngine);
    this.notificationHelper = new NotificationHelper(flutterEngine);
  }
}
