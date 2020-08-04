import 'dart:convert';
import 'dart:typed_data';

import 'package:ndef/ndef.dart';
import 'package:collection/collection.dart';

import 'utilities.dart';
import 'record/wellknown.dart';
import 'record/uri.dart';
import 'record/text.dart';
import 'record/signature.dart';
import 'record/deviceinfo.dart';
import 'record/mime.dart';
import 'record/bluetooth.dart';
import 'record/absoluteUri.dart';
import 'record/handover.dart';

/// Represent the flags in the header of a NDEF record.
class NDEFRecordFlags {
  /// Message Begin */
  bool MB = false;

  /// Message End */
  bool ME = false;

  /// Chunk Flag */
  bool CF = false;

  /// Short Record */
  bool SR = false;

  /// ID Length */
  bool IL = false;

  /// Type Name Format */
  int TNF = 0;

  NDEFRecordFlags({int data}) {
    decode(data);
  }

  int encode() {
    assert(0 <= TNF && TNF <= 7);
    return (ByteUtils.bool2int(MB) << 7) |
        (ByteUtils.bool2int(ME) << 6) |
        (ByteUtils.bool2int(CF) << 5) |
        (ByteUtils.bool2int(SR) << 4) |
        (ByteUtils.bool2int(IL) << 3) |
        (TNF & 7);
  }

  void decode(int data) {
    if (data != null) {
      assert(0 <= data && data <= 255);
      MB = ((data >> 7) & 1) == 1;
      ME = ((data >> 6) & 1) == 1;
      CF = ((data >> 5) & 1) == 1;
      SR = ((data >> 4) & 1) == 1;
      IL = ((data >> 3) & 1) == 1;
      TNF = data & 7;
    }
  }
}

/// The TNF field of a NDEF record.
enum TypeNameFormat {
  empty,
  nfcWellKnown,
  media,
  absoluteURI,
  nfcExternel,
  unknown,
  unchanged
}

/// Construct an instance of a specific type (subclass) of [NDEFRecord] according to [tnf] and [classType]
typedef NDEFRecord TypeFactory(TypeNameFormat tnf, String classType);

/// The base class of all types of records.
/// Also reprents an record of unknown type.
class NDEFRecord {
  static List<String> typePrefixes = [
    "",
    "urn:nfc:wkt:",
    "",
    "",
    "urn:nfc:ext:",
    "unknown",
    "unchanged"
  ];

  /// Predefined TNF of a specific record type.
  static const TypeNameFormat classTnf = null;

  TypeNameFormat get tnf {
    return TypeNameFormat.values[flags.TNF];
  }

  set tnf(TypeNameFormat tnf) {
    flags.TNF = TypeNameFormat.values.indexOf(tnf);
  }

  Uint8List encodedType;

  String get decodedType {
    return utf8.decode(encodedType);
  }

  set decodedType(String decodedType) {
    encodedType = utf8.encode(decodedType);
  }

  set type(Uint8List type) {
    encodedType = type;
  }

  Uint8List get type {
    if (encodedType != null) {
      return encodedType;
    } else {
      // no encodedType set, might be a directly initialized subclass
      return utf8.encode(decodedType);
    }
  }

  String get recordType {
    return typePrefixes[flags.TNF] + decodedType;
  }

  String get idString {
    return id == null ? "(empty)" : ByteUtils.list2hexString(id);
  }

  set idString(String value) {
    id = utf8.encode(value);
  }

  static const int classMinPayloadLength = 0;
  static const int classMaxPayloadLength = null;

  int get minPayloadLength {
    return classMinPayloadLength;
  }

  int get maxPayloadLength {
    return classMaxPayloadLength;
  }

  String get basicInfoString {
    var str = "id=$idString ";
    str += "typeNameFormat=$tnf ";
    str += "type=$decodedType ";
    return str;
  }

  @override
  String toString() {
    var str = "Record: ";
    str += basicInfoString;
    str += "payload=${ByteUtils.list2hexString(payload)}";
    return str;
  }

  Uint8List id;
  Uint8List payload;
  NDEFRecordFlags flags;

  /// Initialize a new [NDEFRecord], and set the corresponding fields
  NDEFRecord({int tnf, Uint8List type, Uint8List id, Uint8List payload}) {
    flags = new NDEFRecordFlags();
    if (tnf == null) {
      flags.TNF = TypeNameFormat.values.indexOf(this.tnf);
    } else {
      if (this.tnf != TypeNameFormat.empty) {
        throw "TNF has not been set in subclass of Record";
      }
      flags.TNF = tnf;
    }
    if (type != null) {
      this.type = type;
    }
    if (id != null) {
      this.id = id;
    }
    if (payload != null) {
      this.payload = payload;
    }
  }

  /// Construct an instance of a specific type (subclass) of [NDEFRecord] according to tnf and type
  static NDEFRecord defaultTypeFactory(TypeNameFormat tnf, String classType) {
    NDEFRecord record;
    if (tnf == TypeNameFormat.nfcWellKnown) {
      if (classType == UriRecord.classType) {
        record = UriRecord();
      } else if (classType == TextRecord.classType) {
        record = TextRecord();
      } else if (classType == SmartPosterRecord.classType) {
        record = SmartPosterRecord();
      } else if (classType == SignatureRecord.classType) {
        record = SignatureRecord();
      } else if (classType == HandoverRequestRecord.classType) {
        record = HandoverRequestRecord();
      } else if (classType == HandoverSelectRecord.classType) {
        record = HandoverSelectRecord();
      } else if (classType == HandoverMediationRecord.classType) {
        record = HandoverMediationRecord();
      } else if (classType == HandoverInitiateRecord.classType) {
        record = HandoverInitiateRecord();
      } else if (classType == DeviceInformationRecord.classType) {
        record = DeviceInformationRecord();
      } else {
        record = WellKnownRecord();
      }
    } else if (tnf == TypeNameFormat.media) {
      if (classType == BluetoothEasyPairingRecord.classType) {
        record = BluetoothEasyPairingRecord();
      } else if (classType == BluetoothLowEnergyRecord.classType) {
        record = BluetoothLowEnergyRecord();
      } else {
        record = MimeRecord();
      }
    } else if (tnf == TypeNameFormat.absoluteURI) {
      record = AbsoluteUriRecord();
    } else {
      record = NDEFRecord();
    }
    return record;
  }

  /// Decode a [NDEFRecord] record from raw data.
  static NDEFRecord doDecode(
      TypeNameFormat tnf, Uint8List type, Uint8List payload,
      {Uint8List id, TypeFactory typeFactory = NDEFRecord.defaultTypeFactory}) {
    NDEFRecord record = typeFactory(tnf, utf8.decode(type));
    if (payload.length < record.minPayloadLength) {
      throw "payload length must be >= ${record.minPayloadLength}";
    }
    if (record.maxPayloadLength != null &&
        payload.length < record.maxPayloadLength) {
      throw "payload length must be <= ${record.maxPayloadLength}";
    }
    record.id = id;
    record.type = type;
    // use setter for implicit decoding
    record.payload = payload;
    return record;
  }

  /// Decode a NDEF [NDEFRecord] from part of [ByteStream].
  static NDEFRecord decodeStream(ByteStream stream, TypeFactory typeFactory) {
    var flags = new NDEFRecordFlags(data: stream.readByte());

    num typeLength = stream.readByte();
    num payloadLength;
    num idLength = 0;

    if (flags.SR) {
      payloadLength = stream.readByte();
    } else {
      payloadLength = stream.readInt(4);
    }
    if (flags.IL) {
      idLength = stream.readByte();
    }

    if ([0, 5, 6].contains(flags.TNF)) {
      assert(typeLength == 0, "TYPE_LENTH must be 0 when TNF is 0,5,6");
    }
    if (flags.TNF == 0) {
      assert(idLength == 0, "ID_LENTH must be 0 when TNF is 0");
      assert(payloadLength == 0, "PAYLOAD_LENTH must be 0 when TNF is 0");
    }
    if ([1, 2, 3, 4].contains(flags.TNF)) {
      assert(typeLength > 0, "TYPE_LENTH must be > 0 when TNF is 1,2,3,4");
    }

    var type = stream.readBytes(typeLength);

    Uint8List id;
    if (idLength != 0) {
      id = stream.readBytes(idLength);
    }

    var payload = stream.readBytes(payloadLength);
    var typeNameFormat = TypeNameFormat.values[flags.TNF];

    var decoded = doDecode(typeNameFormat, type, payload,
        id: id, typeFactory: typeFactory);
    decoded.flags = flags;
    return decoded;
  }

  /// Encode this [NDEFRecord] to raw byte data.
  Uint8List encode() {
    var encoded = new List<int>();

    // check and canonicalize
    if (this.id == null) {
      flags.IL = false;
    }

    if (payload.length < 256) {
      flags.SR = true;
    }

    // flags
    var encodedFlags = flags.encode();
    encoded.add(encodedFlags);

    // type length
    assert(type.length > 0 && type.length < 256);
    encoded += [type.length];

    // use gettter for implicit encoding
    var encodedPayload = payload;

    // payload length
    if (encodedPayload.length < 256) {
      encoded += [encodedPayload.length];
    } else {
      encoded += [
        encodedPayload.length & 0xff,
        (encodedPayload.length >> 8) & 0xff,
        (encodedPayload.length >> 16) & 0xff,
        (encodedPayload.length >> 24) & 0xff,
      ];
    }

    // ID length
    if (id != null) {
      assert(id.length > 0 && id.length < 256);
      encoded += [id.length];
    }

    // type
    encoded += type;

    // ID
    if (id != null) {
      encoded += id;
    }

    // payload
    encoded += encodedPayload;

    return new Uint8List.fromList(encoded);
  }

  bool isEqual(NDEFRecord other) {
    Function eq = const ListEquality().equals;
    return (other is NDEFRecord) &&
        (tnf == other.tnf) &&
        eq(type, other.type) &&
        (id == other.id) &&
        eq(payload, other.payload);
  }
}
