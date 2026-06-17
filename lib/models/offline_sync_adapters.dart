import 'package:cloud_firestore/cloud_firestore.dart';
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

/// TypeId 3 reserved for the Firestore Timestamp adapter.
// Queued SOR payloads carry Firestore Timestamps (invoice/dispatch dates,
// queuedAt) that Hive can't serialize natively; we persist them as
// seconds+nanoseconds so they stay real Timestamps for the sync worker's
// Firestore write.
class TimestampAdapter extends TypeAdapter<Timestamp> {
  @override
  final int typeId = 3;

  @override
  Timestamp read(BinaryReader reader) {
    final seconds = reader.readInt();
    final nanoseconds = reader.readInt();
    return Timestamp(seconds, nanoseconds);
  }

  @override
  void write(BinaryWriter writer, Timestamp obj) {
    writer.writeInt(obj.seconds);
    writer.writeInt(obj.nanoseconds);
  }
}
