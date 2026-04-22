import 'app_bootstrap.dart';
import 'core/utils/app_variant.dart';

Future<void> main() async {
  await bootstrapEmergencyOS(AppVariant.hospital);
}