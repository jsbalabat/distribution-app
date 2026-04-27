import 'package:hive/hive.dart';
import 'offline_sync_contract.dart';

/// TypeId 1 reserved for OfflineSorStatus adapter
class OfflineSorStatusAdapter extends TypeAdapter<OfflineSorStatus> {
  @override
  final int typeId = 1;

  @override
  OfflineSorStatus read(BinaryReader reader) {
    final value = reader.readString();
    return OfflineSorStatus.values.byName(value);
  }

  @override
  void write(BinaryWriter writer, OfflineSorStatus obj) {
    writer.writeString(obj.name);
  }
}

/// TypeId 2 reserved for OfflineErrorCategory adapter
class OfflineErrorCategoryAdapter extends TypeAdapter<OfflineErrorCategory> {
  @override
  final int typeId = 2;

  @override
  OfflineErrorCategory read(BinaryReader reader) {
    final value = reader.readString();
    return OfflineErrorCategory.values.byName(value);
  }

  @override
  void write(BinaryWriter writer, OfflineErrorCategory obj) {
    writer.writeString(obj.name);
  }
}
