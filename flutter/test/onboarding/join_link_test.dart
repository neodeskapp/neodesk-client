import 'package:flutter_hbb/onboarding/first_start_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a code and a typed server keep the scheme and port as typed', () {
    expect(joinLinkFor('http://10.0.0.5:21121', 'ABCDEF23'),
        'http://10.0.0.5:21121/join/ABCDEF23');
    expect(joinLinkFor(' HTTPS://desk.example.com:8443/ ', 'ABCDEF23'),
        'HTTPS://desk.example.com:8443/join/ABCDEF23');
    expect(joinLinkFor('desk.example.com:8443', 'ABCDEF23'),
        'https://desk.example.com:8443/join/ABCDEF23');
    expect(joinLinkFor('desk.example.com', 'ABCDEF23'),
        'https://desk.example.com/join/ABCDEF23');
  });
}
