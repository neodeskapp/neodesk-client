// Join a server asks to leave the current server only for another host
// (L508): the same server's console on a new port is the same server.

import 'package:flutter_hbb/onboarding/onboarding_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the same host on another port is the same server', () {
    expect(isSameServer('10.10.10.74', '10.10.10.74:3375'), isTrue);
    expect(isSameServer('10.10.10.74', '10.10.10.74:5000'), isTrue);
    expect(isSameServer('10.10.10.74:21116', '10.10.10.74:3375'), isTrue);
    expect(isSameServer('Desk.Example.com', 'desk.example.com'), isTrue);
    expect(isSameServer('desk.example.com', 'https://desk.example.com:8443'),
        isTrue);
    expect(isSameServer('[2001:db8::1]:21116', '[2001:db8::1]:3375'), isTrue);
  });

  test('another host is another server', () {
    expect(isSameServer('10.10.10.74', '10.10.10.75:3375'), isFalse);
    expect(isSameServer('desk.example.com', 'desk2.example.com'), isFalse);
    expect(isSameServer('[2001:db8::1]', '[2001:db8::2]'), isFalse);
  });

  test('host of an address', () {
    expect(serverHostOf('http://10.10.10.74:5000/'), '10.10.10.74');
    expect(serverHostOf(' 10.10.10.74 '), '10.10.10.74');
    expect(serverHostOf('[::1]:3375'), '::1');
    expect(serverHostOf('2001:db8::1'), '2001:db8::1');
  });
}
