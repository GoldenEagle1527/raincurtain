import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// DNS 解析管理器
/// 纯 Dart 实现 DNS 协议（RFC 1035），通过 UDP 报文查询 DNS 服务器
class DnsManager {
  // ==================== DNS 记录类型常量 ====================

  static const int typeA = 1;
  static const int typeNS = 2;
  static const int typeCNAME = 5;
  static const int typeMX = 15;
  static const int typeTXT = 16;
  static const int typeAAAA = 28;
  static const int typeSRV = 33;
  static const int typePTR = 12;

  // ==================== 默认配置 ====================

  static const String defaultServer = '8.8.8.8';
  static const int defaultPort = 53;
  static const Duration defaultTimeout = Duration(milliseconds: 5000);
  static const int maxBatchSize = 50;
  static const int maxConcurrency = 10;
  static const int maxTimeoutMs = 30000;
  static const int maxDomainLength = 253;

  final Random _random = Random();

  // ==================== 公开方法 ====================

  /// 解析单个域名
  Future<Map<String, dynamic>> resolve({
    required String domain,
    String type = 'A',
    String? server,
    int port = defaultPort,
    int timeoutMs = 5000,
  }) async {
    // 参数校验
    if (domain.isEmpty) {
      return {'error': 'Missing domain'};
    }
    if (!_isValidDomain(domain)) {
      return {'error': 'Invalid domain format'};
    }
    if (port < 1 || port > 65535) {
      return {'error': 'Port must be between 1 and 65535'};
    }
    if (timeoutMs < 0) timeoutMs = 5000;
    if (timeoutMs > maxTimeoutMs) timeoutMs = maxTimeoutMs;

    final qtype = _typeFromString(type);
    if (qtype == -1) {
      return {'error': 'Unsupported record type: $type'};
    }

    final dnsServer = server ?? defaultServer;
    final timeout = Duration(milliseconds: timeoutMs);
    final stopwatch = Stopwatch()..start();

    try {
      final query = _buildQuery(domain, qtype);
      final response = await _sendQuery(query, dnsServer, port, timeout);
      stopwatch.stop();

      final result = _parseResponse(response, domain, type);
      result['server'] = dnsServer;
      result['timeMs'] = stopwatch.elapsedMilliseconds;
      return result;
    } on TimeoutException {
      stopwatch.stop();
      return {'error': 'Query timed out'};
    } on SocketException catch (e) {
      stopwatch.stop();
      return {'error': 'Network error: ${e.message}'};
    } catch (e) {
      stopwatch.stop();
      debugPrint('[DnsManager] resolve error: $e');
      return {'error': e.toString()};
    }
  }

  /// 批量解析
  Future<Map<String, dynamic>> resolveAll({
    required List<Map<String, dynamic>> queries,
    String? server,
    int port = defaultPort,
    int timeoutMs = 5000,
    int concurrency = 5,
  }) async {
    if (queries.isEmpty) {
      return {'error': 'queries must be a non-empty array'};
    }
    if (queries.length > maxBatchSize) {
      return {'error': 'Too many queries (max $maxBatchSize)'};
    }
    if (concurrency < 1) concurrency = 1;
    if (concurrency > maxConcurrency) concurrency = maxConcurrency;

    final stopwatch = Stopwatch()..start();
    final results = <Map<String, dynamic>>[];

    // 使用分块实现并发控制
    for (var i = 0; i < queries.length; i += concurrency) {
      final chunk = queries.sublist(
        i,
        (i + concurrency) > queries.length ? queries.length : i + concurrency,
      );

      final futures = chunk.map((q) async {
        final domain = q['domain'] as String? ?? '';
        final type = q['type'] as String? ?? 'A';
        final result = await resolve(
          domain: domain,
          type: type,
          server: server,
          port: port,
          timeoutMs: timeoutMs,
        );
        // 简化批量结果：只保留核心字段
        if (result.containsKey('error')) {
          return {
            'domain': domain,
            'type': type,
            'error': result['error'],
          };
        } else {
          return {
            'domain': result['domain'] ?? domain,
            'type': result['type'] ?? type,
            'records': result['records'] ?? [],
          };
        }
      }).toList();

      results.addAll(await Future.wait(futures));
    }

    stopwatch.stop();
    return {
      'totalTimeMs': stopwatch.elapsedMilliseconds,
      'results': results,
    };
  }

  /// 无状态管理器，提供空 dispose 以保持一致的 API
  void dispose() {}

  // ==================== DNS 报文构建 ====================

  /// 构建 DNS 查询报文
  Uint8List _buildQuery(String domain, int qtype) {
    final buffer = BytesBuilder();

    // === Header (12 bytes) ===
    // Transaction ID (2 bytes) — 随机
    final txId = _random.nextInt(0x10000);
    buffer.addByte((txId >> 8) & 0xFF);
    buffer.addByte(txId & 0xFF);

    // Flags (2 bytes): QR=0(查询), Opcode=0(标准查询), RD=1(期望递归)
    buffer.addByte(0x01); // RD=1
    buffer.addByte(0x00);

    // QDCOUNT = 1
    buffer.addByte(0x00);
    buffer.addByte(0x01);

    // ANCOUNT = 0
    buffer.addByte(0x00);
    buffer.addByte(0x00);

    // NSCOUNT = 0
    buffer.addByte(0x00);
    buffer.addByte(0x00);

    // ARCOUNT = 0
    buffer.addByte(0x00);
    buffer.addByte(0x00);

    // === Question Section ===
    // QNAME (域名编码)
    buffer.add(_encodeDomainName(domain));

    // QTYPE (2 bytes)
    buffer.addByte((qtype >> 8) & 0xFF);
    buffer.addByte(qtype & 0xFF);

    // QCLASS = IN (1) (2 bytes)
    buffer.addByte(0x00);
    buffer.addByte(0x01);

    return buffer.toBytes();
  }

  /// 域名编码为 DNS labels 格式
  /// 例: "example.com" → [7]example[3]com[0]
  Uint8List _encodeDomainName(String domain) {
    final buffer = BytesBuilder();
    final labels = domain.split('.');
    for (final label in labels) {
      if (label.isEmpty) continue;
      final bytes = label.codeUnits; // ASCII 足够
      buffer.addByte(bytes.length);
      buffer.add(bytes);
    }
    buffer.addByte(0x00); // 终止符
    return buffer.toBytes();
  }

  // ==================== DNS 报文解析 ====================

  /// 解析 DNS 响应报文
  Map<String, dynamic> _parseResponse(
      Uint8List data, String domain, String type) {
    if (data.length < 12) {
      return {'error': 'Response too short'};
    }

    // === Header 解析 ===
    // final txId = (data[0] << 8) | data[1]; // 可用于匹配
    final flags = (data[2] << 8) | data[3];
    final rcode = flags & 0x0F;
    final qdcount = (data[4] << 8) | data[5];
    final ancount = (data[6] << 8) | data[7];

    // 检查响应码
    if (rcode != 0) {
      return {'error': _rcodeToString(rcode)};
    }

    // 跳过 Question Section
    var offset = 12;
    for (var i = 0; i < qdcount; i++) {
      final result = _skipDomainName(data, offset);
      offset = result + 4; // +4 for QTYPE + QCLASS
    }

    // === Answer Section 解析 ===
    final records = <Map<String, dynamic>>[];
    for (var i = 0; i < ancount; i++) {
      if (offset >= data.length) break;

      // NAME (可能是压缩指针)
      final nameResult = _decodeDomainName(data, offset);
      offset = nameResult.endOffset;

      if (offset + 10 > data.length) break;

      // TYPE (2 bytes)
      final rrType = (data[offset] << 8) | data[offset + 1];
      offset += 2;

      // CLASS (2 bytes)
      // final rrClass = (data[offset] << 8) | data[offset + 1];
      offset += 2;

      // TTL (4 bytes)
      final ttl = (data[offset] << 24) |
          (data[offset + 1] << 16) |
          (data[offset + 2] << 8) |
          data[offset + 3];
      offset += 4;

      // RDLENGTH (2 bytes)
      final rdlength = (data[offset] << 8) | data[offset + 1];
      offset += 2;

      if (offset + rdlength > data.length) break;

      // 解析 RDATA
      final record = _parseRdata(data, offset, rdlength, rrType, ttl);
      if (record != null) {
        records.add(record);
      }

      offset += rdlength;
    }

    return {
      'domain': domain,
      'type': type,
      'records': records,
    };
  }

  /// 解析 RDATA 部分
  Map<String, dynamic>? _parseRdata(
      Uint8List data, int offset, int rdlength, int rrType, int ttl) {
    try {
      switch (rrType) {
        case typeA:
          if (rdlength != 4) return null;
          final addr =
              '${data[offset]}.${data[offset + 1]}.${data[offset + 2]}.${data[offset + 3]}';
          return {'address': addr, 'ttl': ttl};

        case typeAAAA:
          if (rdlength != 16) return null;
          final parts = <String>[];
          for (var i = 0; i < 16; i += 2) {
            parts.add(
                ((data[offset + i] << 8) | data[offset + i + 1])
                    .toRadixString(16));
          }
          return {'address': parts.join(':'), 'ttl': ttl};

        case typeCNAME:
          final name = _decodeDomainName(data, offset);
          return {'name': name.value, 'ttl': ttl};

        case typeMX:
          if (rdlength < 3) return null;
          final priority = (data[offset] << 8) | data[offset + 1];
          final exchange = _decodeDomainName(data, offset + 2);
          return {'priority': priority, 'exchange': exchange.value, 'ttl': ttl};

        case typeTXT:
          final texts = <String>[];
          var pos = offset;
          final end = offset + rdlength;
          while (pos < end) {
            final len = data[pos];
            pos++;
            if (pos + len > end) break;
            texts.add(String.fromCharCodes(data, pos, pos + len));
            pos += len;
          }
          return {'text': texts.join(''), 'ttl': ttl};

        case typeNS:
          final name = _decodeDomainName(data, offset);
          return {'nameserver': name.value, 'ttl': ttl};

        case typeSRV:
          if (rdlength < 7) return null;
          final priority = (data[offset] << 8) | data[offset + 1];
          final weight = (data[offset + 2] << 8) | data[offset + 3];
          final srvPort = (data[offset + 4] << 8) | data[offset + 5];
          final target = _decodeDomainName(data, offset + 6);
          return {
            'priority': priority,
            'weight': weight,
            'port': srvPort,
            'target': target.value,
            'ttl': ttl,
          };

        case typePTR:
          final name = _decodeDomainName(data, offset);
          return {'name': name.value, 'ttl': ttl};

        default:
          return null; // 不支持的类型直接忽略
      }
    } catch (e) {
      debugPrint('[DnsManager] Error parsing RDATA for type $rrType: $e');
      return null;
    }
  }

  // ==================== 域名编解码 ====================

  /// 解码域名（支持 DNS 压缩指针 0xC0）
  /// 返回解码后的域名和下一个字节的偏移量
  _DomainResult _decodeDomainName(Uint8List data, int offset) {
    final parts = <String>[];
    var pos = offset;
    int? jumpedFrom; // 记录第一次跳转的位置，用于计算真实偏移
    var jumps = 0;
    const maxJumps = 50; // 防止无限循环

    while (pos < data.length) {
      if (jumps > maxJumps) break;

      final len = data[pos];

      if (len == 0) {
        // 域名结束
        pos++;
        break;
      }

      // 检查是否为压缩指针 (前两位为 11)
      if ((len & 0xC0) == 0xC0) {
        if (pos + 1 >= data.length) break;
        // 记录跳转前的位置（只在第一次跳转时记录）
        jumpedFrom ??= pos + 2;
        // 计算指针偏移
        final pointer = ((len & 0x3F) << 8) | data[pos + 1];
        pos = pointer;
        jumps++;
        continue;
      }

      // 普通标签
      pos++;
      if (pos + len > data.length) break;
      parts.add(String.fromCharCodes(data, pos, pos + len));
      pos += len;
    }

    final endOffset = jumpedFrom ?? pos;
    return _DomainResult(parts.join('.'), endOffset);
  }

  /// 跳过域名字段，返回域名结束后的偏移
  int _skipDomainName(Uint8List data, int offset) {
    var pos = offset;
    while (pos < data.length) {
      final len = data[pos];
      if (len == 0) {
        return pos + 1;
      }
      if ((len & 0xC0) == 0xC0) {
        // 压缩指针占 2 字节
        return pos + 2;
      }
      pos += 1 + len;
    }
    return pos;
  }

  // ==================== UDP 查询发送 ====================

  /// 发送 UDP 查询并等待响应
  Future<Uint8List> _sendQuery(
      Uint8List query, String server, int port, Duration timeout) async {
    final ipAddress = InternetAddress.tryParse(server) ?? InternetAddress(server);
    final bindAddress = ipAddress.type == InternetAddressType.IPv6
        ? InternetAddress.anyIPv6
        : InternetAddress.anyIPv4;
    final socket = await RawDatagramSocket.bind(bindAddress, 0);
    final completer = Completer<Uint8List>();
    Timer? timer;
    StreamSubscription<RawSocketEvent>? subscription;

    try {
      socket.send(query, ipAddress, port);

      timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.completeError(TimeoutException('DNS query timed out'));
        }
      });

      subscription = socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null && !completer.isCompleted) {
            timer?.cancel();
            completer.complete(Uint8List.fromList(datagram.data));
          }
        }
      });

      return await completer.future;
    } finally {
      timer?.cancel();
      await subscription?.cancel();
      socket.close();
    }
  }

  // ==================== 工具方法 ====================

  /// 记录类型字符串 → 数字
  int _typeFromString(String type) {
    switch (type.toUpperCase()) {
      case 'A':
        return typeA;
      case 'AAAA':
        return typeAAAA;
      case 'MX':
        return typeMX;
      case 'CNAME':
        return typeCNAME;
      case 'TXT':
        return typeTXT;
      case 'NS':
        return typeNS;
      case 'SRV':
        return typeSRV;
      case 'PTR':
        return typePTR;
      default:
        return -1;
    }
  }

  /// 验证域名格式
  bool _isValidDomain(String domain) {
    if (domain.length > maxDomainLength) return false;
    if (domain.isEmpty) return false;

    // 基本格式检查：允许字母、数字、连字符、点、下划线（SRV 记录需要下划线）
    final regex = RegExp(r'^[a-zA-Z0-9._-]+(\.[a-zA-Z0-9._-]+)*$');
    return regex.hasMatch(domain);
  }

  /// DNS 响应码 → 错误描述
  String _rcodeToString(int rcode) {
    switch (rcode) {
      case 1:
        return 'FORMERR';
      case 2:
        return 'SERVFAIL';
      case 3:
        return 'NXDOMAIN';
      case 4:
        return 'NOTIMP';
      case 5:
        return 'REFUSED';
      default:
        return 'DNS error (rcode=$rcode)';
    }
  }
}

/// 域名解码结果（包含解码后的字符串和结束偏移）
class _DomainResult {
  final String value;
  final int endOffset;
  _DomainResult(this.value, this.endOffset);
}
