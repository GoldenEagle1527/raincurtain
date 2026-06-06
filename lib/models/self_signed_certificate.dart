import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// 运行时自签证书生成器
/// 生成 RSA 2048 密钥对 + X.509 v3 自签证书，用于 WSS 服务端
class SelfSignedCertificate {
  final String certificatePem;
  final String privateKeyPem;

  SelfSignedCertificate._({
    required this.certificatePem,
    required this.privateKeyPem,
  });

  /// 异步生成自签证书（在后台 Isolate 中运行，避免阻塞主线程）
  static Future<SelfSignedCertificate> generateAsync({
    String commonName = 'RainCurtain WSS',
    int validDays = 3650,
  }) async {
    return Isolate.run(() => generate(
          commonName: commonName,
          validDays: validDays,
        ));
  }

  /// 生成自签证书（RSA 2048, SHA-256, 有效期 10 年）
  static SelfSignedCertificate generate({
    String commonName = 'RainCurtain WSS',
    int validDays = 3650,
  }) {
    // 1. 生成 RSA 2048 密钥对
    final keyPair = _generateRSAKeyPair();
    final publicKey = keyPair.publicKey as RSAPublicKey;
    final privateKey = keyPair.privateKey as RSAPrivateKey;

    // 2. 构建自签 X.509 v3 证书 DER
    final now = DateTime.now().toUtc();
    final notAfter = now.add(Duration(days: validDays));
    final serial = _randomSerialNumber();

    final certDer = _buildX509Certificate(
      publicKey: publicKey,
      privateKey: privateKey,
      serial: serial,
      notBefore: now,
      notAfter: notAfter,
      commonName: commonName,
    );

    // 3. 导出为 PEM
    final certPem = _toPem(certDer, 'CERTIFICATE');
    final keyDer = _encodePrivateKeyPkcs8(privateKey);
    final keyPem = _toPem(keyDer, 'PRIVATE KEY');

    return SelfSignedCertificate._(
      certificatePem: certPem,
      privateKeyPem: keyPem,
    );
  }

  /// 将证书和私钥写入临时文件，返回路径
  /// 支持可选的 [parentDirectory] 自定义父目录，默认在系统临时目录下创建。
  Future<({String certPath, String keyPath})> writeToTempFiles({Directory? parentDirectory}) async {
    final Directory tempDir;
    if (parentDirectory != null) {
      if (!await parentDirectory.exists()) {
        await parentDirectory.create(recursive: true);
      }
      tempDir = await parentDirectory.createTemp('rc_tls_');
    } else {
      tempDir = await Directory.systemTemp.createTemp('rc_tls_');
    }
    final certFile = File('${tempDir.path}${Platform.pathSeparator}cert.pem');
    final keyFile = File('${tempDir.path}${Platform.pathSeparator}key.pem');
    await certFile.writeAsString(certificatePem);
    await keyFile.writeAsString(privateKeyPem);
    return (certPath: certFile.path, keyPath: keyFile.path);
  }

  // ==================== 内部实现 ====================

  /// 生成 RSA 2048 密钥对
  static AsymmetricKeyPair<PublicKey, PrivateKey> _generateRSAKeyPair() {
    final secureRandom = FortunaRandom();
    final random = Random.secure();
    final seeds = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));

    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
        secureRandom,
      ));

    return keyGen.generateKeyPair();
  }

  /// 生成随机序列号（16 字节正整数）
  static BigInt _randomSerialNumber() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[0] &= 0x7F; // 确保正数
    if (bytes[0] == 0) bytes[0] = 1;
    return _bytesToBigInt(Uint8List.fromList(bytes));
  }

  /// 构建 X.509 v3 证书 DER 编码
  static Uint8List _buildX509Certificate({
    required RSAPublicKey publicKey,
    required RSAPrivateKey privateKey,
    required BigInt serial,
    required DateTime notBefore,
    required DateTime notAfter,
    required String commonName,
  }) {
    // TBSCertificate
    final tbs = _buildTBSCertificate(
      publicKey: publicKey,
      serial: serial,
      notBefore: notBefore,
      notAfter: notAfter,
      commonName: commonName,
    );

    // 签名算法：sha256WithRSAEncryption
    final signAlgoId = _encodeAlgorithmIdentifier(_oidSha256WithRsa);

    // 签名
    final signer = Signer('SHA-256/RSA')
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    final signature =
        (signer.generateSignature(tbs) as RSASignature).bytes;
    final signBits = _encodeBitString(signature);

    // Certificate = SEQUENCE { TBSCertificate, signatureAlgorithm, signature }
    return _encodeSequence([tbs, signAlgoId, signBits]);
  }

  /// 构建 TBSCertificate
  static Uint8List _buildTBSCertificate({
    required RSAPublicKey publicKey,
    required BigInt serial,
    required DateTime notBefore,
    required DateTime notAfter,
    required String commonName,
  }) {
    final parts = <Uint8List>[];

    // version: v3 (explicit tag [0])
    parts.add(_encodeExplicit(0, _encodeInteger(BigInt.from(2))));

    // serialNumber
    parts.add(_encodeInteger(serial));

    // signature algorithm: sha256WithRSAEncryption
    parts.add(_encodeAlgorithmIdentifier(_oidSha256WithRsa));

    // issuer: CN=commonName
    parts.add(_encodeName(commonName));

    // validity
    parts.add(_encodeValidity(notBefore, notAfter));

    // subject: CN=commonName (self-signed, same as issuer)
    parts.add(_encodeName(commonName));

    // subjectPublicKeyInfo
    parts.add(_encodeSubjectPublicKeyInfo(publicKey));

    return _encodeSequence(parts);
  }

  // ==================== ASN.1 DER 编码工具 ====================

  // OID: sha256WithRSAEncryption (1.2.840.113549.1.1.11)
  static final List<int> _oidSha256WithRsa = [
    0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B
  ];

  // OID: rsaEncryption (1.2.840.113549.1.1.1)
  static final List<int> _oidRsaEncryption = [
    0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01
  ];

  // OID: commonName (2.5.4.3)
  static final List<int> _oidCommonName = [0x55, 0x04, 0x03];

  static Uint8List _encodeLength(int length) {
    if (length < 0x80) {
      return Uint8List.fromList([length]);
    } else if (length < 0x100) {
      return Uint8List.fromList([0x81, length]);
    } else if (length < 0x10000) {
      return Uint8List.fromList([0x82, length >> 8, length & 0xFF]);
    } else if (length < 0x1000000) {
      return Uint8List.fromList(
          [0x83, length >> 16, (length >> 8) & 0xFF, length & 0xFF]);
    } else {
      return Uint8List.fromList([
        0x84,
        length >> 24,
        (length >> 16) & 0xFF,
        (length >> 8) & 0xFF,
        length & 0xFF
      ]);
    }
  }

  static Uint8List _encodeTLV(int tag, Uint8List value) {
    final len = _encodeLength(value.length);
    final result = Uint8List(1 + len.length + value.length);
    result[0] = tag;
    result.setRange(1, 1 + len.length, len);
    result.setRange(1 + len.length, result.length, value);
    return result;
  }

  static Uint8List _encodeSequence(List<Uint8List> items) {
    final content = _concat(items);
    return _encodeTLV(0x30, content);
  }

  static Uint8List _encodeInteger(BigInt value) {
    var bytes = _bigIntToBytes(value);
    // DER INTEGER 前导 0 处理
    if (bytes.isNotEmpty && bytes[0] & 0x80 != 0) {
      bytes = Uint8List.fromList([0, ...bytes]);
    }
    return _encodeTLV(0x02, bytes);
  }

  static Uint8List _encodeBitString(Uint8List data) {
    // 前缀 0x00 表示无未使用位
    final content = Uint8List(1 + data.length);
    content[0] = 0x00;
    content.setRange(1, content.length, data);
    return _encodeTLV(0x03, content);
  }

  static Uint8List _encodeOctetString(Uint8List data) {
    return _encodeTLV(0x04, data);
  }

  static Uint8List _encodeOID(List<int> oid) {
    return _encodeTLV(0x06, Uint8List.fromList(oid));
  }

  static Uint8List _encodeNull() {
    return Uint8List.fromList([0x05, 0x00]);
  }

  static Uint8List _encodeUTF8String(String s) {
    final bytes = Uint8List.fromList(s.codeUnits);
    return _encodeTLV(0x0C, bytes);
  }

  static Uint8List _encodeUTCTime(DateTime dt) {
    final s = '${_pad2(dt.year % 100)}${_pad2(dt.month)}${_pad2(dt.day)}'
        '${_pad2(dt.hour)}${_pad2(dt.minute)}${_pad2(dt.second)}Z';
    return _encodeTLV(0x17, Uint8List.fromList(s.codeUnits));
  }

  static Uint8List _encodeGeneralizedTime(DateTime dt) {
    final s = '${dt.year.toString().padLeft(4, '0')}${_pad2(dt.month)}${_pad2(dt.day)}'
        '${_pad2(dt.hour)}${_pad2(dt.minute)}${_pad2(dt.second)}Z';
    return _encodeTLV(0x18, Uint8List.fromList(s.codeUnits));
  }

  static Uint8List _encodeExplicit(int tag, Uint8List content) {
    return _encodeTLV(0xA0 | tag, content);
  }

  static Uint8List _encodeAlgorithmIdentifier(List<int> oid) {
    return _encodeSequence([_encodeOID(oid), _encodeNull()]);
  }

  static Uint8List _encodeName(String commonName) {
    // Name = SEQUENCE { SET { SEQUENCE { OID, UTF8String } } }
    final attrValue = _encodeSequence([
      _encodeOID(_oidCommonName),
      _encodeUTF8String(commonName),
    ]);
    final rdn = _encodeTLV(0x31, attrValue); // SET
    return _encodeSequence([rdn]);
  }

  static Uint8List _encodeValidity(DateTime notBefore, DateTime notAfter) {
    // 2050 年前使用 UTCTime, 之后用 GeneralizedTime
    final nb = notBefore.year < 2050
        ? _encodeUTCTime(notBefore)
        : _encodeGeneralizedTime(notBefore);
    final na = notAfter.year < 2050
        ? _encodeUTCTime(notAfter)
        : _encodeGeneralizedTime(notAfter);
    return _encodeSequence([nb, na]);
  }

  static Uint8List _encodeSubjectPublicKeyInfo(RSAPublicKey key) {
    // AlgorithmIdentifier: rsaEncryption
    final algo = _encodeAlgorithmIdentifier(_oidRsaEncryption);

    // RSAPublicKey = SEQUENCE { modulus INTEGER, publicExponent INTEGER }
    final rsaPubKey = _encodeSequence([
      _encodeInteger(key.modulus!),
      _encodeInteger(key.exponent!),
    ]);

    // SubjectPublicKeyInfo = SEQUENCE { algorithm, BIT STRING { RSAPublicKey } }
    return _encodeSequence([algo, _encodeBitString(rsaPubKey)]);
  }

  /// 编码 PKCS#8 PrivateKeyInfo DER
  static Uint8List _encodePrivateKeyPkcs8(RSAPrivateKey key) {
    // RSAPrivateKey SEQUENCE
    final rsaPrivKey = _encodeSequence([
      _encodeInteger(BigInt.zero), // version
      _encodeInteger(key.modulus!), // modulus
      _encodeInteger(key.publicExponent!), // publicExponent
      _encodeInteger(key.privateExponent!), // privateExponent
      _encodeInteger(key.p!), // prime1
      _encodeInteger(key.q!), // prime2
      _encodeInteger(
          key.privateExponent! % (key.p! - BigInt.one)), // exponent1
      _encodeInteger(
          key.privateExponent! % (key.q! - BigInt.one)), // exponent2
      _encodeInteger(key.q!.modInverse(key.p!)), // coefficient
    ]);

    // PrivateKeyInfo = SEQUENCE { version, algorithm, OCTET STRING { RSAPrivateKey } }
    return _encodeSequence([
      _encodeInteger(BigInt.zero), // version 0
      _encodeAlgorithmIdentifier(_oidRsaEncryption),
      _encodeOctetString(rsaPrivKey),
    ]);
  }

  /// DER → PEM
  static String _toPem(Uint8List der, String label) {
    final b64 = _base64Encode(der);
    final lines = <String>[];
    lines.add('-----BEGIN $label-----');
    for (var i = 0; i < b64.length; i += 64) {
      final end = i + 64 > b64.length ? b64.length : i + 64;
      lines.add(b64.substring(i, end));
    }
    lines.add('-----END $label-----');
    return lines.join('\n');
  }

  static String _base64Encode(Uint8List data) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final buf = StringBuffer();
    for (var i = 0; i < data.length; i += 3) {
      final b0 = data[i];
      final b1 = i + 1 < data.length ? data[i + 1] : 0;
      final b2 = i + 2 < data.length ? data[i + 2] : 0;
      buf.write(chars[(b0 >> 2) & 0x3F]);
      buf.write(chars[((b0 << 4) | (b1 >> 4)) & 0x3F]);
      buf.write(i + 1 < data.length ? chars[((b1 << 2) | (b2 >> 6)) & 0x3F] : '=');
      buf.write(i + 2 < data.length ? chars[b2 & 0x3F] : '=');
    }
    return buf.toString();
  }

  // ==================== 数值工具 ====================

  static Uint8List _bigIntToBytes(BigInt value) {
    if (value == BigInt.zero) return Uint8List.fromList([0]);
    final isNeg = value.isNegative;
    var v = isNeg ? -value : value;
    final bytes = <int>[];
    while (v > BigInt.zero) {
      bytes.insert(0, (v & BigInt.from(0xFF)).toInt());
      v >>= 8;
    }
    return Uint8List.fromList(bytes);
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  static Uint8List _concat(List<Uint8List> items) {
    final total = items.fold<int>(0, (sum, e) => sum + e.length);
    final result = Uint8List(total);
    var offset = 0;
    for (final item in items) {
      result.setRange(offset, offset + item.length, item);
      offset += item.length;
    }
    return result;
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');
}
